require "../syntax/ast"
require "../compiler"

module Crystal
  class Command
    private def macro_code_coverage
      config, result = compile_no_codegen "tool macro_code_coverage", macro_code_coverage: true

      JSON.build STDOUT do |builder|
        builder.object do
          builder.string "coverage"
          builder.object do
            result.program.covered_macro_nodes.each do |filename, line_coverage|
              next unless filename.starts_with? "/home/george/dev/git/athena-framework"
              builder.field filename do
                builder.object do
                  line_coverage.each do |line, count|
                    builder.field line, count
                  end
                end
              end
            end
          end
        end
      end
    end

    private def match_path?(path)
      paths = ::Path[path].parents << ::Path[path]

      !match_any_pattern?(CrystalPath.default_paths.map { |path| ::Path[path].expand.to_posix.to_s }, paths)
    end

    private def match_any_pattern?(patterns, paths)
      patterns.any? { |pattern| paths.any? { |path| path == pattern || File.match?(pattern, path.to_posix) } }
    end
  end
end
