require "./coverage_mapping"

module Crystal
  # A function in the coverage mapping: the source regions of a typed def
  # instance, or of a file's top-level code, mapped to the counters that
  # count their executions.
  #
  # Its regions are mostly in its file, but code from other files can be
  # part of it, like templates expanded into a def by a macro.
  #
  # An unused function is a def that was never codegen'd. It has no counters
  # and maps its source to zero executions.
  class CoverageFunction
    alias Counter = CoverageMapping::Counter

    getter name : String
    # The files of the regions, by their file ID. The first one is the
    # function's file.
    getter filenames : Array(String)
    getter regions = [] of CoverageMapping::Region
    getter expressions = [] of CoverageMapping::Expression
    getter num_counters = 1
    getter? used : Bool
    @structural_hash : UInt64?

    def initialize(@name : String, filename : String, *, @used : Bool = true)
      @filenames = [filename]
    end

    def filename : String
      @filenames.first
    end

    # Counts the executions of the function.
    def entry_counter : Counter
      used? ? Counter.reference(0) : Counter.zero
    end

    def add_counter : Counter
      counter = Counter.reference(@num_counters)
      @num_counters += 1
      counter
    end

    # Returns a counter that evaluates `lhs - rhs` for `CounterKind::Subtract`,
    # or `lhs + rhs` for `CounterKind::Add`.
    def add_expression(kind : CoverageMapping::CounterKind, lhs : Counter, rhs : Counter) : Counter
      @expressions << CoverageMapping::Expression.new(lhs, rhs)
      Counter.new(kind, @expressions.size - 1)
    end

    # Maps the source from *start_location* to *end_location*, inclusive, to
    # *counter*. Both locations must be in the same file.
    def add_region(counter : Counter, start_location : Location, end_location : Location) : Nil
      @regions << CoverageMapping::Region.new(
        counter: counter, file_id: file_id(start_location),
        line_start: start_location.line_number, column_start: start_location.column_number,
        line_end: end_location.line_number, column_end: end_location.column_number + 1)
    end

    # Maps the source from *start_location* to right before *end_location* to
    # a gap region of *counter*.
    def add_gap_region(counter : Counter, start_location : Location, end_location : Location) : Nil
      @regions << CoverageMapping::Region.new(
        counter: counter, file_id: file_id(start_location),
        line_start: start_location.line_number, column_start: start_location.column_number,
        line_end: end_location.line_number, column_end: end_location.column_number, kind: :gap)
    end

    # Maps the whole lines from *start_line* to *end_line*, inclusive, of the
    # function's file to a skipped region, so that they aren't reported. The
    # line after it starts in the region around it.
    def add_skipped_region(start_line : Int32, end_line : Int32) : Nil
      # `llvm-cov` reads columns 0 to 0 as whole lines
      @regions << CoverageMapping::Region.new(
        counter: Counter.zero, file_id: 0,
        line_start: start_line, column_start: 0,
        line_end: end_line, column_end: 0, kind: :skipped)
    end

    # Maps the condition from *start_location* to *end_location*, inclusive,
    # to a branch region, true as many times as *true_counter* counts and
    # false as many times as *false_counter* counts.
    def add_branch_region(true_counter : Counter, false_counter : Counter, start_location : Location, end_location : Location) : Nil
      @regions << CoverageMapping::Region.new(
        counter: true_counter, file_id: file_id(start_location),
        line_start: start_location.line_number, column_start: start_location.column_number,
        line_end: end_location.line_number, column_end: end_location.column_number + 1,
        kind: :branch, false_counter: false_counter)
    end

    private def file_id(location : Location) : Int32
      filename = location.filename.as(String)
      @filenames.index(filename) || begin
        @filenames << filename
        @filenames.size - 1
      end
    end

    # Encodes the mapping, with the indices of `filenames` in the filenames
    # table.
    def encode_mapping(filename_indices : Array(Int32)) : Bytes
      CoverageMapping.encode_function(filename_indices, @expressions, @regions)
    end

    # The profile data of a function is only matched to its mapping if their
    # hashes are equal, which rejects profiles of a different layout. Unused
    # functions have no profile data, `llvm-cov` expects a hash of 0.
    #
    # Must only be called once all regions are added.
    def structural_hash : UInt64
      @structural_hash ||= used? ? CoverageMapping.md5_hash(encode_mapping((0...@filenames.size).to_a)) : 0_u64
    end
  end

  # The counters of coverage functions that codegen increments, by the AST
  # node whose codegen increments them.
  class CoverageNodeCounters
    alias Counters = Hash(ASTNode, {CoverageFunction, Int32})

    # Incremented right before the node runs.
    getter entry = Counters.new.compare_by_identity

    # Incremented right after the node runs.
    getter continuation = Counters.new.compare_by_identity

    # Incremented when the condition of the `While` node is false.
    getter loop_exit = Counters.new.compare_by_identity
  end

  # Locations of nodes for the regions of the coverage function `@function`.
  private module CoverageLocations
    private def start_location(node) : Location?
      node.location || node.as?(Expressions).try(&.expressions.first?).try { |exp| start_location(exp) }
    end

    private def end_location(node) : Location?
      node.end_location || node.as?(Expressions).try(&.expressions.last?).try { |exp| end_location(exp) }
    end

    # Code expanded from macros is in virtual files, without source to map.
    private def in_source_file?(location : Location?) : Bool
      !!location && location.filename.is_a?(String)
    end

    private def in_function_file?(location : Location?) : Bool
      !!location && location.filename == @function.filename
    end
  end

  # Maps the source of a coverage function to counters, and assigns the
  # counters to the AST nodes whose codegen must increment them.
  #
  # The first counter counts entries into the function. Each branch body
  # (`then` of `if`, bodies of `while` and inlined blocks, `rescue`, `else` and
  # `ensure` of exception handlers) gets a counter incremented right before it
  # runs, except the `else` of `if`, whose count is the parent's minus the
  # `then`'s.
  #
  # The statements following one that may not complete normally (with
  # `return`, `break`, `next`, a `NoReturn` call or exception handling) get a
  # counter incremented right after that statement. Other statements share
  # their parent's counter. Exceptions raised by calls elsewhere aren't
  # accounted for.
  #
  # Each statement gets its own region. `llvm-cov` adds up the counts of
  # regions with the same location in all the instances of a def, but lets
  # the innermost region win otherwise. Which statements may not complete,
  # or were removed because they can't run, differs between instances, but
  # the location of each statement doesn't. The regions that depend on the
  # instance are gaps between statements, which only set the count of the
  # lines that start in them.
  #
  # `llvm-cov` counts a line as the maximum of the count of the region it
  # starts in and of the regions that start in it. Each branch's region is
  # thus preceded by a gap region that starts right after the code before the
  # branch, so that the lines of the branch start in it.
  #
  # Lines without code, like comments and `end`, map to skipped regions so
  # that they aren't reported. They're found in the source text rather than
  # from the locations of nodes, which aren't always precise, for example in
  # code passed to a macro.
  class CoverageRegionBuilder < Visitor
    include CoverageLocations

    alias Counter = CoverageMapping::Counter

    @counter : Counter
    @escapes = Hash(ASTNode, Bool).new.compare_by_identity
    @if_counters = Hash(If, {Counter, Counter}).new.compare_by_identity

    # Counters are added to *node_counters* for codegen to increment.
    # *source_lines* are the lines of the function's file, if known.
    def initialize(@function : CoverageFunction, @node_counters : CoverageNodeCounters,
                   @source_lines : Array(String)? = nil)
      @counter = @function.entry_counter
    end

    # Maps the source of *a_def* to the function's entry counter, and builds
    # its body's regions. The entry counter must be incremented when the
    # body is codegen'd.
    #
    # A def expanded from a macro has no source of its own, so it maps to the
    # start of the macro call. Code passed to the macro, like a block, keeps
    # its own source.
    def build_def(a_def : Def) : Nil
      location = a_def.location.not_nil!
      if location.filename.is_a?(String)
        end_location = a_def.end_location.not_nil!
        @function.add_region(@counter, location, end_location)
        add_skipped_regions(location.line_number, end_location.line_number)
      else
        call_location = location.expanded_location.not_nil!
        @function.add_region(@counter, call_location, call_location)
      end
      a_def.body.accept self
    end

    # Maps the source of *a_def*, which was never codegen'd, to zero.
    def build_unused_def(a_def : Def) : Nil
      location = a_def.location.not_nil!
      end_location = a_def.end_location.not_nil!
      @function.add_region(Counter.zero, location, end_location)
      add_skipped_regions(location.line_number, end_location.line_number)
    end

    # Maps the source from *location* to the end of *value*, the initializer
    # of a constant or class variable, to the function's entry counter, and
    # builds the regions of *value*. The entry counter must be incremented
    # when *value* is codegen'd.
    #
    # A value expanded from a macro has no source of its own, so only the
    # start of the declaration is mapped.
    def build_initializer(location : Location, value : ASTNode) : Nil
      unless add_region(location, value, @counter)
        @function.add_region(@counter, location, location)
      end
      if (end_location = end_location(value)) && in_function_file?(end_location)
        add_skipped_regions(location.line_number, end_location.line_number)
      end
      value.accept self
    end

    # Builds the regions of each executable statement of a file's top-level
    # code, and assigns the function's entry counter to the first statement.
    def build_top_level(statements : Array(ASTNode)) : Nil
      visit_statements(statements, top_level: true)
      if (first = statements.first?) && !@function.regions.empty?
        @node_counters.entry[first] = {@function, 0}
      end

      statements.each do |statement|
        next if declaration?(statement)

        start_location = start_location(statement)
        end_location = end_location(statement)
        if in_function_file?(start_location) && in_function_file?(end_location)
          add_skipped_regions(start_location.not_nil!.line_number, end_location.not_nil!.line_number)
        end
      end
    end

    def visit(node : ASTNode)
      true
    end

    def visit(node : Expressions)
      visit_statements(node.expressions, top_level: false)

      # The statements after one that doesn't complete are removed before
      # codegen, but the parsed location of the expressions still includes
      # them
      if (last = node.expressions.last?) && escapes?(last) && (end_location = node.end_location)
        add_gap_region(location_after(last), Location.new(end_location.filename, end_location.line_number, end_location.column_number + 1), Counter.zero)
      end

      false
    end

    def visit(node : If)
      return true unless in_source_file?(node.location)

      node.cond.accept self
      parent = @counter
      then_counter = add_counter(node.then, @node_counters.entry)
      else_counter = @function.add_expression(:subtract, parent, then_counter)
      @if_counters[node] = {then_counter, else_counter}
      add_branch_regions(node, then_counter, else_counter)

      # The expansions of `a && b` and `a || b` repeat `a` as a branch, which
      # must not map the source of `a` a second time. Expanded conditions,
      # like those of `case`, may have no end location. A branch around its
      # condition is code generated for a whole construct, like the `else`
      # of an exhaustive `case`.
      visit_branch(node.then, then_counter, location_after(node.cond) || node.location,
        region: !same_start?(node.then, node.cond) && !around?(node.then, node.cond))
      visit_branch(node.else, else_counter,
        location_after(node.then) || location_after(node.cond) || node.location,
        region: !same_start?(node.else, node.cond) && !around?(node.else, node.cond))

      @counter = parent
      false
    end

    def visit(node : While)
      return true unless in_source_file?(node.location)

      parent = @counter
      body_counter = add_counter(node.body, @node_counters.entry)

      # `while true` has no condition to report
      unless node.cond.single_expression.true_literal?
        add_branch_region(node.cond, body_counter, add_counter(node, @node_counters.loop_exit))
      end

      visit_branch(node.cond, @function.add_expression(:add, parent, body_counter), nil)
      visit_branch(node.body, body_counter, location_after(node.cond))

      @counter = parent
      false
    end

    def visit(node : Call)
      node.obj.try &.accept self
      node.args.each &.accept self
      node.named_args.try &.each &.accept self
      node.block_arg.try &.accept self

      # A captured block is codegen'd as a proc literal, its own function
      if (block = node.block) && !block.fun_literal
        if in_source_file?(block.location)
          parent = @counter
          visit_branch(block.body, add_counter(block.body, @node_counters.entry), block.location)
          @counter = parent
        else
          block.body.accept self
        end
      end

      false
    end

    def visit(node : ExceptionHandler)
      return true unless in_source_file?(node.location)

      parent = @counter
      node.body.accept self
      @counter = parent

      branches = node.rescues.try(&.map(&.body)) || [] of ASTNode
      node.else.try { |node_else| branches << node_else }
      node.ensure.try { |node_ensure| branches << node_ensure }
      # The lines between the parts have the code that matches exceptions to
      # `rescue` clauses, which runs as many times as the part after them
      previous = node.body
      branches.each do |branch|
        visit_branch(branch, add_counter(branch, @node_counters.entry), location_after(previous), whole_gap: true)
        @counter = parent
        previous = branch
      end

      false
    end

    def visit(node : ProcLiteral)
      # Codegen'd as its own function
      false
    end

    private def visit_statements(statements, top_level)
      statements = statements.reject { |statement| declaration?(statement) } if top_level
      groups = group_statements(statements)

      previous_end = nil
      continued = false
      groups.each_with_index do |(group, start_location, end_location), index|
        # After a continuation counter, the lines of each statement must start
        # in a region of that counter rather than in the enclosing region.
        # Top-level statements have no enclosing region, and declarations
        # between them must stay unmapped.
        if continued && previous_end && start_location && !top_level
          add_gap_region(location_after(previous_end), start_location, @counter)
        end

        if start_location && end_location
          @function.add_region(@counter, start_location, end_location)
        else
          group.each { |statement| add_source_regions(statement, @counter) }
        end
        group.each &.accept(self)
        previous_end = end_location if end_location

        next if index == groups.size - 1 || group.none? { |statement| escapes?(statement) }

        @counter = add_counter(group.last, @node_counters.continuation)
        continued = true
      end
    end

    # Groups the statements that overlap in the source, with the location of
    # each group. The expansion of a literal, like `{"a" => -> { 1 }}`, is
    # spliced into the statements around it as statements located at parts of
    # the literal, which would otherwise map the source of a proc literal, its
    # own function, a second time.
    private def group_statements(statements) : Array({Array(ASTNode), Location?, Location?})
      groups = [] of {Array(ASTNode), Location?, Location?}
      statements.each do |statement|
        start_location = start_location(statement)
        end_location = end_location(statement)
        unless start_location && end_location && in_source_file?(start_location) && (start_location <=> end_location).try(&.<=(0))
          groups << {[statement] of ASTNode, nil, nil}
          next
        end

        if (last = groups.last?) && (group_start = last[1]) && (group_end = last[2]) && (start_location <=> group_end).try(&.<=(0))
          last[0] << statement
          groups[-1] = {
            last[0],
            (start_location <=> group_start).try(&.<(0)) ? start_location : group_start,
            (end_location <=> group_end).try(&.>(0)) ? end_location : group_end,
          }
        else
          groups << {[statement] of ASTNode, start_location, end_location}
        end
      end
      groups
    end

    # A line consisting of keywords and punctuation that close code, of a
    # comment, or of nothing.
    private LINE_WITHOUT_CODE = /\A\s*(?:(?:end|else|ensure|begin|then|do)\b|[\}\]\),;])?(?:\s*(?:end\b|[\}\]\),;]))*\s*(?:#.*)?\z/

    # Maps the lines without code from *first_line* to *last_line* to skipped
    # regions.
    private def add_skipped_regions(first_line, last_line)
      return unless source_lines = @source_lines

      skipped_start = nil
      (first_line..last_line + 1).each do |line_number|
        line = source_lines[line_number - 1]? if line_number <= last_line
        if line && LINE_WITHOUT_CODE.matches?(line)
          skipped_start ||= line_number
        elsif skipped_start
          @function.add_skipped_region(skipped_start, line_number - 1)
          skipped_start = nil
        end
      end
    end

    # Returns the condition tested by an `If` with condition *cond*: the
    # left operand of `a && b` and `a || b` is assigned to a temporary
    # variable, unless it's a variable.
    private def condition(cond)
      if cond.is_a?(Assign) && (target = cond.target).is_a?(Var) && target.name.starts_with?("__temp")
        cond.value
      else
        cond
      end
    end

    # Maps the condition of *node* to a branch region, true as many times as
    # its `then` runs and false as many times as its `else` runs.
    #
    # Each operand of `a || b` and `a && b` is a condition, but `a || b`
    # expands to an `If` testing `a` whose `else` is `b`. An `If` whose
    # condition is such an expansion tests its value, which is that of its
    # last operand only when that operand ran, so it maps that operand with
    # the counts of those times. For `x || y`, `y` ran when `x` was false, and
    # for `x && y`, when `x` was true.
    private def add_branch_regions(node : If, then_counter, else_counter)
      cond = condition(node.cond)
      if cond.is_a?(If) && (cond.or? || cond.and?) && (inner_counters = @if_counters[cond]?)
        inner_then_counter, inner_else_counter = inner_counters
        operand = cond.or? ? cond.else : cond.then

        # The counts of a nested expansion would also depend on its own
        # operands
        return if operand.is_a?(If) && (operand.or? || operand.and?)

        if cond.or?
          then_counter = @function.add_expression(:subtract, then_counter, inner_then_counter)
        else
          else_counter = @function.add_expression(:subtract, else_counter, inner_else_counter)
        end
        cond = operand
      end

      add_branch_region(cond, then_counter, else_counter)
    end

    # Maps the source of *cond* to a branch region. An expanded condition
    # without an end location maps its first column.
    private def add_branch_region(cond, true_counter, false_counter)
      start_location = start_location(cond)
      end_location = end_location(cond) || start_location
      return unless start_location && end_location && in_source_file?(start_location)
      return unless (start_location <=> end_location).try(&.<=(0))

      @function.add_branch_region(true_counter, false_counter, start_location, end_location)
    end

    # Maps the code from source files within *statement*, which has no
    # source of its own, to *counter*. A statement expanded from a macro or a
    # template contains code from source files, like the expressions of the
    # template.
    private def add_source_regions(statement, counter)
      finder = SourceNodeFinder.new
      statement.accept finder
      finder.nodes.each { |node| add_region(node, node, counter) }
    end

    # Finds the outermost nodes with a location in a source file.
    private class SourceNodeFinder < Visitor
      getter nodes = [] of ASTNode

      def visit(node : Block | ProcLiteral)
        # Blocks and proc literals are their own regions or functions
        false
      end

      def visit(node : ASTNode)
        if node.location.try(&.filename).is_a?(String) && node.end_location
          @nodes << node
          false
        else
          true
        end
      end
    end

    # Maps *node* to *counter*, preceded by a gap region from *gap_start*,
    # which covers the lines in between if *whole_gap*.
    private def visit_branch(node, counter, gap_start : Location?, region = true, whole_gap = false)
      if region
        add_gap_region(gap_start, node, counter, whole_gap)
        add_region(node, node, counter)
      end
      @counter = counter
      node.accept self
    end

    private def add_counter(node, node_counters)
      counter = @function.add_counter
      node_counters[node] = {@function, counter.id}
      counter
    end

    # Maps the source from the start of *first* to the end of *last*, if both
    # are known and in the same source file. Returns whether it did.
    private def add_region(first : ASTNode | Location, last : ASTNode, counter) : Bool
      start_location = first.is_a?(Location) ? first : start_location(first)
      end_location = end_location(last)
      return false unless start_location && end_location && in_source_file?(start_location)

      # Comparing locations of different files returns `nil`
      return false unless (start_location <=> end_location).try(&.<=(0))

      @function.add_region(counter, start_location, end_location)
      true
    end

    # Maps the source from *start_location* to right before *node*, if it's
    # not empty and in a source file.
    private def add_gap_region(start_location, node : ASTNode, counter, whole_gap = false)
      add_gap_region(start_location, start_location(node), counter, whole_gap)
    end

    private def add_gap_region(start_location, end_location : Location?, counter, whole_gap = false)
      return unless start_location && end_location && in_source_file?(start_location)
      return unless (start_location <=> end_location).try(&.<(0))

      start_location = gap_start(start_location, end_location) unless whole_gap

      @function.add_gap_region(counter, start_location, end_location)
    end

    # A gap region only needs to set the count of the line that it ends in.
    # When there are lines in between, it starts at the end of the line
    # before, if the source is known, so that those lines keep the count of
    # the regions around them, like the conditions of the next values of a
    # `when`.
    private def gap_start(start_location : Location, end_location : Location) : Location
      return start_location unless end_location.line_number > start_location.line_number + 1
      return start_location unless in_function_file?(start_location) && (source_lines = @source_lines)
      return start_location unless line = source_lines[end_location.line_number - 2]?

      Location.new(start_location.filename, end_location.line_number - 1, line.bytesize + 1)
    end

    private def location_after(node : ASTNode) : Location?
      end_location(node).try { |location| location_after(location) }
    end

    private def location_after(location : Location) : Location
      Location.new(location.filename, location.line_number, location.column_number + 1)
    end

    # Returns `true` if the source of *node* contains the one of *other*.
    private def around?(node, other)
      start_location = start_location(node)
      end_location = end_location(node)
      other_start_location = start_location(other)
      other_end_location = end_location(other) || other_start_location
      return false unless start_location && end_location && other_start_location && other_end_location

      !!((start_location <=> other_start_location).try(&.<=(0)) && (end_location <=> other_end_location).try(&.>=(0)))
    end

    private def same_start?(node, other)
      start_location = start_location(node)
      other_start_location = start_location(other)
      !!(start_location && other_start_location && (start_location <=> other_start_location) == 0)
    end

    private def declaration?(node)
      case node
      when ClassDef, ModuleDef, EnumDef, LibDef, CStructOrUnionDef, AnnotationDef,
           Def, FunDef, Macro, Alias, TypeDef, Include, Extend, Annotation,
           VisibilityModifier, Require, FileNode, Nop
        true
      when Assign
        # Constants are initialized lazily, not where they are declared
        node.target.is_a?(Path)
      else
        false
      end
    end

    private def escapes?(node)
      @escapes.put_if_absent(node) do
        finder = EscapeFinder.new
        node.accept finder
        finder.found?
      end
    end

    # Finds code that may transfer control out of a statement before its end.
    private class EscapeFinder < Visitor
      getter? found = false

      def visit(node : Return | Break | Next | ExceptionHandler)
        @found = true
        false
      end

      def visit(node : ProcLiteral)
        false
      end

      def visit(node : Block)
        # `next` in a captured block returns from its proc
        !node.fun_literal && !@found
      end

      def visit(node : ASTNode)
        @found = true if node.type?.try(&.no_return?)
        !@found
      end
    end
  end
end
