require "spec"
require "../src/silver"

describe Silver do
    describe Silver::Route do
        describe "#initialize" do
            it "should parse static routes" do
                route = Silver::Route.new("/about")
                route.param_names.should be_empty
                route.pattern.should eq("/about")
            end

            it "should parse routes with path parameters" do
                route = Silver::Route.new("/users/:id")
                route.param_names.should eq(["id"])
                route.pattern.should eq("/users/:id")
            end

            it "should parse routes with multiple path parameters" do
                route = Silver::Route.new("/api/:resource/:id")
                route.param_names.should eq(["resource", "id"])
                route.pattern.should eq("/api/:resource/:id")
            end
        end

        describe "#match" do
            it "should match static routes" do
                route = Silver::Route.new("/about")
                route.match("/about").should eq({} of String => String)
                route.match("/other").should be_nil
            end

            it "should match and extract single path parameter" do
                route = Silver::Route.new("/users/:id")
                params = route.match("/users/123")
                params.should_not be_nil
                params.not_nil!["id"].should eq("123")
                route.match("/users").should be_nil
                route.match("/users/123/profile").should be_nil
            end

            it "should match and extract multiple path parameters" do
                route = Silver::Route.new("/api/:resource/:id")
                params = route.match("/api/users/123")
                params.should_not be_nil
                params.not_nil!["resource"].should eq("users")
                params.not_nil!["id"].should eq("123")
            end

            it "should match path parameters with special characters" do
                route = Silver::Route.new("/files/:filename")
                params = route.match("/files/document.txt")
                params.should_not be_nil
                params.not_nil!["filename"].should eq("document.txt")
            end
        end
    end

    describe Silver::HttpRequest do
        describe "#method_enum" do
            it "should convert string methods to enum" do
                request = Silver::HttpRequest.new("GET", "/")
                request.method_enum.should eq(Silver::Method::GET)
                request = Silver::HttpRequest.new("POST", "/")
                request.method_enum.should eq(Silver::Method::POST)
                request = Silver::HttpRequest.new("PUT", "/")
                request.method_enum.should eq(Silver::Method::PUT)
                request = Silver::HttpRequest.new("DELETE", "/")
                request.method_enum.should eq(Silver::Method::DELETE)
            end

            it "should default to GET for unknown methods" do
                request = Silver::HttpRequest.new("PATCH", "/")
                request.method_enum.should eq(Silver::Method::GET)
            end
        end
    end

    describe Silver::Context do
        describe "#query_params" do
            it "should parse query parameters" do
                request = Silver::HttpRequest.new("GET", "/?name=John&age=25")
                context = Silver::Context.new(request)
                params = context.query_params
                params["name"].should eq("John")
                params["age"].should eq("25")
            end

            it "should handle missing query parameters" do
                request = Silver::HttpRequest.new("GET", "/")
                context = Silver::Context.new(request)
                context.query_params.should be_empty
            end

            it "should handle URL-encoded query parameters" do
                request = Silver::HttpRequest.new("GET", "/?name=John%20Doe&email=john%40example.com")
                context = Silver::Context.new(request)
                params = context.query_params
                params["name"].should eq("John Doe")
                params["email"].should eq("john@example.com")
            end
        end

        describe "#query" do
            it "should return query parameter by name" do
                request = Silver::HttpRequest.new("GET", "/?name=John&age=25")
                context = Silver::Context.new(request)
                context.query("name").should eq("John")
                context.query("age").should eq("25")
            end

            it "should return nil for missing query parameters" do
                request = Silver::HttpRequest.new("GET", "/?name=John")
                context = Silver::Context.new(request)
                context.query("age").should be_nil
            end
        end

        describe "#param" do
            it "should return path parameter by name" do
                request = Silver::HttpRequest.new("GET", "/users/123")
                params = {"id" => "123"}
                context = Silver::Context.new(request, params)
                context.param("id").should eq("123")
            end

            it "should return form parameter from POST body" do
                request = Silver::HttpRequest.new("POST", "/", "name=John&age=25")
                context = Silver::Context.new(request)
                context.param("name").should eq("John")
                context.param("age").should eq("25")
            end

            it "should prioritize path parameters over form parameters" do
                request = Silver::HttpRequest.new("POST", "/", "id=form_value")
                params = {"id" => "path_value"}
                context = Silver::Context.new(request, params)
                context.param("id").should eq("path_value")
            end

            it "should handle URL-encoded form parameters" do
                request = Silver::HttpRequest.new("POST", "/", "name=Jane%20Doe&email=jane%40example.com")
                context = Silver::Context.new(request)
                context.param("name").should eq("Jane Doe")
                context.param("email").should eq("jane@example.com")
            end
        end
    end

    describe Silver::App do
        describe "#add_route" do
            it "should add routes to the routes list" do
                app = Silver::App.new
                handler = ->(ctx : Silver::Context) { Silver::HttpResponse.new }
                app.add_route(Silver::Method::GET, "/test", &handler)
                app.routes.size.should eq(1)
                app.add_route(Silver::Method::POST, "/test", &handler)
                app.routes.size.should eq(2)
            end
        end

        describe "#find_handler" do
            it "should find handler for static routes" do
                app = Silver::App.new
                handler = ->(ctx : Silver::Context) { Silver::HttpResponse.new }
                app.add_route(Silver::Method::GET, "/test", &handler)
                request = Silver::HttpRequest.new("GET", "/test")
                result = app.find_handler(request)
                result.should_not be_nil
                result.not_nil![1].should be_empty
            end

            it "should find handler for routes with query parameters" do
                app = Silver::App.new
                handler = ->(ctx : Silver::Context) { Silver::HttpResponse.new }
                app.add_route(Silver::Method::GET, "/test", &handler)
                request = Silver::HttpRequest.new("GET", "/test?name=John")
                result = app.find_handler(request)
                result.should_not be_nil
                result.not_nil![1].should be_empty
            end

            it "should find handler for routes with path parameters" do
                app = Silver::App.new
                handler = ->(ctx : Silver::Context) { Silver::HttpResponse.new }
                app.add_route(Silver::Method::GET, "/users/:id", &handler)
                request = Silver::HttpRequest.new("GET", "/users/123")
                result = app.find_handler(request)
                result.should_not be_nil
                result.not_nil![1]["id"].should eq("123")
            end

            it "should find handler for routes with multiple path parameters" do
                app = Silver::App.new
                handler = ->(ctx : Silver::Context) { Silver::HttpResponse.new }

                app.add_route(Silver::Method::GET, "/api/:resource/:id", &handler)

                request = Silver::HttpRequest.new("GET", "/api/users/123")
                result = app.find_handler(request)
                result.should_not be_nil
                result.not_nil![1]["resource"].should eq("users")
                result.not_nil![1]["id"].should eq("123")
            end

            it "should return nil for non-existent routes" do
                app = Silver::App.new
                handler = ->(ctx : Silver::Context) { Silver::HttpResponse.new }
                app.add_route(Silver::Method::GET, "/test", &handler)
                request = Silver::HttpRequest.new("GET", "/not-found")
                app.find_handler(request).should be_nil
            end

            it "should respect HTTP method" do
                app = Silver::App.new
                handler = ->(ctx : Silver::Context) { Silver::HttpResponse.new }
                app.add_route(Silver::Method::GET, "/test", &handler)
                request = Silver::HttpRequest.new("POST", "/test")
                app.find_handler(request).should be_nil
            end
        end

        describe "#html and #json" do
            it "should register html route handlers" do
                app = Silver::App.new
                app.html(Silver::Method::GET, "/test") do |ctx|
                    "test content"
                end
                app.routes.size.should eq(1)
                app.routes[0][0].should eq(Silver::Method::GET)
                app.routes[0][1].pattern.should eq("/test")
            end

            it "should register json route handlers" do
                app = Silver::App.new
                app.json(Silver::Method::GET, "/api/test") do |ctx|
                    %({"result": "ok"})
                end
                app.routes.size.should eq(1)
                app.routes[0][0].should eq(Silver::Method::GET)
                app.routes[0][1].pattern.should eq("/api/test")
            end
        end
    end

    describe Silver::HttpResponse do
        describe "#initialize" do
            it "should initialize with default values" do
                response = Silver::HttpResponse.new
                response.status.should eq(200)
                response.content_length.should eq(0)
                response.data.should be_nil
                response.reader.should be_nil
                response.last_modified.should be_nil
            end
        end
    end
end
