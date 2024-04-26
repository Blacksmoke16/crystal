{% skip_file if LibLLVM::IS_LT_130 %}

require "../target_machine"
require "../types"

lib LibLLVM
  struct PassBuilderOptionsRef
    debug_logging : Bool
    verify_each : Bool
    pipeline_tuning_options : Void*
  end

  fun run_passes = LLVMRunPasses(m : ModuleRef, passes : Char*, tm : TargetMachineRef, options : PassBuilderOptionsRef*) : ErrorRef

  fun create_pass_builder_options = LLVMCreatePassBuilderOptions : PassBuilderOptionsRef*
  fun dispose_pass_builder_options = LLVMDisposePassBuilderOptions(options : PassBuilderOptionsRef*)
end
