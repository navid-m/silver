require "../src/silver"

port = 8085
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

app.html(Silver::Method::GET, "/") do |ctx|
    query = ctx.query("q") || "no query parameter"
    "<h1>Hello from Silver Web Framework</h1><p>Query parameter 'q': #{query}</p>"
end

app.run(port)
