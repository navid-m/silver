require "../src/silver"

port = 8082
router = Silver::Router.new

# router.add_route("/") do |ctx|
#     res = HttpResponse.new
#     body = "<h1>Hello from Silver Web Framework</h1>"
#     res.mime = "text/html"
#     res.data = body.to_slice
#     res.content_length = body.bytesize
#     res
# end

router.add_route("/") do |ctx|
    res = Silver::HttpResponse.new
    body = %({"message": "hello world"})
    res.mime = "application/json"
    res.data = body.to_slice
    res.content_length = body.bytesize
    res
end

router.run(port)
