module Crystal
  # Selects paths with glob patterns. A path is selected if it or one of its
  # parent directories matches an included pattern, or if none of them
  # matches an excluded pattern.
  struct PathFilter
    getter includes : Array(String)
    getter excludes : Array(String)

    def initialize(@includes = [] of String, @excludes = [] of String)
    end

    def match?(path : String) : Bool
      paths = ::Path[path].parents << ::Path[path]

      match_any_pattern?(@includes, paths) || !match_any_pattern?(@excludes, paths)
    end

    private def match_any_pattern?(patterns, paths)
      patterns.any? { |pattern| paths.any? { |path| path == pattern || File.match?(pattern, path.to_posix) } }
    end
  end
end
