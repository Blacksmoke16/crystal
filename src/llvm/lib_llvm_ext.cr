require "./lib_llvm"
{% if flag?(:win32) %}
  @[Link(ldflags: "#{__DIR__}/ext/llvm_ext.obj")]
{% else %}
  @[Link(ldflags: "#{__DIR__}/ext/llvm_ext.o")]
{% end %}
lib LibLLVMExt
  alias Char = LibC::Char
  alias Int = LibC::Int
  alias UInt = LibC::UInt
  alias SizeT = LibC::SizeT

  {% if LibLLVM::IS_LT_90 %}
    fun di_builder_create_enumerator = LLVMExtDIBuilderCreateEnumerator(builder : LibLLVM::DIBuilderRef, name : Char*, name_len : SizeT, value : Int64, is_unsigned : LibLLVM::Bool) : LibLLVM::MetadataRef
    fun clear_current_debug_location = LLVMExtClearCurrentDebugLocation(b : LibLLVM::BuilderRef)
  {% end %}

  fun create_operand_bundle = LLVMExtCreateOperandBundle(tag : Char*, tag_len : SizeT,
                                                         args : LibLLVM::ValueRef*,
                                                         num_args : UInt) : LibLLVM::OperandBundleRef

  fun dispose_operand_bundle = LLVMExtDisposeOperandBundle(bundle : LibLLVM::OperandBundleRef)

  fun build_call_with_operand_bundles = LLVMExtBuildCallWithOperandBundles(LibLLVM::BuilderRef, LibLLVM::TypeRef, fn : LibLLVM::ValueRef,
                                                                           args : LibLLVM::ValueRef*, num_args : UInt,
                                                                           bundles : LibLLVM::OperandBundleRef*, num_bundles : UInt,
                                                                           name : Char*) : LibLLVM::ValueRef

  fun build_invoke_with_operand_bundles = LLVMExtBuildInvokeWithOperandBundles(LibLLVM::BuilderRef, ty : LibLLVM::TypeRef, fn : LibLLVM::ValueRef,
                                                                               args : LibLLVM::ValueRef*, num_args : UInt,
                                                                               then : LibLLVM::BasicBlockRef, catch : LibLLVM::BasicBlockRef,
                                                                               bundles : LibLLVM::OperandBundleRef*, num_bundles : UInt,
                                                                               name : Char*) : LibLLVM::ValueRef

  fun set_target_machine_global_isel = LLVMExtSetTargetMachineGlobalISel(t : LibLLVM::TargetMachineRef, enable : LibLLVM::Bool)

  # Coverage instrumentation support
  fun get_instrprof_increment_func = LLVMExtGetInstrProfIncrementFunc(m : LibLLVM::ModuleRef) : LibLLVM::ValueRef
  fun create_profile_name_var = LLVMExtCreateProfileNameVar(m : LibLLVM::ModuleRef, func_name : Char*, func_name_len : SizeT) : LibLLVM::ValueRef
  fun compute_function_hash = LLVMExtComputeFunctionHash(func_name : Char*, func_name_len : SizeT) : UInt64
  fun insert_instrprof_increment = LLVMExtInsertInstrProfIncrement(builder : LibLLVM::BuilderRef, intrinsic_func : LibLLVM::ValueRef, name_ptr : LibLLVM::ValueRef, func_hash : UInt64, num_counters : UInt32, counter_index : UInt32)
  fun get_first_insertion_pt = LLVMExtGetFirstInsertionPt(bb : LibLLVM::BasicBlockRef) : LibLLVM::ValueRef
  fun generate_coverage_mapping = LLVMExtGenerateCoverageMapping(m : LibLLVM::ModuleRef, source_file : Char*)
  fun run_passes_with_coverage = LLVMExtRunPassesWithCoverage(m : LibLLVM::ModuleRef, passes : Char*, tm : LibLLVM::TargetMachineRef, options : LibLLVM::PassBuilderOptionsRef, enable_coverage : LibLLVM::Bool, source_file : Char*) : LibLLVM::ErrorRef
end
