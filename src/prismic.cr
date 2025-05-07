require "socket"
require "http/headers"
require "json"
require "colorize"

module Prism
    VERSION = "0.1.1"

    # HTTP Method constants
    HTTP_GET     = "GET"
    HTTP_POST    = "POST"
    HTTP_PUT     = "PUT"
    HTTP_DELETE  = "DELETE"
    HTTP_PATCH   = "PATCH"
    HTTP_OPTIONS = "OPTIONS"
    HTTP_HEAD    = "HEAD"

    # HTTP Status codes
    HTTP_STATUS = {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        500 => "Internal Server Error"
    }

    # Route class for storing route information
    class Route
        property method : String
        property path : String
        property handler : Proc(Context, String)
        property middleware : Array(Proc(Context, Nil))

        def initialize(@method, @path, @handler, @middleware = [] of Proc(Context, Nil))
        end

        def match?(request_method : String, request_path : String) : Bool
            return false unless @method == request_method

            if @path.includes?(":")
                # Handle dynamic path parameters
                path_parts = @path.split("/")
                request_parts = request_path.split("/")

                return false unless path_parts.size == request_parts.size

                path_parts.zip(request_parts).all? do |route_part, request_part|
                    route_part.starts_with?(":") || route_part == request_part
                end
            else
                # Simple path matching
                @path == request_path
            end
        end

        def extract_params(request_path : String) : Hash(String, String)
            params = {} of String => String

            path_parts = @path.split("/")
            request_parts = request_path.split("/")

            path_parts.each_with_index do |part, i|
                if part.starts_with?(":")
                    param_name = part[1..-1]  # Remove the leading colon
                    params[param_name] = request_parts[i]
                end
            end

            params
        end
    end

    # Context class for handling request/response lifecycle
    class Context
        property request_method : String
        property path : String
        property query_params : Hash(String, String)
        property path_params : Hash(String, String)
        property headers : HTTP::Headers
        property body : String
        property response_status : Int32
        property response_headers : HTTP::Headers
        property response_body : String
        property halt_called : Bool

        def initialize(@request_method, @path, @headers, @body)
            @query_params = parse_query_params(@path)
            @path_params = {} of String => String
            @response_status = 200
            @response_headers = HTTP::Headers.new
            @response_headers["Content-Type"] = "text/html; charset=utf-8"
            @response_body = ""
            @halt_called = false
        end

        private def parse_query_params(path : String) : Hash(String, String)
            params = {} of String => String

            if path.includes?("?")
                query_string = path.split("?")[1]
                path, query = path.split("?", 2)

                if query
                    query.split("&").each do |part|
                        if part.includes?("=")
                            key, value = part.split("=", 2)
                            params[key] = value
                        end
                    end
                end
            end

            params
        end

        def json(data)
            @response_headers["Content-Type"] = "application/json; charset=utf-8"
            @response_body = data.to_json
            @response_body
        end

        def status(code : Int32)
            @response_status = code
            self
        end

        def header(key : String, value : String)
            @response_headers[key] = value
            self
        end

        def halt(code : Int32, body : String = "")
            @response_status = code
            @response_body = body
            @halt_called = true
            @response_body
        end

        def params
            @query_params.merge(@path_params)
        end

        def request_body_json
            JSON.parse(@body)
        rescue
            JSON.parse("{}")
        end
    end

    # Connection pool for handling TCP connections
    class ConnectionPool
        @channel : Channel(TCPSocket)
        @max_size : Int32

        def initialize(@max_size = 50)
            @channel = Channel(TCPSocket).new(@max_size)
        end

        def get(timeout = 0.1) : TCPSocket?
            if !@channel
                nil
            else
                select
                when socket = @channel.receive
                    socket
                when timeout(Time::Span.new(seconds: timeout.to_i))
                    nil
                end
            end
        end

        def return(socket : TCPSocket)
            return if socket.closed?

            select
            when @channel.send(socket)
                # Socket returned to the pool
            end
        end

        def size
            @channel.size
        end

        def close_all
            while socket = get(0.001)
                socket.close rescue nil
            end
        end
    end

    # The main application class
    class Application
        getter routes = [] of Route
        getter middleware = [] of Proc(Context, Nil)
        getter before_hooks = [] of Proc(Context, Nil)
        getter after_hooks = [] of Proc(Context, Nil)
        property port : Int32
        property host : String
        property static_dir : String?
        property logger : Bool
        property worker_count : Int32
        property connection_pool_size : Int32
        property route_cache : Hash(String, Route)

        def initialize(@port = 3000, @host = "0.0.0.0", @logger = true, @worker_count = 12, @connection_pool_size = 500)
            @route_cache = {} of String => Route
        end

        {% for method in ["get", "post", "put", "delete", "patch", "options", "head"] %}
        def {{method.id}}(path : String, &handler : Context -> String)
            add_route({{method.upcase}}, path, handler)
        end
        {% end %}

        def add_route(method : String, path : String, handler : Proc(Context, String))
            routes << Route.new(method, path, handler, middleware.dup)
        end

        def use(&middleware : Context -> Nil)
            @middleware << middleware
        end

        def before(&hook : Context -> Nil)
            @before_hooks << hook
        end

        def after(&hook : Context -> Nil)
            @after_hooks << hook
        end

        def serve_static(dir : String)
            @static_dir = dir
        end

        def run
            server = TCPServer.new(@host, @port)
            server.tcp_nodelay = true
            connection_pool = ConnectionPool.new(@connection_pool_size)

            if @logger
                puts "Prism v#{VERSION} server started at http://#{@host}:#{@port}".colorize(:green)
                puts "Running with #{@worker_count} workers".colorize(:green)
            end
            @worker_count.times do
                spawn worker_loop(server, connection_pool)
            end
            sleep

        rescue ex
            if @logger
                puts "Server error: #{ex.message}".colorize(:red)
                puts ex.backtrace.join("\n").colorize(:red)
            end
            if connection_pool
                connection_pool.close_all
            end
            if server
                server.close rescue nil
            end
        end

        private def worker_loop(server : TCPServer, connection_pool : ConnectionPool)
            loop do
                client = server.accept
                client.tcp_nodelay = true
                client.linger = 0
                begin
                    if client
                        processing_start = Time.monotonic
                        handle_client(client)
                        processing_end = Time.monotonic
                        puts "[perf] processing took #{(processing_end - processing_start).total_milliseconds} ms"
                    end
                rescue ex
                    if @logger
                        puts "Worker error: #{ex.message}".colorize(:yellow)
                    end
                    if client
                        client.close rescue nil
                    end
                end
                Fiber.yield
            end
        rescue ex
            if @logger
                puts "Worker terminated: #{ex.message}".colorize(:red)
            end
        end

        private def handle_client(client : TCPSocket)
            start_total = Time.monotonic  # Track the true total time

            # Set socket options for better performance
            client.tcp_nodelay = true

            # Measure initial socket read time
            socket_read_start = Time.monotonic
            request_line = client.gets.to_s
            socket_read_end = Time.monotonic
            puts "[perf] initial socket read took #{(socket_read_end - socket_read_start).total_milliseconds}ms"

            return if request_line.empty?

            # Parse request line (fixed the typo)
            path_parse_start = Time.monotonic
            method, full_path, *protocol = request_line.split  # Fixed request*line -> request_line
            path, query = full_path.includes?("?") ? full_path.split("?", 2) : {full_path, nil}
            path_parse_end = Time.monotonic
            puts "[perf] path parsed in #{(path_parse_end - path_parse_start).total_milliseconds}ms"

            # Parse headers
            headers_start = Time.monotonic
            headers = HTTP::Headers.new
            while (header_line = client.gets.to_s) && !header_line.strip.empty?
                if header_line.includes?(":")
                    name, value = header_line.split(":", 2)
                    headers.add(name.strip, value.strip)
                end
            end
            headers_end = Time.monotonic
            puts "[perf] headers parsed in #{(headers_end - headers_start).total_milliseconds}ms"

            # Read body if present
            body_start = Time.monotonic
            body = ""
            if headers["Content-Length"]? && (content_length = headers["Content-Length"].to_i) > 0
                if content_length
                    body = client.read_string(content_length)
                end
            end
            body_end = Time.monotonic
            puts "[perf] body read in #{(body_end - body_start).total_milliseconds}ms"

            # Create context
            context_start = Time.monotonic
            context = Context.new(method, path, headers, body)
            context_end = Time.monotonic
            puts "[perf] context initialized in #{(context_end - context_start).total_milliseconds}ms"

            # Find matching route
            route_start = Time.monotonic
            cache_key = "#{method}:#{path}"
            route = @route_cache[cache_key]? || find_route(method, path)
            # Cache the route for faster lookups
            if route && !@route_cache[cache_key]?
                @route_cache[cache_key] = route
            end
            route_end = Time.monotonic
            puts "[perf] routing cached in #{(route_end - route_start).total_milliseconds}ms"

            # Process the request
            process_start = Time.monotonic
            process_request(context, route)
            process_end = Time.monotonic
            puts "[perf] process request done in #{(process_end - process_start).total_milliseconds}ms"

            # Send response
            response_start = Time.monotonic
            send_response(client, context)
            response_end = Time.monotonic
            puts "[perf] sending response done in #{(response_end - response_start).total_milliseconds}ms"

            # Close client
            close_start = Time.monotonic
            client.close
            close_end = Time.monotonic
            puts "[perf] closing client done in #{(close_end - close_start).total_milliseconds}ms"

            # Calculate true total time
            end_total = Time.monotonic
            true_total_ms = (end_total - start_total).total_milliseconds
            puts "TRUE_TOTAL_MS #{true_total_ms}"

            # Sum of individual steps for verification
            total_individual = (socket_read_end - socket_read_start) +
            (path_parse_end - path_parse_start) +
            (headers_end - headers_start) +
            (body_end - body_start) +
            (context_end - context_start) +
            (route_end - route_start) +
            (process_end - process_start) +
            (response_end - response_start) +
            (close_end - close_start)

            puts "SUM_OF_PARTS_MS #{total_individual.total_milliseconds}"
            puts "UNACCOUNTED_TIME_MS #{true_total_ms - total_individual.total_milliseconds}"

            if true_total_ms > 10
                puts "STATS"
                stats = GC.stats
                puts "[gc] count=#{stats}"
            end
        rescue ex
            if @logger
                puts "Request error: #{ex.message}".colorize(:red)
            end
            client.close rescue nil
        end

        private def find_route(method : String, path : String) : Route?
            routes.find { |route| route.match?(method, path) }
        end

        private def process_request(context : Context, route : Route?)
            if route
                # Extract path parameters
                context.path_params = route.extract_params(context.path)

                # Run before hooks
                @before_hooks.each do |hook|
                    hook.call(context)
                    return if context.halt_called
                end

                # Run middleware
                route.middleware.each do |middleware|
                    middleware.call(context)
                    return if context.halt_called
                end

                # Run route handler
                response = route.handler.call(context)
                context.response_body = response unless context.halt_called

                # Run after hooks
                @after_hooks.each do |hook|
                    hook.call(context)
                end
            else
                # Check for static file
                if @static_dir && context.request_method == HTTP_GET
                    serve_static_file(context)
                else
                    # No route found
                    context.status(404)
                    context.response_body = "Not Found"
                end
            end
        end

        private def serve_static_file(context : Context)
            return unless static_dir = @static_dir

            file_path = File.join(static_dir, context.path.lstrip("/"))

            if File.exists?(file_path) && !File.directory?(file_path)
                content = File.read(file_path)
                context.response_body = content

                # Set content type based on file extension
                ext = File.extname(file_path)
                case ext
                when ".html", ".htm"
                    context.header("Content-Type", "text/html; charset=utf-8")
                when ".css"
                    context.header("Content-Type", "text/css; charset=utf-8")
                when ".js"
                    context.header("Content-Type", "application/javascript; charset=utf-8")
                when ".json"
                    context.header("Content-Type", "application/json; charset=utf-8")
                when ".png"
                    context.header("Content-Type", "image/png")
                when ".jpg", ".jpeg"
                    context.header("Content-Type", "image/jpeg")
                when ".gif"
                    context.header("Content-Type", "image/gif")
                when ".svg"
                    context.header("Content-Type", "image/svg+xml")
                else
                    context.header("Content-Type", "application/octet-stream")
                end
            else
                context.status(404)
                context.response_body = "Not Found"
            end
        end

        private def send_response(client : TCPSocket, context : Context)
            status_text = HTTP_STATUS[context.response_status]? || "Unknown"

            # Send status line
            client.puts "HTTP/1.1 #{context.response_status} #{status_text}"

            # Send headers
            context.response_headers["Content-Length"] = context.response_body.bytesize.to_s
            context.response_headers["Connection"] = "close"  # No keep-alive for now
            context.response_headers.each do |name, values|
                values.each do |value|
                    client.puts "#{name}: #{value}"
                end
            end
            client.puts ""
            client.print context.response_body
            client.flush
        end
    end

    class AppContainer
        class_getter instance = new
        getter app = Application.new
    end

    module DSL
        def self.app
            AppContainer.instance.app
        end

        {% for method in ["get", "post", "put", "delete", "patch", "options", "head"] %}
        def {{method.id}}(path : String, &handler : Context -> String)
            AppContainer.instance.app.{{method.id}}(path, &handler)
        end
        {% end %}

        def use(&middleware : Context -> Nil)
            AppContainer.instance.app.use(&middleware)
        end

        def before(&hook : Context -> Nil)
            AppContainer.instance.app.before(&hook)
        end

        def after(&hook : Context -> Nil)
            AppContainer.instance.app.after(&hook)
        end

        def serve_static(dir : String)
            AppContainer.instance.app.serve_static(dir)
        end

        def run(port = 3000, host = "0.0.0.0", worker_count = 4)
            app = AppContainer.instance.app
            app.port = port
            app.host = host
            app.worker_count = worker_count
            app.run
        end
    end
    # Include the DSL methods at the top level
end

include Prism::DSL
