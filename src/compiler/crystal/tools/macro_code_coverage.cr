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
                  line_coverage.to_a.sort_by! { |(line, count)| line }.each do |line, count|
                    builder.field line, count
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
