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

def http_code_to_status(code : Int32) : String
    case code
    when 200
        "OK"
    when 400
        "Bad Request"
    when 403
        "Forbidden"
    when 404
        "Not Found"
    else
        Log.error { "unknown status code [#{code}]" }
        "501 Not Implemented"
    end
end

def extension_to_mime(file_ext : String) : String
    case file_ext
    when ".html", ".htm"
        "text/html"
    when ".js"
        "application/javascript"
    when ".json"
        "application/json"
    when ".xml"
        "application/xml"
    when ".zip"
        "application/zip"
    when ".wma"
        "audio/x-ms-wma"
    when ".txt", ".log"
        "text/plain"
    when ".ttf"
        "application/x-font-ttf"
    when ".tex"
        "application/x-tex"
    when ".sh"
        "application/x-sh"
    when ".py"
        "text/x-python"
    when ".png"
        "image/png"
    when ".pdf"
        "application/pdf"
    when ".mpeg", ".mpa"
        "video/mpeg"
    when ".mp4"
        "video/mp4"
    when ".mp3"
        "audio/mpeg"
    when ".jpg", ".jpeg"
        "image/jpeg"
    when ".java"
        "text/x-java-source"
    when ".jar"
        "application/java-archive"
    when ".gif"
        "image/gif"
    when ".cpp"
        "text/x-c"
    when ".bmp"
        "image/bmp"
    when ".avi"
        "video/x-msvideo"
    when ".mkv"
        "video/x-matroska"
    when ".ico"
        "image/x-icon"
    else
        "application/octet-stream"
    end
end
