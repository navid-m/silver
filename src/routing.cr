module Silver
    class Route
        getter pattern : String
        getter param_names : Array(String)

        def initialize(@pattern : String)
            @param_names = [] of String
            @pattern.split("/").each do |part|
                if part.starts_with?(":")
                    @param_names << part[1..]
                end
            end
        end

        def match(path : String) : Hash(String, String)?
            pattern_parts = pattern.split("/")
            path_parts = path.split("/")

            return nil unless pattern_parts.size == path_parts.size

            params = Hash(String, String).new
            pattern_parts.zip(path_parts) do |pat_part, path_part|
                if pat_part.starts_with?(":")
                    param_name = pat_part[1..]
                    params[param_name] = path_part
                elsif pat_part != path_part
                    return nil
                end
            end

            params
        end
    end
end
