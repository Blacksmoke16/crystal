require "./coverage_mapping"

module Crystal
  # A function in the coverage mapping: the source regions of a typed def
  # instance, or of a file's top-level code, mapped to the counters that
  # count their executions.
  #
  # An unused function is a def that was never codegen'd. It has no counters
  # and maps its source to zero executions.
  class CoverageFunction
    alias Counter = CoverageMapping::Counter

    getter name : String
    getter filename : String
    getter regions = [] of CoverageMapping::Region
    getter expressions = [] of CoverageMapping::Expression
    getter num_counters = 1
    getter? used : Bool
    @structural_hash : UInt64?

    def initialize(@name : String, @filename : String, *, @used : Bool = true)
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
    # *counter*.
    def add_region(counter : Counter, start_location : Location, end_location : Location) : Nil
      @regions << CoverageMapping::Region.new(
        counter: counter, file_id: 0,
        line_start: start_location.line_number, column_start: start_location.column_number,
        line_end: end_location.line_number, column_end: end_location.column_number + 1)
    end

    # Maps the source from *start_location* to right before *end_location* to
    # a gap region of *counter*.
    def add_gap_region(counter : Counter, start_location : Location, end_location : Location) : Nil
      @regions << CoverageMapping::Region.new(
        counter: counter, file_id: 0,
        line_start: start_location.line_number, column_start: start_location.column_number,
        line_end: end_location.line_number, column_end: end_location.column_number, gap: true)
    end

    def encode_mapping(filename_index : Int32) : Bytes
      CoverageMapping.encode_function([filename_index], @expressions, @regions)
    end

    # The profile data of a function is only matched to its mapping if their
    # hashes are equal, which rejects profiles of a different layout. Unused
    # functions have no profile data, `llvm-cov` expects a hash of 0.
    #
    # Must only be called once all regions are added.
    def structural_hash : UInt64
      @structural_hash ||= used? ? CoverageMapping.md5_hash(encode_mapping(0)) : 0_u64
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
  class CoverageRegionBuilder < Visitor
    alias Counter = CoverageMapping::Counter
    alias NodeCounters = Hash(ASTNode, {CoverageFunction, Int32})

    @counter : Counter
    @escapes = Hash(ASTNode, Bool).new.compare_by_identity

    # Counters are added to *entry_counters* for the nodes to increment them
    # before, and to *continuation_counters* for the nodes to increment them
    # after.
    def initialize(@function : CoverageFunction, @entry_counters : NodeCounters, @continuation_counters : NodeCounters)
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
        @function.add_region(@counter, location, a_def.end_location.not_nil!)
      else
        call_location = location.expanded_location.not_nil!
        @function.add_region(@counter, call_location, call_location)
      end
      a_def.body.accept self
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
      value.accept self
    end

    # Builds the regions of each executable statement of a file's top-level
    # code, and assigns the function's entry counter to the first statement.
    def build_top_level(statements : Array(ASTNode)) : Nil
      visit_statements(statements, top_level: true)
      if (first = statements.first?) && !@function.regions.empty?
        @entry_counters[first] = {@function, 0}
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
      return true unless in_function_file?(node)

      node.cond.accept self
      parent = @counter
      then_counter = add_counter(node.then, @entry_counters)

      # The expansions of `a && b` and `a || b` repeat `a` as a branch, which
      # must not map the source of `a` a second time. Expanded conditions,
      # like those of `case`, may have no end location.
      visit_branch(node.then, then_counter, location_after(node.cond) || node.location,
        region: !same_start?(node.then, node.cond))
      visit_branch(node.else, @function.add_expression(:subtract, parent, then_counter),
        location_after(node.then) || location_after(node.cond) || node.location,
        region: !same_start?(node.else, node.cond))

      @counter = parent
      false
    end

    def visit(node : While)
      return true unless in_function_file?(node)

      parent = @counter
      body_counter = add_counter(node.body, @entry_counters)
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
        if in_function_file?(block)
          parent = @counter
          visit_branch(block.body, add_counter(block.body, @entry_counters), block.location)
          @counter = parent
        else
          block.body.accept self
        end
      end

      false
    end

    def visit(node : ExceptionHandler)
      return true unless in_function_file?(node)

      parent = @counter
      node.body.accept self
      @counter = parent

      branches = node.rescues.try(&.map(&.body)) || [] of ASTNode
      node.else.try { |node_else| branches << node_else }
      node.ensure.try { |node_ensure| branches << node_ensure }
      previous = node.body
      branches.each do |branch|
        visit_branch(branch, add_counter(branch, @entry_counters), location_after(previous))
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
      # The expansions of literals, like `{"a" => -> { 1 }}`, are statements
      # located at parts of the literal, which would map the source of a proc
      # literal, its own function, a second time
      unless source_ordered?(statements)
        statements.each &.accept(self)
        return
      end

      previous = nil
      continued = false
      statements.each_with_index do |statement, index|
        next if top_level && declaration?(statement)

        # After a continuation counter, the lines of each statement must start
        # in a region of that counter rather than in the enclosing region.
        # Top-level statements have no enclosing region, and declarations
        # between them must stay unmapped.
        if continued && previous && !top_level
          add_gap_region(location_after(previous), statement, @counter)
        end
        add_region(statement, statement, @counter)
        statement.accept self
        previous = statement

        next if index == statements.size - 1 || !escapes?(statement)

        @counter = add_counter(statement, @continuation_counters)
        continued = true
      end
    end

    # Maps *node* to *counter*, preceded by a gap region from *gap_start*.
    # Returns `true` if the located *statements* follow each other in the
    # source without overlapping, like parsed statements do.
    private def source_ordered?(statements)
      previous_end = nil
      statements.each do |statement|
        start_location = start_location(statement)
        end_location = end_location(statement)
        next unless start_location && end_location
        next unless start_location.filename == @function.filename && end_location.filename == @function.filename

        return false if previous_end && !(start_location <=> previous_end).try(&.>(0))
        previous_end = end_location
      end
      true
    end

    private def visit_branch(node, counter, gap_start : Location?, region = true)
      if region
        add_gap_region(gap_start, node, counter)
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
    # are known and in the function's file. Returns whether it did.
    private def add_region(first : ASTNode | Location, last : ASTNode, counter) : Bool
      start_location = first.is_a?(Location) ? first : start_location(first)
      end_location = end_location(last)
      return false unless start_location && end_location
      return false unless start_location.filename == @function.filename && end_location.filename == @function.filename
      return false unless (start_location <=> end_location).try(&.<=(0))

      @function.add_region(counter, start_location, end_location)
      true
    end

    # Maps the source from *start_location* to right before *node*, if it's
    # not empty and in the function's file.
    private def add_gap_region(start_location, node : ASTNode, counter)
      add_gap_region(start_location, start_location(node), counter)
    end

    private def add_gap_region(start_location, end_location : Location?, counter)
      return unless start_location && end_location
      return unless start_location.filename == @function.filename
      return unless (start_location <=> end_location).try(&.<(0))

      @function.add_gap_region(counter, start_location, end_location)
    end

    private def location_after(node) : Location?
      if end_location = end_location(node)
        Location.new(end_location.filename, end_location.line_number, end_location.column_number + 1)
      end
    end

    private def start_location(node) : Location?
      node.location || node.as?(Expressions).try(&.expressions.first?).try { |exp| start_location(exp) }
    end

    private def end_location(node) : Location?
      node.end_location || node.as?(Expressions).try(&.expressions.last?).try { |exp| end_location(exp) }
    end

    private def in_function_file?(node)
      node.location.try(&.filename) == @function.filename
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
