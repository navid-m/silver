# Silver

### Example usage

```crystal
require "silver"

app = Silver::App.new

app.html(Silver::Method::GET, "/") do |ctx|
    "<h1>Hello from Silver Web Framework</h1>"
end

app.json(Silver::Method::GET, "/json") do |ctx|
    %({"message": "hello world"})
end

app.run(8082)
```
