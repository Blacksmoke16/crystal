require "./lib_llvm_ext"
require "./function"
require "./basic_block"
require "./builder"

module LLVM
  module Coverage
    # Instrument a function with coverage counters at each basic block
    def self.instrument_function(func : Function)
      # Get the module
      mod_ref = LibLLVM.get_global_parent(func)

      # Get instrprof.increment intrinsic
      intrinsic = LibLLVMExt.get_instrprof_increment_func(mod_ref)

      # Get function name
      name = func.name
      return if name.starts_with?("llvm.") # Skip LLVM intrinsics

      # For testing: ONLY instrument user-defined top-level functions
      # Allow "*functionname:ReturnType" pattern (Crystal's simple functions)
      # Skip Crystal internal functions (those with multiple * or complex names)
      return if name.includes?("~")
      return if name.includes?("@")
      return if name.starts_with?("_")
      return if name.starts_with?("__")

      # Allow only simple patterns like "*test_function:Int32" or "*main:Nil"
      # Skip if contains :: (methods), multiple *, or < (generics)
      return if name.includes?("::")
      return if name.count("*") > 1
      return if name.includes?("<")
      return if name.includes?("Crystal::")

      # Must start with * and have a simple function name or class method
      # Allows: *function:Type or *Class#method:Type
      return unless name.starts_with?("*")
      return unless name =~ /^\*[a-z_][a-z0-9_#]*:/i

      # Count basic blocks first - skip if function has no body (is declaration)
      num_counters = 0_u32
      func.basic_blocks.each { num_counters += 1 }
      return if num_counters == 0 # Skip empty/external functions

      # Create profile name variable (only for functions with bodies)
      name_var = LibLLVMExt.create_profile_name_var(mod_ref, name, name.bytesize)

      # Compute function hash
      func_hash = LibLLVMExt.compute_function_hash(name, name.bytesize)

      # Insert increment at start of each basic block
      counter_index = 0_u32
      func.basic_blocks.each do |bb|
        # Get context and create builder
        context = LibLLVM.get_module_context(mod_ref)
        builder_ref = LibLLVM.create_builder_in_context(context)

        # Get first safe insertion point (after PHI nodes) using C++ helper
        insert_point = LibLLVMExt.get_first_insertion_pt(bb)
        if insert_point
          LibLLVM.position_builder_before(builder_ref, insert_point)
        else
          # Block is empty (shouldn't happen in practice)
          LibLLVM.position_builder_at_end(builder_ref, bb)
        end

        # Insert increment call
        LibLLVMExt.insert_instrprof_increment(
          builder_ref, intrinsic, name_var,
          func_hash, num_counters, counter_index
        )

        # Clean up builder
        LibLLVM.dispose_builder(builder_ref)

        counter_index += 1
      end
    end
  end
end
