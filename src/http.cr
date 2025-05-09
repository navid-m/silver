require "mime"

module Silver
    HEADER_REGEX = /^(GET|POST|PUT|DELETE) (\/[\w\.\/]*(?:\?[\w\.\=\&\%\+\-]*)*) HTTP\/\d\.\d$/

    # HTTP method request type.
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
        property body : String?

        def initialize(@method : String, @path : String, @body : String? = nil)
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

    # Some response.
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
end
