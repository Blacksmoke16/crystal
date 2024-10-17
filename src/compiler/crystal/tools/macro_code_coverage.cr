require "../syntax/ast"
require "../compiler"

module Crystal
  class Command
    private def macro_code_coverage
      config, result = compile_no_codegen "tool macro_code_coverage", path_filter: true, macro_code_coverage: true

      coverage_processor = MacroCoverageProcessor.new

      coverage_processor.includes.concat config.includes.map { |path| ::Path[path].expand.to_posix.to_s }

      coverage_processor.excludes.concat CrystalPath.default_paths.map { |path| ::Path[path].expand.to_posix.to_s }
      coverage_processor.excludes.concat config.excludes.map { |path| ::Path[path].expand.to_posix.to_s }

      coverage_processor.process result
    end
  end

  struct MacroCoverageProcessor
    private CURRENT_DIR = Dir.current

    @hits = Hash(String, Hash(Int32, Int32 | String)).new { |hash, key| hash[key] = Hash(Int32, Int32 | String).new(0) }

    property includes = [] of String
    property excludes = [] of String

    def process(result : Compiler::Result) : Nil
      @hits.clear

      self.compute_coverage result

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

    def compute_coverage(result : Compiler::Result)
      # In order to obtain proper hit counts for multi-line MacroExpression we need to get a bit creative.
      #
      # If we just collect the MacroExpression node itself, it would only mark the first line of the expression as hit, which would not be true if it were a multi-line expression with bunch of other logic within it.
      # However, if we collect every Call, it would produce incorrect hits, e.g. `pp 10 * 10` would be 2 calls even tho the line executes once.
      #
      # To solve this, we'll normalize the covered nodes by:
      # 1. First, filter the nodes them down to only the ones we care about given the desired path filters
      # 2. Chunk then un-chunk the nodes to remove duplicate consecutive elements
      # 3. Chunk the nodes again by their line number.
      #    This should be fine as long as we can assume there will be another node on a different line in-between multiple iterations/invocations of the macro.
      # 4. Iterate over the chunks themselves, using the first missed node, falling back on the first node as the node to process/whose location to use.
      #    Missed nodes take priority since if any node was missed, that means the whole line was missed and should be reported as such.
      #    It shouldn't matter what node we ultimately pick since all nodes are on the same line and that's the level of granularity we're operating on.
      normalized_nodes = result.program.covered_macro_nodes
        .each
        .select { |(n, l, m)| match_path?(l.filename.as(String)) }
        .map { |(n, l, m)| {n, self.normalize_location(l), m} }
        .chunk(true, &.itself)
        .map(&.first)

      normalized_nodes
        .slice_before(normalized_nodes.first)
        .each do |nodes|
          origin_location = nodes[0][1]

          pp!(origin_location)

          nodes.each do |(node, location, missed)|
            p({node.to_s.gsub("\n", ""), node.class, location, missed})
          end

          puts ""
          puts ""

          # nodes.each do |(node, location, missed)|
          #   self.visit node, location
          # end
        end

      @hits
    end

    private def normalize_location(location : Location) : Location
      Location.new(
        ::Path[location.filename.as(String)].relative_to(CURRENT_DIR).to_s,
        location.line_number,
        location.column_number
      )
    end

    def visit(node : If | Unless, location : Location) : Nil
      # If there are more than 1 branch, we need to increment a partial hit
      if (branches = pp!(self.condtional_statement_branches(node))) > 1
        self.set_or_increment location, branches
      end
    end

    def visit(node : ASTNode, location : Location) : Nil
      self.increment location
    end

    private def increment(location : Location, count : Int32 = 1, override : Bool = false) : Nil
      @hits[location.filename][location.line_number] = case existing_hits = @hits[location.filename][location.line_number]?
                                                       in String
                                                         hits, _, total = existing_hits.partition '/'

                                                         hits.to_i == total ? hits.to_i + count : "#{hits.to_i + count}/#{total}"
                                                       in Int32 then existing_hits += count
                                                       in Nil
                                                         count
                                                       end

      # case existing_hits = @hits[location.filename][location.line_number]
      # when String
      #   # In this context if *existing_hits* is a string, it implies an `If` and other macro expressions on the same line.
      #   # Handle this by essentially no-oping as it'll be a hit no matter what branch the `If` is hit.
      # when Int32
      #   @hits[location.filename][location.line_number] = override ? count : existing_hits + count
      # end
    end

    # private def increment_partial(location : Location, branches : Int32, count : Int32 = 1) : Nil

    #   @hits[location.filename][location.line_number] = case existing_hits = @hits[location.filename][location.line_number]?
    #                                                    in String
    #                                                      hits, _, total = existing_hits.partition '/'

    #                                                      hits.to_i == total ? hits.to_i + count : "#{hits.to_i + count}/#{total}"
    #                                                    in Int32 then existing_hits += count
    #                                                    in Nil   then "#{count}/#{branches}"
    #                                                    end
    # end

    private def set_or_increment(location : Location, branches : Int32, count : Int32 = 1)
      # If the existing hits value is:
      # * String: Increment hits, up to *branches*
      # * Int32: All branches were hit, so switched back to simpler total hit counter.
      # * Nil: Newly found partial hit
      @hits[location.filename][location.line_number] = case existing_hits = @hits[location.filename][location.line_number]?
                                                       in String
                                                         hits, _, total = existing_hits.partition '/'

                                                         hits.to_i == total ? hits.to_i + count : "#{hits.to_i + count}/#{total}"
                                                       in Int32 then existing_hits += count
                                                       in Nil
                                                         "#{count}/#{branches}"
                                                       end
    end

    # Returns how many unique branches this `If` statement consist of on a single line, assuming `1` if it's not a ternary.
    #
    # ```
    # true ? 1 : 0             # => 2
    # true ? 1 : false ? 2 : 3 # => 3
    # ```
    private def condtional_statement_branches(node : If) : Int32
      return 1 unless node.ternary?

      then_depth = case n = node.then
                   when If then self.condtional_statement_branches n
                   else
                     1
                   end

      else_depth = case n = node.else
                   when If then self.condtional_statement_branches n
                   else
                     1
                   end

      then_depth + else_depth
    end

    # Unless statements cannot be nested more than 1 level on a single line.
    private def condtional_statement_branches(node : Unless) : Int32
      1
    end

    private def match_path?(path)
      paths = ::Path[path].parents << ::Path[path]

      match_any_pattern?(includes, paths) || !match_any_pattern?(excludes, paths)
    end

    private def match_any_pattern?(patterns, paths)
      patterns.any? { |pattern| paths.any? { |path| path == pattern || File.match?(pattern, path.to_posix) } }
    end
  end
end
