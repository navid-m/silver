require "../src/silver"

port = 8085
app = Silver::App.new

app.html(Silver::Method::GET, "/") do |ctx|
    query_value = ctx.query("q") || "nothing"
    "<h1>Hello from Silver Web Framework</h1><br /><h2>q is #{query_value}"
end

app.json(Silver::Method::GET, "/json") do |ctx|
    %({"message": "hello world"})
end

app.html(Silver::Method::GET, "/greet/:name/:surname") do |ctx|
    name = ctx.param("name")
    surname = ctx.param("surname")
    "<h1>Hello, #{name} #{surname}!</h1>"
end

app.json(Silver::Method::POST, "/echo") do |ctx|
    Log.info { "Body: #{ctx.request.body.inspect}" }
    body = ctx.request.body || ""
    %({"received": #{body.to_json}})
end

app.run(port)
