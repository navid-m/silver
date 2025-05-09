module Silver
    # Some route for the router (router logic encapsulated in App class)
    class Route
        getter pattern : String
        getter param_names : Array(String)
        getter regex : Regex

        def initialize(@pattern : String)
            @param_names = [] of String
            @regex = compile_route_regex
        end

        private def compile_route_regex : Regex
            parts = [] of String
            @pattern.split("/").each do |part|
                if part.starts_with?(":")
                    param_name = part[1..]
                    @param_names << param_name
                    parts << "([^/]+)"
                else
                    parts << Regex.escape(part)
                end
            end
            pattern_str = "^" + parts.join("/") + "$"
            Regex.new(pattern_str)
        end

        def match(path : String) : Hash(String, String)?
            match_data = @regex.match(path)
            return nil unless match_data
            params = Hash(String, String).new
            @param_names.each_with_index do |name, i|
                params[name] = match_data[i + 1]
            end

            params
        end
    end
end
