require "../syntax/ast"
require "../compiler"
require "json"

module Crystal
  class Command
    private def macro_code_coverage
      config, result = compile_no_codegen "tool macro_code_coverage", path_filter: true, macro_code_coverage: true, allowed_formats: ["codecov"]

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
    @conditional_hit_cache = Hash(String, Hash(Int32, Set({ASTNode, Bool}))).new { |hash, key| hash[key] = Hash(Int32, Set({ASTNode, Bool})).new { |h, k| h[k] = Set({ASTNode, Bool}).new } }

    property includes = [] of String
    property excludes = [] of String

    def process(result : Compiler::Result) : Nil
      @hits.clear

      self.compute_coverage result

      if err = result.program.coverage_interrupt_exception
        puts "Encountered an error while computing coverage report:"
        puts
        err.inspect_with_backtrace STDOUT
        puts
        puts
      end

      self.write_output STDERR

      exit 1 if err
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
          # puts ""
          # puts "-" * 10
          # puts ""
        end

      # pp @conditional_hit_cache

      @hits
    end

    private def process_line(line : Int32, nodes : Array({ASTNode, Location, Bool}), & : {Int32, Location, Int32?} ->) : Nil
      # nodes.each do |(node, location, missed)|
      #   p({node: node.to_s.gsub("\n", "|=|"), class: node.class, location: location, end_location: node.end_location, missed: missed})
      # end

      # puts ""

      node, location, missed = nodes.first

      # Check for conditional hits first so that suffix conditionals are still treated as `1/2`.
      if (conditional_node = nodes.find(&.[0].is_a?(If | Unless | MacroIf | Or | And))) && (node = conditional_node[0]).is_a?(If | Unless | MacroIf | Or | And) && (branches = self.conditional_statement_branches(node)) > 1
        # Keep track of what specific conditional branches were hit and missed as to enure a proper partial count
        # p(node: node, location: location)
        newly_hit = @conditional_hit_cache[location.filename][location.line_number].add?({nodes.last[0], nodes.last[2]})

        yield({newly_hit ? 1 : 0, location, branches})
        return
      end

      # If no nodes on this line were missed, we can be assured it was a hit
      if nodes.none? { |(_, _, missed)| missed }
        yield({1, location, nil})
        return
      end

      yield({0, location, nil})
    end

    # Returns how many unique values a conditional statement could return on a single line.
    private def conditional_statement_branches(node : If | Unless | MacroIf | Or | And) : Int32
      return 1 unless start_location = node.location
      return 1 unless end_location = node.end_location
      return 1 if end_location.line_number > start_location.line_number

      self.count_branches node
    end

    private def count_branches(node : Or | And) : Int32
      self.count_branches node.left, node.right
    end

    private def count_branches(node : MacroIf | If | Unless) : Int32
      self.count_branches node.then, node.else
    end

    private def count_branches(left : ASTNode, right : ASTNode) : Int32
      then_depth = case n = left
                   when MacroIf, If, Unless, Or, And then self.count_branches n
                   else
                     1
                   end

      else_depth = case n = right
                   when MacroIf, If, Unless, Or, And then self.count_branches n
                   else
                     1
                   end

      then_depth + else_depth
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
