# Silver

### Example usage

```crystal
require "silver"

router = Silver::Router.new

router.add_route("/") do |ctx|
    res = Silver::HttpResponse.new
    body = "<h1>Hello from Silver Web Framework</h1>"
    res.mime = "text/html"
    res.data = body.to_slice
    res.content_length = body.bytesize
    res
end

router.add_route("/json") do |ctx|
    res = Silver::HttpResponse.new
    body = %({"message": "hello world"})
    res.mime = "application/json"
    res.data = body.to_slice
    res.content_length = body.bytesize
    res
end

router.run(8082)
```
