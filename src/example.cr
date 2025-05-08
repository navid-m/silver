require "../src/silver"

port = 8082
router = Silver::Router.new
router = Silver::Router.new

router.html "/" do |ctx|
    "<h1>Hello from Silver Web Framework</h1>"
end

router.get "/json" do |ctx|
    %({"message": "hello world"})
end

router.run(port)
