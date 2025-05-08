require "../src/silver"

port = 8082
app = Silver::App.new

app.html(Silver::Method::GET, "/") do |ctx|
    "<h1>Hello from Silver Web Framework</h1>"
end

app.json(Silver::Method::GET, "/json") do |ctx|
    %({"message": "hello world"})
end

app.json(Silver::Method::POST, "/echo") do |ctx|
    Log.info { "Body: #{ctx.request.body.inspect}" }
    body = ctx.request.body || ""
    %({"received": #{body.to_json}})
end

app.run(port)
