
require "../src/prismic"

# Logger middleware
use do |ctx|
  puts "[#{Time.utc}] #{ctx.request_method} #{ctx.path}"
end

# CORS middleware
use do |ctx|
  ctx.header("Access-Control-Allow-Origin", "*")
  ctx.header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
  ctx.header("Access-Control-Allow-Headers", "Content-Type, Authorization")

  # Handle preflight requests
  if ctx.request_method == "OPTIONS"
    ctx.halt(200, "")
  end
end

# Before hook for all routes
before do |ctx|
  # You could check authentication here
  puts "Processing request: #{ctx.request_method} #{ctx.path}"
end

# After hook for all routes
after do |ctx|
  puts "Completed: #{ctx.response_status}"
end

# Serve static files from the public directory
serve_static("public")

# Basic routes
get "/" do |ctx|
  "<h1>Welcome to Prism!</h1><p>A high-performance web framework for Crystal</p>"
end

# Route with URL parameters
get "/users/:id" do |ctx|
  user_id = ctx.params["id"]
  "<h1>User Profile</h1><p>User ID: #{user_id}</p>"
end

# JSON response
get "/api/data" do |ctx|
  ctx.json({
    "status": "success",
    "message": "API is working",
    "time": Time.utc.to_s
  })
end

# Handle POST request with JSON body
post "/api/users" do |ctx|
  data = ctx.request_body_json

  # In a real app, you'd save to a database
  ctx.status(201)
  ctx.json({
    "status": "success",
    "message": "User created",
    "user": data
  })
end

# Custom 404 route
get "/*" do |ctx|
  ctx.status(404)
  "<h1>404 - Not Found</h1><p>The page you requested doesn't exist.</p>"
end

# Start the server
puts "Starting example application..."
run(port: 8080)
