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
      result.program.collected_covered_macro_nodes
        # .select { |nodes| nodes.any? { |(_, location, _)| match_path? location.filename.as(String) } }
        .each do |nodes|
          # Do some pre-processing on the nodes
          nodes = nodes
            .chunk { |(_, location, _)| location.line_number }
            .map { |(_, nodes)| nodes.first }
            .map { |(node, location, missed)| {node, self.normalize_location(location), missed} }
            .select { |(_, location, _)| match_path? location.filename.as(String) }
            .to_a

          next if nodes.empty?

          # nodes.each do |(node, location, missed)|
          #   p!({node.to_s.gsub("\n", ""), node.class, location, missed})
          # end

          # puts ""
          # puts ""

          node, location, missed = nodes.first

          # If the first node is a conditional, handle partial hits
          if node.is_a?(If) && (branches = condtional_statement_branches(node)) && branches > 1
            next self.visit node, location
          end

          nodes.each do |(node, location, missed)|
            next self.increment location, 0 if missed

            self.visit node, location
          end
        end

      @hits
    end

    def visit(node : If | Unless, location : Location) : Nil
      # If there are more than 1 branch, we need to increment a partial hit
      if (branches = self.condtional_statement_branches(node)) > 1
        self.set_or_increment location, branches
      end
    end

    def visit(node : MacroIf, location : Location) : Nil
    end

    def visit(node : ASTNode, location : Location) : Nil
      self.increment location
    end

    private def increment(location : Location, count : Int32 = 1, override : Bool = false) : Nil
      @hits[location.filename][location.line_number] = case existing_hits = @hits[location.filename][location.line_number]?
                                                       in String
                                                         hits, _, total = existing_hits.partition '/'

                                                         hits.to_i == total.to_i ? hits.to_i + count : "#{hits.to_i + count}/#{total}"
                                                       in Int32 then override ? count : existing_hits + count
                                                       in Nil
                                                         count
                                                       end
    end

    private def set_or_increment(location : Location, branches : Int32, count : Int32 = 1)
      # If the existing hits value is:
      # * String: Increment hits, up to *branches*
      # * Int32: All branches were hit, so switched back to simpler total hit counter.
      # * Nil: Newly found partial hit
      @hits[location.filename][location.line_number] = case existing_hits = @hits[location.filename][location.line_number]?
                                                       in String
                                                         hits, _, total = existing_hits.partition '/'

                                                         hits.to_i >= total.to_i ? hits.to_i + count : "#{hits.to_i + count}/#{total}"
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
