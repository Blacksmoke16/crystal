require "./types"

lib LibLLVM
  fun get_or_insert_comdat = LLVMGetOrInsertComdat(m : ModuleRef, name : Char*) : ComdatRef
  fun set_comdat = LLVMSetComdat(v : ValueRef, c : ComdatRef)
end
