require "./codegen"
require "./coverage_mapping"

class Crystal::CodeGenVisitor
  # Coverage functions of typed def instances, named like their LLVM
  # functions. A body is either codegen'd once as an LLVM function or inlined
  # at each call site (defs that yield, trivial getters), so the counters of
  # a function can be incremented from any LLVM function and module.
  @coverage_functions = Hash(Def, CoverageFunction?).new.compare_by_identity
  @coverage_initializer_functions = Hash(ASTNode, CoverageFunction?).new.compare_by_identity
  @coverage_function_names = Set(String).new
  @coverage_def_locations = Set({String, Int32, Int32}).new
  @coverage_functions_by_module = {} of LLVM::Module => Set(CoverageFunction)
  @coverage_entry_counters = CoverageRegionBuilder::NodeCounters.new.compare_by_identity
  @coverage_continuation_counters = CoverageRegionBuilder::NodeCounters.new.compare_by_identity

  # Counts an execution of *target_def*'s body, if coverage instrumentation
  # is enabled. *mangled_name* identifies the typed def instance.
  def emit_def_coverage_counter(target_def : Def, mangled_name : String)
    return unless @coverage
    return unless function = coverage_function(target_def, mangled_name)

    emit_coverage_counter(function, 0)
  end

  private def coverage_function(target_def, mangled_name) : CoverageFunction?
    @coverage_functions.put_if_absent(target_def) do
      next unless coverable_def?(target_def)

      location = target_def.location.not_nil!
      source_filename = location.expanded_location.not_nil!.filename.as(String)
      next unless instrument_coverage?(source_filename)

      # Typed defs that differ only in the type of their block have the
      # same name, but not necessarily the same counters
      function = CoverageFunction.new(unique_coverage_function_name(mangled_name), source_filename)
      CoverageRegionBuilder.new(function, @coverage_entry_counters, @coverage_continuation_counters, coverage_source_lines(function.filename)).build_def(target_def)
      @coverage_def_locations << coverage_location_key(location) if location.filename.is_a?(String)
      function
    end
  end

  # Counts an execution of the initializer of a constant or class variable
  # named *name*, whose source starts at *location* and ends with *value*.
  def emit_initializer_coverage_counter(name : String, location : Location?, value : ASTNode)
    initializer_function = @coverage_initializer_functions.put_if_absent(value) do
      # A declaration expanded from a macro maps to the macro call
      location = location.try(&.expanded_location)
      next unless location && (filename = location.filename).is_a?(String)
      next unless instrument_coverage?(filename)

      function = CoverageFunction.new(unique_coverage_function_name("#{name} initializer"), filename)
      CoverageRegionBuilder.new(function, @coverage_entry_counters, @coverage_continuation_counters, coverage_source_lines(function.filename)).build_initializer(location, value)

      # A value expanded from a macro has no source to map
      function unless function.regions.empty?
    end

    emit_coverage_counter(initializer_function, 0) if initializer_function
  end

  private def unique_coverage_function_name(name)
    unique_name = name
    suffix = 1
    until @coverage_function_names.add?(unique_name)
      suffix += 1
      unique_name = "#{name} (#{suffix})"
    end
    unique_name
  end

  # Builds the coverage functions of each file's top-level code in the
  # program *node*.
  private def build_top_level_coverage(node)
    statements_by_file = {} of String => Array(ASTNode)
    collect_top_level_statements(node, statements_by_file)

    statements_by_file.each do |filename, statements|
      next unless instrument_coverage?(filename)

      function = CoverageFunction.new("__crystal_main #{filename}", filename)
      CoverageRegionBuilder.new(function, @coverage_entry_counters, @coverage_continuation_counters, coverage_source_lines(function.filename)).build_top_level(statements)
    end
  end

  private def collect_top_level_statements(node, statements_by_file)
    case node
    when Expressions
      node.expressions.each { |exp| collect_top_level_statements(exp, statements_by_file) }
    when FileNode
      collect_top_level_statements(node.node, statements_by_file)
    else
      if filename = node.location.try(&.filename).as?(String)
        (statements_by_file[filename] ||= [] of ASTNode) << node
      end
    end
  end

  private def emit_coverage_entry_counter(node)
    if entry = @coverage_entry_counters[node]?
      emit_coverage_counter(*entry)
    end
  end

  private def emit_coverage_continuation_counter(node)
    if entry = @coverage_continuation_counters[node]?
      emit_coverage_counter(*entry)
    end
  end

  # The lines of each source file, read from disk like error messages do.
  @coverage_source_lines = {} of String => Array(String)?

  private def coverage_source_lines(filename : String) : Array(String)?
    @coverage_source_lines.put_if_absent(filename) do
      File.read_lines(filename) if File.file?(filename)
    rescue IO::Error
      nil
    end
  end

  private def instrument_coverage?(filename : String) : Bool
    @coverage_filter.nil? || @coverage_filter.not_nil!.match?(filename)
  end

  private def coverable_def?(a_def)
    # The `new` expanded from an `initialize` maps to the same source, which
    # its call to `initialize` already counts
    return false if a_def.new?

    # Primitives have no source body
    return false if a_def.body.is_a?(Primitive)

    # Defs expanded from macros map to the macro call
    return false unless location = a_def.location
    location.filename.is_a?(String) ? !!a_def.end_location : !!location.expanded_location
  end

  private def emit_coverage_counter(function : CoverageFunction, index : Int32)
    (@coverage_functions_by_module[@llvm_mod] ||= Set(CoverageFunction).new) << function

    increment = fetch_typed_fun(@llvm_mod, "llvm.instrprof.increment") do
      LLVM::Type.function([llvm_context.void_pointer, llvm_context.int64, llvm_context.int32, llvm_context.int32], llvm_context.void)
    end
    call increment, [
      cast_to_void_pointer(coverage_name_var(@llvm_mod, function)),
      int64(function.structural_hash),
      int32(function.num_counters),
      int32(index),
    ]
  end

  # The `instrprof` pass names a function's counters after this variable,
  # and its contents become the function name in the profile.
  private def coverage_name_var(llvm_mod : LLVM::Module, function : CoverageFunction)
    var_name = "__profn_#{function.name}"
    if global = llvm_mod.globals[var_name]?
      return global
    end

    global = llvm_mod.globals.add(llvm_mod.context.int8.array(function.name.bytesize), var_name)
    global.linkage = LLVM::Linkage::Private
    global.global_constant = true
    global.initializer = llvm_mod.context.const_bytes(function.name.to_slice)
    global
  end

  # Emits the coverage mapping of the functions whose counters each module
  # increments, and of the unused functions.
  def emit_coverage_mappings
    unused_functions = collect_unused_coverage_functions
    unless unused_functions.empty?
      (@coverage_functions_by_module[@main_mod] ||= Set(CoverageFunction).new).concat(unused_functions)
      emit_unused_coverage_names(@main_mod, unused_functions)
    end

    @coverage_functions_by_module.each do |llvm_mod, functions|
      emit_coverage_mapping(llvm_mod, functions)
    end
  end

  private def collect_unused_coverage_functions
    used_locations = @coverage_def_locations.dup
    unused_functions = [] of CoverageFunction
    collect_unused_coverage_functions(@program, used_locations, unused_functions)
    unused_functions
  end

  private def collect_unused_coverage_functions(type, used_locations, unused_functions)
    if type.is_a?(ModuleType)
      type.defs.try &.each_value do |defs_with_metadata|
        defs_with_metadata.each do |def_with_metadata|
          a_def = def_with_metadata.def
          while a_def
            add_unused_coverage_function(a_def, used_locations, unused_functions)
            a_def = a_def.previous.try(&.def)
          end
        end
      end
    end

    type.types?.try &.each_value do |inner_type|
      collect_unused_coverage_functions(inner_type, used_locations, unused_functions)
    end

    if (metaclass = type.metaclass) != type
      collect_unused_coverage_functions(metaclass, used_locations, unused_functions)
    end
  end

  private def add_unused_coverage_function(a_def, used_locations, unused_functions)
    return if a_def.abstract? || a_def.autogenerated? || a_def.is_a?(External)
    return unless coverable_def?(a_def)

    # Unused defs expanded from macros aren't reported: a macro call may
    # expand to many defs that the program isn't expected to use
    return unless a_def.location.try(&.filename).is_a?(String)

    location = a_def.location.not_nil!
    return unless instrument_coverage?(location.filename.as(String))
    return unless used_locations.add?(coverage_location_key(location))

    # Used functions are named after their LLVM functions, which start with
    # `*`, so these names can't clash with them.
    function = CoverageFunction.new("#{a_def.short_reference} at #{location}", location.filename.as(String), used: false)
    CoverageRegionBuilder.new(function, @coverage_entry_counters, @coverage_continuation_counters, coverage_source_lines(function.filename)).build_unused_def(a_def)
    unused_functions << function
  end

  private def coverage_location_key(location)
    {location.filename.as(String), location.line_number, location.column_number}
  end

  # The `instrprof` pass adds the names of unused functions to the profile
  # names that `llvm-cov` reads from the binary.
  private def emit_unused_coverage_names(llvm_mod, functions)
    names = functions.map { |function| coverage_name_var(llvm_mod, function) }
    global = llvm_mod.globals.add(llvm_mod.context.void_pointer.array(names.size), "__llvm_coverage_names")
    global.linkage = LLVM::Linkage::Internal
    global.global_constant = true
    global.initializer = llvm_mod.context.void_pointer.const_array(names)
  end

  private def emit_coverage_mapping(llvm_mod, functions)
    # The counters of a function may have been removed along with the code
    # that incremented them, such as a class variable initializer that
    # turned out to be a constant. `llvm-cov` can't handle functions without
    # regions.
    functions = functions.select do |function|
      next false if function.regions.empty?

      !function.used? || llvm_mod.globals["__profn_#{function.name}"]?.try { |name_var| !name_var.use_empty? }
    end
    return if functions.empty?

    filenames = [Dir.current]
    filename_indices = {} of String => Int32
    functions.each do |function|
      filename_indices.put_if_absent(function.filename) do
        filenames << function.filename
        filenames.size - 1
      end
    end

    encoded_filenames = CoverageMapping.encode_filenames(filenames)
    filenames_hash = CoverageMapping.md5_hash(encoded_filenames)

    used = functions.map do |function|
      emit_coverage_function_record(llvm_mod, function, filename_indices[function.filename], filenames_hash)
    end
    used << emit_coverage_filenames(llvm_mod, encoded_filenames)

    used_var = llvm_mod.globals.add(llvm_mod.context.void_pointer.array(used.size), "llvm.used")
    used_var.linkage = LLVM::Linkage::Appending
    used_var.section = "llvm.metadata"
    used_var.initializer = llvm_mod.context.void_pointer.const_array(used)
  end

  private def emit_coverage_function_record(llvm_mod, function, filename_index, filenames_hash)
    llvm_context = llvm_mod.context
    mapping = function.encode_mapping(filename_index)
    name_hash = CoverageMapping.md5_hash(function.name)

    type = llvm_context.struct([
      llvm_context.int64, llvm_context.int32, llvm_context.int64, llvm_context.int64,
      llvm_context.int8.array(mapping.size),
    ], packed: true)

    # Every module that uses a function emits its record, so the linker
    # keeps only one copy. The `u` suffix marks records of used functions.
    record_name = "__covrec_#{name_hash.to_s(16).upcase}#{"u" if function.used?}"
    global = llvm_mod.globals.add(type, record_name)
    global.linkage = LLVM::Linkage::LinkOnceODR
    global.visibility = LLVM::Visibility::Hidden
    global.global_constant = true
    global.initializer = llvm_context.const_struct([
      llvm_context.int64.const_int(name_hash),
      llvm_context.int32.const_int(mapping.size),
      llvm_context.int64.const_int(function.structural_hash),
      llvm_context.int64.const_int(filenames_hash),
      llvm_context.const_bytes(mapping),
    ], packed: true)
    global.section = coverage_section("covfun")
    global.alignment = 8
    global.comdat = llvm_mod.get_or_insert_comdat(record_name) unless @program.has_flag?("darwin")
    global
  end

  private def emit_coverage_filenames(llvm_mod, encoded_filenames)
    llvm_context = llvm_mod.context
    int32 = llvm_context.int32
    header_type = llvm_context.struct([int32, int32, int32, int32])
    type = llvm_context.struct([header_type, llvm_context.int8.array(encoded_filenames.size)])

    global = llvm_mod.globals.add(type, "__llvm_coverage_mapping")
    global.linkage = LLVM::Linkage::Private
    global.global_constant = true
    global.initializer = llvm_context.const_struct([
      # function records count and mapping size are always 0: function
      # records are stored in the covfun section
      llvm_context.const_struct([
        int32.const_int(0),
        int32.const_int(encoded_filenames.size),
        int32.const_int(0),
        int32.const_int(CoverageMapping::VERSION),
      ]),
      llvm_context.const_bytes(encoded_filenames),
    ])
    global.section = coverage_section("covmap")
    global.alignment = 8
    global
  end

  private def coverage_section(name)
    if @program.has_flag?("darwin")
      "__LLVM_COV,__llvm_#{name}"
    elsif @program.has_flag?("win32")
      ".l#{name}$M"
    else
      "__llvm_#{name}"
    end
  end
end
