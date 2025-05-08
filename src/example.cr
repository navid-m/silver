require "../src/silver"

port = 8082
app = Silver::App.new

app.html "/" do |ctx|
    "<h1>Hello from Silver Web Framework</h1>"
end

app.get "/json" do |ctx|
    %({"message": "hello world"})
end

app.run(port)
