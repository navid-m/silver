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
