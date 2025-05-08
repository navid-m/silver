require "socket"
require "option_parser"
require "http"
require "regex"
require "file"
require "log"
require "json"
require "path"
require "mime"
require "../src/mappings"

module Silver
    DEFAULT_PORT         = 8082
    ROOT                 = "./static/"
    FLAG_PORT_HELP       = "the port to listen for requests"
    CANNOT_OPEN_PORT_MSG = "cannot connect to specified port\n"
    NOT_FOUND_MSG        = "404 Not Found\r\n"
    BAD_REQ_MSG          = "400 Bad Request\r\n"
    HEADER_REGEX_1       = /^(GET) (\/[\w\.\/]*) HTTP\/\d\.\d$/

    enum Method
        GET
        POST
        PUT
        DELETE
    end

    # Some request.
    class HttpRequest
        property method : String
        property path : String

        def initialize(@method : String, @path : String)
        end

        def method_enum : Method
            case @method
            when "GET"    then Method::GET
            when "POST"   then Method::POST
            when "PUT"    then Method::PUT
            when "DELETE" then Method::DELETE
            else               Method::GET
            end
        end
    end

    alias Handler = Context -> HttpResponse

    # The context for some request.
    class Context
        getter request : HttpRequest
        getter path : String

        def initialize(@request : HttpRequest)
            @path = request.path
        end

        def query_params : Hash(String, String)
            params = Hash(String, String).new
            if path.includes?("?")
                path.split("?")[1].split("&").each do |param|
                    if param.includes?("=")
                        key, value = param.split("=", 2)
                        params[key] = URI.decode(value)
                    end
                end
            end
            params
        end

        def query(name : String) : String?
            query_params[name]?
        end

        # TODO : IMPLEMENT
        def param(name : String) : String?
            nil
        end
    end

    # The control-point of the application.
    # Includes caching and server-run mechanisms.
    class App
        getter routes : Hash(Tuple(Method, String), Handler) = Hash(Tuple(Method, String), Handler).new
        @cache = Hash(String, Tuple(HttpResponse, Time)).new

        # Add some route to the route list
        def add_route(method : Method, path : String, &block : Handler)
            routes[{method, path}] = block
        end

        # Find a handler given a route, the path may be invalid and this
        # is accounted for.
        def find_handler(req : HttpRequest) : Handler?
            routes[{req.method_enum, req.path}]?
        end

        # Create a response corresponding to a HTTP request.
        def create_response(req : HttpRequest) : Tuple(HttpResponse, File?)
            if handler = self.find_handler(req)
                response = handler.call(Context.new(req))
                return {response, nil}
            end

            file_path = ROOT + req.path

            if cache_entry = @cache[req.path]?
                begin
                    stat = File.info(file_path)
                    cached_mtime = cache_entry[1]

                    if stat.modification_time == cached_mtime
                        return {cache_entry[0], nil}
                    end
                rescue
                    @cache.delete(req.path)
                end
            end

            response = empty_response()
            response.status = 200

            begin
                file = File.open(file_path, "r")

                if File.directory?(file_path)
                    file.close
                    req.path += "/index.html"
                    return create_response(req)
                end

                file_stat = File.info(file_path)
                content_length = file_stat.size
                mime = extension_to_mime(File.extname(file_path))
                last_modified = file_stat.modification_time
                data = file.getb_to_end

                file.close

                response.data = data
                response.content_length = content_length
                response.mime = mime
                response.last_modified = last_modified

                @cache[req.path] = {response, last_modified}
                return {response, nil}
            rescue e
                Log.info { "404 [#{e.message}]" }
                return {create_error_404, nil}
            end
        end

        # Create some request
        # Returns a tuple of the request itself and the status of keep-alive as bool
        def create_request(reader : TCPSocket) : Tuple(HttpRequest?, Bool)
            begin
                first_line = reader.gets || ""
                return {nil, false} if first_line.empty?

                match = first_line.match(HEADER_REGEX_1)
                return {nil, false} if match.nil?

                method = match[1]
                path = match[2]
                keep_alive = false

                while (line = reader.gets)
                    break if line.strip.empty?
                    keep_alive ||= line.downcase.includes?("connection: keep-alive")
                end

                return {HttpRequest.new(method, path), keep_alive}
            rescue e
                Log.error { e.message }
                return {nil, false}
            end
        end

        def write_response(res : HttpResponse, socket : TCPSocket, keep_alive : Bool) : Bool
            begin
                first_line = "HTTP/1.1 #{res.status} #{http_code_to_status(res.status)}\r\n"
                headers = "Date: #{res.date.to_rfc2822}\r\n"

                headers += "Server: Silver/1.0\r\n"
                headers += "Content-Type: #{res.mime};\r\n"
                headers += "Content-Length: #{res.content_length}\r\n"
                headers += "Connection: #{keep_alive ? "keep-alive" : "close"}\r\n"

                if res.reader && res.last_modified
                    headers += "Last-Modified: #{res.last_modified.not_nil!.to_rfc2822}\r\n"
                end

                socket.write("#{first_line}#{headers}\r\n".to_slice)

                if reader = res.reader
                    IO.copy(reader, socket, res.content_length)
                elsif data = res.data
                    socket.write(data)
                end

                socket.flush
                return true
            rescue e
                Log.error { "Error writing response: #{e.message}" }
                return false
            end
        end

        def empty_response : HttpResponse
            response = HttpResponse.new
            response.status = 200
            response.date = Time.utc
            response.mime = extension_to_mime(".txt")
            response.content_length = 0_i64
            response
        end

        def create_error_400 : HttpResponse
            resp = empty_response()
            resp.status = 400
            resp.data = BAD_REQ_MSG.to_slice
            resp.content_length = resp.data.not_nil!.size.to_i64
            resp
        end

        def create_error_404 : HttpResponse
            resp = empty_response()
            resp.status = 404
            resp.data = NOT_FOUND_MSG.to_slice
            resp.content_length = resp.data.not_nil!.size.to_i64
            resp
        end

        def connection_handler(client : TCPSocket)
            remote_addr = client.remote_address
            # Log.info { "new connection from [#{remote_addr}]" }

            begin
                loop do
                    request, keep_alive = create_request(client)

                    if request.nil?
                        # Log.info { "400: Bad Request" }
                        write_response(create_error_400(), client, false)
                        break
                    end

                    response, file = create_response(request)
                    write_response(response, client, keep_alive)
                    file.try &.close

                    break unless keep_alive
                end
            rescue e
                Log.error { "Error handling connection: #{e.message}" }
            ensure
                client.close
              # Log.info { "connection from [#{remote_addr}] closed" }
            end
        end

        def json(method : Method, path : String, &block : Context -> String)
            add_route(method, path) do |ctx|
                response = empty_response()
                result = block.call(ctx)
                response.mime = "application/json"
                response.data = result.to_slice
                response.content_length = result.bytesize.to_i64
                response
            end
        end

        def html(method : Method, path : String, &block : Context -> String)
            add_route(method, path) do |ctx|
                response = empty_response()
                result = block.call(ctx)
                response.mime = "text/html"
                response.data = result.to_slice
                response.content_length = result.bytesize.to_i64
                response
            end
        end

        def run(port : Int, address : String = "0.0.0.0")
            server = TCPServer.new(address, port)

            Log.info { "Server is running on #{address}:#{port}" }

            begin
                semaphore = Channel(Nil).new(1000)

                while client = server.accept?
                    spawn do
                        semaphore.send(nil)
                        begin
                            connection_handler(client)
                        ensure
                            semaphore.receive
                        end
                    end
                end
            rescue e : Exception
                Log.error { CANNOT_OPEN_PORT_MSG }
                Log.error { e.message }
            ensure
                server.close if server
            end
        end
    end
end

class HttpResponse
    property status : Int32
    property date : Time
    property content_length : Int64
    property data : Bytes?
    property reader : IO?
    property last_modified : Time?
    property mime : String

    def initialize
        @status = 200
        @date = Time.utc
        @content_length = 0_i64
        @data = nil
        @reader = nil
        @last_modified = nil
        @mime = extension_to_mime(".txt")
    end
end
