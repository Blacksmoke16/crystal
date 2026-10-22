require "./codegen"
require "./coverage_mapping"

class Crystal::CodeGenVisitor
  # A function in the coverage mapping: one typed def instance, named like its
  # LLVM function. Its body is either codegen'd once as an LLVM function or
  # inlined at each call site (defs that yield, trivial getters), so the
  # counters of a function can be incremented from any LLVM function and
  # module.
  #
  # An unused function is a def that was never codegen'd. It has no counters
  # and maps its source to zero executions.
  class CoverageFunction
    getter name : String
    getter filename : String
    getter location : Location
    getter regions : Array(CoverageMapping::Region)
    getter structural_hash : UInt64
    getter? used : Bool

    def initialize(@name : String, @filename : String, @location : Location, end_location : Location, *, @used : Bool = true)
      counter = used? ? CoverageMapping::Counter.reference(0) : CoverageMapping::Counter.zero
      @regions = [
        CoverageMapping::Region.new(
          counter: counter, file_id: 0,
          line_start: location.line_number, column_start: location.column_number,
          line_end: end_location.line_number, column_end: end_location.column_number + 1),
      ]

      # The profile data of a function is only matched to its mapping if
      # their hashes are equal, which rejects profiles of a different layout.
      # Unused functions have no profile data, `llvm-cov` expects a hash of 0.
      @structural_hash = if used?
                           CoverageMapping.md5_hash(
                             CoverageMapping.encode_function([0], [] of CoverageMapping::Expression, @regions))
                         else
                           0_u64
                         end
    end

    def num_counters
      1
    end
  end

  @coverage_functions = {} of String => CoverageFunction
  @coverage_functions_by_module = {} of LLVM::Module => Set(CoverageFunction)

  # Counts an execution of *target_def*'s body, if coverage instrumentation
  # is enabled. *mangled_name* identifies the typed def instance.
  def emit_def_coverage_counter(target_def : Def, mangled_name : String)
    return unless @coverage
    return unless function = coverage_function(target_def, mangled_name)

    emit_coverage_counter(function, 0)
  end

  private def coverage_function(target_def, mangled_name) : CoverageFunction?
    if function = @coverage_functions[mangled_name]?
      return function
    end

    return unless coverable_def?(target_def)
    location = target_def.location.not_nil!

    @coverage_functions[mangled_name] = CoverageFunction.new(
      mangled_name, location.filename.as(String), location, target_def.end_location.not_nil!)
  end

  private def coverable_def?(a_def)
    # The `new` expanded from an `initialize` maps to the same source, which
    # its call to `initialize` already counts
    return false if a_def.new?

    # Primitives have no source body, and defs expanded from macros have no
    # source file to map regions to.
    return false if a_def.body.is_a?(Primitive)
    return false unless a_def.location.try(&.filename).is_a?(String) && a_def.end_location

    true
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
    used_locations = @coverage_functions.each_value.map { |function| coverage_location_key(function.location) }.to_set
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

    location = a_def.location.not_nil!
    return unless used_locations.add?(coverage_location_key(location))

    # Used functions are named after their LLVM functions, which start with
    # `*`, so these names can't clash with them.
    unused_functions << CoverageFunction.new(
      "#{a_def.short_reference} at #{location}", location.filename.as(String),
      location, a_def.end_location.not_nil!, used: false)
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
    mapping = CoverageMapping.encode_function([filename_index], [] of CoverageMapping::Expression, function.regions)
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
