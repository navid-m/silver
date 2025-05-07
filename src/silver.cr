require "socket"
require "option_parser"
require "http"
require "regex"
require "file"
require "log"
require "path"
require "mime"
require "../src/mappings"

DEFAULT_PORT         = 8082
ROOT                 = "./static/"
FLAG_PORT_HELP       = "the port to listen for requests"
CANNOT_OPEN_PORT_MSG = "cannot connect to specified port\n"
NOT_FOUND_MSG        = "404 Not Found\r\n"
BAD_REQ_MSG          = "400 Bad Request\r\n"
HEADER_REGEX_1       = /^(GET) (\/[\w\.\/]*) HTTP\/\d\.\d$/

class HttpRequest
    property method : String
    property path : String

    def initialize(@method : String, @path : String)
    end
end

alias Handler = Context -> HttpResponse

class Context
    getter request : HttpRequest
    getter path : String

    def initialize(@request : HttpRequest)
        @path = request.path
    end
end

class Router
    getter routes : Hash(String, Handler) = Hash(String, Handler).new

    def add_route(path : String, &block : Handler)
        routes[path] = block
    end

    def find_handler(path : String) : Handler?
        routes[path]?
    end

    def create_request(reader : IO) : Tuple(HttpRequest?, Bool)
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
            headers    = "Date: #{res.date.to_rfc2822}\r\n"

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

    def create_response(req : HttpRequest) : Tuple(HttpResponse, File?)
        response = empty_response()
        response.status = 200

        begin
            file_path = ROOT + req.path
            file = File.open(file_path)

            if File.directory?(file_path)
                file.close
                req.path += "/index.html"
                return create_response(req)
            end

            response.reader = file
            file_stat = File.info(file_path)
            response.content_length = file_stat.size
            response.last_modified = file_stat.modification_time
            response.mime = extension_to_mime(File.extname(file_path))

            return {response, file}
        rescue e
            Log.info { "404 [#{e.message}]" }
            return {create_error_404, nil}
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
        Log.info { "new connection from [#{remote_addr}]" }

        begin
            loop do
                request, keep_alive = create_request(client)

                if request.nil?
                    Log.info { "400: Bad Request" }
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
            Log.info { "connection from [#{remote_addr}] closed" }
        end
    end

    def create_response(req : HttpRequest) : Tuple(HttpResponse, File?)
        if handler = self.find_handler(req.path)
            ctx = Context.new(req)
            response = handler.call(ctx)
            return {response, nil}
        end

        response = empty_response()
        response.status = 200

        begin
            file_path = ROOT + req.path
            file = File.open(file_path)

            if File.directory?(file_path)
                file.close
                req.path += "/index.html"
                return create_response(req)
            end

            response.reader = file
            file_stat = File.info(file_path)
            response.content_length = file_stat.size
            response.last_modified = file_stat.modification_time
            response.mime = extension_to_mime(File.extname(file_path))

            return {response, file}
        rescue e
            Log.info { "404 [#{e.message}]" }
            return {create_error_404, nil}
        end
    end

    def run(port : Int, address : String = "0.0.0.0")
        server = TCPServer.new(address, port)

        Log.info { "Server is running on #{address}:#{port}" }

        begin
            while client = server.accept?
                spawn connection_handler(client)
            end
        rescue e : Exception
            Log.error { CANNOT_OPEN_PORT_MSG }
            Log.error { e.message }
        ensure
            server.close if server
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
