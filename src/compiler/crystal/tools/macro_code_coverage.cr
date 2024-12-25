require "../syntax/ast"
require "../compiler"
require "json"

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
    @conditional_hit_cache = Hash(String, Hash(Int32, Set(ASTNode))).new { |hash, key| hash[key] = Hash(Int32, Set(ASTNode)).new { |h, k| h[k] = Set(ASTNode).new } }

    property includes = [] of String
    property excludes = [] of String

    def process(result : Compiler::Result) : Nil
      @hits.clear

      self.compute_coverage result

      # Due to their compiled nature, testing of custom macro logic that raises must be done in its own process.
      # As such, it is reasonable to expect an application to have quite a few of those to ensure full coverage.
      #
      # Because of this, allow providing an ENV var once to denote the output directory where the tool should output the reports to,
      # globally for all calls to this tool when running `crystal spec`.
      #
      # TODO: Other option would be add a like `--report-filename` option and move responsibility to the caller, which would also be reasonable.
      unless output_dir = ENV["CRYSTAL_MACRO_CODE_COVERAGE_OUTPUT_DIR"]?
        return self.write_output STDOUT
      end

      File.open ::Path[output_dir, "macro_code_coverage.#{Time.utc.to_unix}.json"], "w" do |file|
        self.write_output file
        file.puts
      end
    end

    # See https://docs.codecov.com/docs/codecov-custom-coverage-format
    private def write_output(io : IO) : Nil
      JSON.build io, indent: "  " do |builder|
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

    # First filters the nodes to only those with locations we care about.
    # The nodes are then chunked by line number, essentially grouping them.
    # Each group is then processed to determine if that line is a hit or miss, but may also yield more than once, such as to mark an `If` conditional as a hit, but it's `else` block as a miss.
    #
    # The coverage information is stored in a similar way as the resulting output report: https://docs.codecov.com/docs/codecov-custom-coverage-format.
    def compute_coverage(result : Compiler::Result)
      result.program.collected_covered_macro_nodes
        .select { |nodes| nodes.any? { |(_, location, _)| match_path? location.filename.as(String) } }
        .each do |nodes|
          nodes
            .chunk { |(_, location, _)| location.line_number }
            .each do |(line_number, nodes_by_line)|
              self.process_line(line_number, nodes_by_line) do |(count, location, branches)|
                next unless location.filename.is_a? String

                location = self.normalize_location(location)

                @hits[location.filename][location.line_number] = case existing_hits = @hits[location.filename][location.line_number]?
                                                                 in String
                                                                   hits, _, total = existing_hits.partition '/'

                                                                   "#{hits.to_i == total.to_i ? hits : hits.to_i + count}/#{total}"
                                                                 in Int32 then existing_hits + count
                                                                 in Nil
                                                                   branches ? "#{count}/#{branches}" : count
                                                                 end
              end
            end
        end

      @hits
    end

    private def process_line(line : Int32, nodes : Array({ASTNode, Location, Bool}), & : {Int32, Location, Int32?} ->) : Nil
      node, location, missed = nodes.first

      # If no nodes on this line were missed, we can be assured it was a hit
      if nodes.none? { |(_, _, missed)| missed }
        yield({1, location, nil})
        return
      end

      if (conditional_node = nodes.find(&.[0].is_a?(If | Unless))) && (node = conditional_node[0]).is_a?(If | Unless) && (branches = self.condtional_statement_branches(node)) > 1
        # Keep track of what specific conditional branches were hit and missed as to enure a proper partial count
        newly_hit = @conditional_hit_cache[location.filename][location.line_number].add? nodes.reverse.find(nodes.last) { |(_, _, missed)| missed }[0]

        yield({newly_hit ? 1 : 0, location, branches})
        return
      end

      # If a MacroIf node is missed, we want to mark the start (conditional) of the MacroIf as hit, but the body as missed.
      #
      # However if the body of the conditional is an Expressions, we need to work around https://github.com/crystal-lang/crystal/issues/14884#issuecomment-2423904262.
      # The incorrect line number is a result of the first node of the expressions being a `MacroLiteral` consisting of a newline and some whitespace.
      # We instead want to use the location of the first non-MacroLiteral node which would be the location of the actual body.
      if node.is_a?(MacroIf) && nodes.last[2]
        node, missed_location, _ = nodes.last

        if node.is_a?(Expressions)
          missed_location = node.expressions.reject(MacroLiteral).first?.try(&.location) || location

          # Because *missed_location* may not be handled via the macro interpreter directly, we need to apply the same VirtualFile check here,
          # using the same `missed_location.line_number + macro_location.line_number` logic to calculate the proper line number.
          if missed_location.filename.is_a?(VirtualFile) && (macro_location = missed_location.macro_location)
            missed_location = Location.new(
              location.filename,
              missed_location.line_number + macro_location.line_number,
              missed_location.column_number
            )
          end
        end

        yield({1, location, nil})
        yield({0, missed_location, nil})
        return
      elsif node.is_a?(Expressions) && missed && nodes.size == 1
        yield({0, location, nil})

        if loc = node.expressions.reject(MacroLiteral).first?.try(&.location)
          yield({0, loc, nil})
        end

        return
      end

      yield({0, location, nil})
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

    private def normalize_location(location : Location) : Location
      Location.new(
        ::Path[location.filename.as(String)].relative_to(CURRENT_DIR).to_s,
        location.line_number,
        location.column_number
      )
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
