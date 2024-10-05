require "../syntax/ast"
require "../compiler"

module Crystal
  class Command
    private def macro_code_coverage
      config, result = compile_no_codegen "tool macro_code_coverage", macro_code_coverage: true

      MacroCoverageProcessor.new.process result
    end

    struct MacroCoverageProcessor
      @hits = Hash(String, Hash(Int32, Int32 | String)).new { |hash, key| hash[key] = Hash(Int32, Int32 | String).new(0) }

      def process(result : Compiler::Result) : Nil
        @hits.clear

        result.program.covered_macro_nodes.each do |node|
          self.visit node, node.location.not_nil!
        end

        JSON.build STDOUT do |builder|
          builder.object do
            builder.string "coverage"
            builder.object do
              @hits.each do |filename, line_coverage|
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

      # A MacroIf node denotes a terminal state in the if statement.
      # I.e. there are no additional elsifs.
      def visit(node : MacroIf, location : Location) : Nil
        self.increment location, 0
      end

      def visit(node : If, location : Location) : Nil
        # If there are more than 1 branch, we need to increment a partial hit
        if (branches = self.if_statement_branches(node)) > 1
          self.increment_partial location, branches
        else
          self.increment location
        end
      end

      # Returns how many unique branches this If statement consist of, assuming `1` if it's not a ternary.
      #
      # ```
      # true ? 1 : 0             # => 2
      # true ? 1 : false ? 2 : 3 # => 3
      # ```
      private def if_statement_branches(node : If) : Int32
        return 1 unless node.ternary?

        then_depth = case n = node.then
                     when If then self.if_statement_branches n
                     else
                       1
                     end

        else_depth = case n = node.else
                     when If then self.if_statement_branches n
                     else
                       1
                     end

        then_depth + else_depth
      end

      def visit(node : ASTNode, location : Location) : Nil
        self.increment location
      end

      private def increment(location : Location, count : Int32 = 1) : Nil
        @hits[location.filename][location.line_number] = @hits[location.filename][location.line_number].as(Int32) + count
      end

      private def increment_partial(location : Location, branches : Int32, count : Int32 = 1) : Nil
        existing_hits = @hits[location.filename][location.line_number]?

        # If the existing hits value is:
        # * String: Increment hits, up to *branches*
        # * Int32: All branches were hit, so switched back to simpler total hit counter.
        # * Nil: Newly found partial hit
        @hits[location.filename][location.line_number] = case existing_hits
                                                         in String
                                                           hits, _, total = existing_hits.partition '/'

                                                           raise "BUG: Branch count mismatch" if total.to_i != branches

                                                           hits.to_i == branches ? hits.to_i + count : "#{hits.to_i + count}/#{branches}"
                                                         in Int32 then existing_hits += count
                                                         in Nil   then "#{count}/#{branches}"
                                                         end
      end
    end
  end
end
