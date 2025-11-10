#include <llvm/Config/llvm-config.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/IntrinsicInst.h>
#include <llvm/IR/Module.h>
#include <llvm/Passes/PassBuilder.h>
#include <llvm/Transforms/Instrumentation/InstrProfiling.h>
#include <llvm/Transforms/Instrumentation/PGOInstrumentation.h>
#include <llvm/Target/TargetMachine.h>
#include <llvm-c/Core.h>
#include <llvm-c/TargetMachine.h>
#include <llvm-c/Transforms/PassBuilder.h>
#include <llvm/ADT/SmallVector.h>
#include <llvm/Support/MD5.h>
#include <llvm/ProfileData/Coverage/CoverageMapping.h>
#include <llvm/ProfileData/Coverage/CoverageMappingWriter.h>
#include <llvm/Support/raw_ostream.h>
#include <vector>
#include <string>

using namespace llvm;

#define LLVM_VERSION_GE(major, minor) \
  (LLVM_VERSION_MAJOR > (major) || LLVM_VERSION_MAJOR == (major) && LLVM_VERSION_MINOR >= (minor))

#if !LLVM_VERSION_GE(9, 0)
#include <llvm/IR/DIBuilder.h>
#endif

#if LLVM_VERSION_GE(16, 0)
#define makeArrayRef ArrayRef
#endif

#if !LLVM_VERSION_GE(18, 0)
typedef struct LLVMOpaqueOperandBundle *LLVMOperandBundleRef;
DEFINE_SIMPLE_CONVERSION_FUNCTIONS(OperandBundleDef, LLVMOperandBundleRef)
#endif

extern "C" {

#if !LLVM_VERSION_GE(9, 0)
LLVMMetadataRef LLVMExtDIBuilderCreateEnumerator(LLVMDIBuilderRef Builder,
                                                 const char *Name, size_t NameLen,
                                                 int64_t Value,
                                                 LLVMBool IsUnsigned) {
  return wrap(unwrap(Builder)->createEnumerator({Name, NameLen}, Value,
                                                IsUnsigned != 0));
}

void LLVMExtClearCurrentDebugLocation(LLVMBuilderRef B) {
  unwrap(B)->SetCurrentDebugLocation(DebugLoc::get(0, 0, nullptr));
}
#endif

#if !LLVM_VERSION_GE(18, 0)
LLVMOperandBundleRef LLVMExtCreateOperandBundle(const char *Tag, size_t TagLen,
                                                LLVMValueRef *Args,
                                                unsigned NumArgs) {
  return wrap(new OperandBundleDef(std::string(Tag, TagLen),
                                   makeArrayRef(unwrap(Args), NumArgs)));
}

void LLVMExtDisposeOperandBundle(LLVMOperandBundleRef Bundle) {
  delete unwrap(Bundle);
}

LLVMValueRef
LLVMExtBuildCallWithOperandBundles(LLVMBuilderRef B, LLVMTypeRef Ty,
                                   LLVMValueRef Fn, LLVMValueRef *Args,
                                   unsigned NumArgs, LLVMOperandBundleRef *Bundles,
                                   unsigned NumBundles, const char *Name) {
  FunctionType *FTy = unwrap<FunctionType>(Ty);
  SmallVector<OperandBundleDef, 8> OBs;
  for (auto *Bundle : makeArrayRef(Bundles, NumBundles)) {
    OperandBundleDef *OB = unwrap(Bundle);
    OBs.push_back(*OB);
  }
  return wrap(unwrap(B)->CreateCall(
      FTy, unwrap(Fn), makeArrayRef(unwrap(Args), NumArgs), OBs, Name));
}

LLVMValueRef LLVMExtBuildInvokeWithOperandBundles(
    LLVMBuilderRef B, LLVMTypeRef Ty, LLVMValueRef Fn, LLVMValueRef *Args,
    unsigned NumArgs, LLVMBasicBlockRef Then, LLVMBasicBlockRef Catch,
    LLVMOperandBundleRef *Bundles, unsigned NumBundles, const char *Name) {
  SmallVector<OperandBundleDef, 8> OBs;
  for (auto *Bundle : makeArrayRef(Bundles, NumBundles)) {
    OperandBundleDef *OB = unwrap(Bundle);
    OBs.push_back(*OB);
  }
  return wrap(unwrap(B)->CreateInvoke(
      unwrap<FunctionType>(Ty), unwrap(Fn), unwrap(Then), unwrap(Catch),
      makeArrayRef(unwrap(Args), NumArgs), OBs, Name));
}
#endif

#if !LLVM_VERSION_GE(18, 0)
static TargetMachine *unwrap(LLVMTargetMachineRef P) {
  return reinterpret_cast<TargetMachine *>(P);
}

void LLVMExtSetTargetMachineGlobalISel(LLVMTargetMachineRef T, LLVMBool Enable) {
  unwrap(T)->setGlobalISel(Enable);
}
#endif

// Coverage instrumentation support
LLVMValueRef LLVMExtGetInstrProfIncrementFunc(LLVMModuleRef M) {
  Module *Mod = unwrap(M);
  return wrap(Intrinsic::getOrInsertDeclaration(
    Mod, Intrinsic::instrprof_increment));
}

LLVMValueRef LLVMExtCreateProfileNameVar(LLVMModuleRef M,
                                          const char *FuncName,
                                          size_t FuncNameLen) {
  Module *Mod = unwrap(M);
  StringRef Name(FuncName, FuncNameLen);

  // Create global for profile name
  auto *NamePtr = Mod->getOrInsertGlobal(
    ("__profn_" + Name).str(),
    ArrayType::get(Type::getInt8Ty(Mod->getContext()), Name.size()));

  auto *NameVar = cast<GlobalVariable>(NamePtr);
  NameVar->setConstant(true);
  NameVar->setLinkage(GlobalValue::PrivateLinkage);

  // Initialize with function name
  NameVar->setInitializer(ConstantDataArray::getRaw(
    Name, Name.size(), Type::getInt8Ty(Mod->getContext())));

  return wrap(NameVar);
}

uint64_t LLVMExtComputeFunctionHash(const char *FuncName, size_t Len) {
  // Simple DJB2 hash
  uint64_t hash = 5381;
  for (size_t i = 0; i < Len; i++) {
    hash = ((hash << 5) + hash) + (unsigned char)FuncName[i];
  }
  return hash;
}

void LLVMExtInsertInstrProfIncrement(LLVMBuilderRef B,
                                     LLVMValueRef IntrinsicFunc,
                                     LLVMValueRef NamePtr,
                                     uint64_t FuncHash,
                                     uint32_t NumCounters,
                                     uint32_t CounterIndex) {
  IRBuilder<> *Builder = unwrap(B);
  Function *IntrFunc = unwrap<Function>(IntrinsicFunc);
  Value *Name = unwrap(NamePtr);

  // Cast function name to opaque pointer (matching Clang's approach)
  Value *NamePtrCast = ConstantExpr::getPointerBitCastOrAddrSpaceCast(
    cast<Constant>(Name),
    PointerType::get(Builder->getContext(), 0));

  // Create call: llvm.instrprof.increment(ptr name, i64 hash, i32 num, i32 idx)
  Builder->CreateCall(IntrFunc, {
    NamePtrCast,
    ConstantInt::get(Type::getInt64Ty(Builder->getContext()), FuncHash),
    ConstantInt::get(Type::getInt32Ty(Builder->getContext()), NumCounters),
    ConstantInt::get(Type::getInt32Ty(Builder->getContext()), CounterIndex)
  });
}

// Generate coverage mapping metadata
void LLVMExtGenerateCoverageMapping(LLVMModuleRef M, const char *SourceFile) {
  Module *Mod = unwrap(M);
  LLVMContext &Ctx = Mod->getContext();

  // Coverage mapping format version 6 (current stable)
  const uint32_t CovMapVersion = 6;

  // Step 1: Create simple file table (just one source file for now)
  // Use CoverageFilenamesSectionWriter to properly encode and compress filenames
  std::vector<std::string> Filenames = {std::string(SourceFile)};
  coverage::CoverageFilenamesSectionWriter FilenamesWriter(Filenames);

  std::string FilenamesStr;
  raw_string_ostream FilenamesOS(FilenamesStr);
  FilenamesWriter.write(FilenamesOS, true); // true = compress
  FilenamesOS.flush();

  std::vector<uint8_t> FilenamesBuffer(FilenamesStr.begin(), FilenamesStr.end());

  // Step 2: Create __llvm_covmap global
  // Header: [unused, filenames_len, unused, version]
  Constant *CovMapHeader = ConstantStruct::get(
    StructType::get(Ctx, {
      Type::getInt32Ty(Ctx),  // unused
      Type::getInt32Ty(Ctx),  // filenames length
      Type::getInt32Ty(Ctx),  // unused
      Type::getInt32Ty(Ctx)   // version
    }),
    {
      ConstantInt::get(Type::getInt32Ty(Ctx), 0),
      ConstantInt::get(Type::getInt32Ty(Ctx), FilenamesBuffer.size()),
      ConstantInt::get(Type::getInt32Ty(Ctx), 0),
      ConstantInt::get(Type::getInt32Ty(Ctx), CovMapVersion)
    }
  );

  // Filenames buffer as constant array
  Constant *FilenamesArray = ConstantDataArray::get(Ctx, FilenamesBuffer);

  // Combine header + filenames
  Constant *CovMapRecord = ConstantStruct::get(
    StructType::get(Ctx, {
      CovMapHeader->getType(),
      FilenamesArray->getType()
    }),
    {CovMapHeader, FilenamesArray}
  );

  // Create the global
  GlobalVariable *CovMapVar = new GlobalVariable(
    *Mod,
    CovMapRecord->getType(),
    true,  // isConstant
    GlobalValue::PrivateLinkage,
    CovMapRecord,
    "__llvm_coverage_mapping"
  );

  // Set section (platform-specific)
  CovMapVar->setSection("__llvm_covmap");
  CovMapVar->setAlignment(Align(8));
  // Don't strip this global
  CovMapVar->setLinkage(GlobalValue::LinkOnceODRLinkage);


  // Compute filenames hash for use in covfun records (MD5 hash)
  MD5 FilenamesHasher;
  FilenamesHasher.update(ArrayRef<uint8_t>(FilenamesBuffer));
  MD5::MD5Result FilenamesHashResult = FilenamesHasher.final();
  uint64_t FilenamesHash = FilenamesHashResult.low();

  // Step 3: Generate __llvm_covfun sections for instrumented functions
  // Format: i64 (name MD5), i32 (data length), i64 (func hash), i64 (filenames hash), bytes (mapping data)
  int covfun_count = 0;

  for (auto &G : Mod->globals()) {
    if (G.getName().starts_with("__profc_")) {
      // Extract function name (remove __profc_ prefix)
      std::string FuncName = G.getName().substr(8).str();

      // Compute MD5 hash of function name
      MD5 Hash;
      Hash.update(FuncName);
      MD5::MD5Result Result = Hash.final();
      uint64_t NameHashLow = Result.low();

      // Create coverage mapping region using LLVM API
      // Single code region on line 1, cols 1-10
      coverage::Counter C = coverage::Counter::getCounter(0);
      coverage::CounterMappingRegion Region =
          coverage::CounterMappingRegion::makeRegion(C, 0, 1, 1, 1, 10);

      // Use CoverageMappingWriter to properly encode the mapping data
      SmallVector<unsigned, 8> VirtualFileMapping = {0};
      ArrayRef<coverage::CounterExpression> Expressions;
      coverage::CounterMappingRegion Regions[] = {Region};
      MutableArrayRef<coverage::CounterMappingRegion> RegionsRef(Regions);

      std::string MappingDataStr;
      raw_string_ostream OS(MappingDataStr);
      coverage::CoverageMappingWriter Writer(VirtualFileMapping, Expressions, RegionsRef);
      Writer.write(OS);
      OS.flush();

      std::vector<uint8_t> MappingData(MappingDataStr.begin(), MappingDataStr.end());
      uint32_t MappingDataLength = MappingData.size();

      // Function structural hash: use same hash as instrumentation
      uint64_t FuncHash = LLVMExtComputeFunctionHash(FuncName.c_str(), FuncName.size());

      // Build the covfun record as raw bytes matching Clang's format
      std::vector<uint8_t> CovFunRecord;

      // i64: name hash (little-endian)
      for (int i = 0; i < 8; i++) {
        CovFunRecord.push_back((NameHashLow >> (i * 8)) & 0xFF);
      }

      // i32: mapping data length (little-endian)
      for (int i = 0; i < 4; i++) {
        CovFunRecord.push_back((MappingDataLength >> (i * 8)) & 0xFF);
      }

      // i64: function hash (little-endian)
      for (int i = 0; i < 8; i++) {
        CovFunRecord.push_back((FuncHash >> (i * 8)) & 0xFF);
      }

      // i64: filenames hash (little-endian)
      for (int i = 0; i < 8; i++) {
        CovFunRecord.push_back((FilenamesHash >> (i * 8)) & 0xFF);
      }

      // Mapping data bytes
      CovFunRecord.insert(CovFunRecord.end(), MappingData.begin(), MappingData.end());

      // Create constant array from bytes
      Constant *CovFunArray = ConstantDataArray::get(Ctx, CovFunRecord);

      // Create global for this function
      GlobalVariable *CovFunVar = new GlobalVariable(
        *Mod,
        CovFunArray->getType(),
        true,  // isConstant
        GlobalValue::LinkOnceODRLinkage,
        CovFunArray,
        "__covrec_" + FuncName
      );

      CovFunVar->setSection("__llvm_covfun");
      CovFunVar->setAlignment(Align(8));
      CovFunVar->setVisibility(GlobalValue::HiddenVisibility);

      covfun_count++;
    }
  }


  // Step 4: Reference the profiler runtime to ensure it gets linked
  // This is equivalent to what Clang does with -fprofile-instr-generate
  FunctionType *VoidFnTy = FunctionType::get(Type::getVoidTy(Ctx), false);
  FunctionCallee ProfileRuntimeInit = Mod->getOrInsertFunction("__llvm_profile_runtime", VoidFnTy);

  if (Function *RuntimeFn = dyn_cast<Function>(ProfileRuntimeInit.getCallee())) {
    // Create a dummy reference to ensure the runtime gets linked
    GlobalVariable *RuntimeRef = new GlobalVariable(
      *Mod,
      RuntimeFn->getType(),
      false,
      GlobalValue::LinkOnceODRLinkage,
      RuntimeFn,
      "__llvm_profile_runtime_user"
    );
    RuntimeRef->setVisibility(GlobalValue::HiddenVisibility);
  }
}

// Run optimization passes with optional coverage instrumentation
LLVMErrorRef LLVMExtRunPassesWithCoverage(LLVMModuleRef M,
                                           const char *Passes,
                                           LLVMTargetMachineRef TM,
                                           LLVMPassBuilderOptionsRef Options,
                                           LLVMBool EnableCoverage,
                                           const char *SourceFile) {
  Module *Mod = unwrap(M);
  TargetMachine *Machine = reinterpret_cast<TargetMachine *>(TM);

  PassBuilder PB(Machine);

  // Setup analysis managers
  LoopAnalysisManager LAM;
  FunctionAnalysisManager FAM;
  CGSCCAnalysisManager CGAM;
  ModuleAnalysisManager MAM;

  PB.registerModuleAnalyses(MAM);
  PB.registerCGSCCAnalyses(CGAM);
  PB.registerFunctionAnalyses(FAM);
  PB.registerLoopAnalyses(LAM);
  PB.crossRegisterProxies(LAM, FAM, CGAM, MAM);

  // Create module pass manager
  ModulePassManager MPM;

  // Add InstrProfiling lowering pass if coverage is enabled
  if (EnableCoverage) {
    // Add InstrProfiling lowering pass to convert intrinsics to actual code
    InstrProfOptions ProfileOptions;
    ProfileOptions.Atomic = true; // Use atomic counters for thread safety
    MPM.addPass(InstrProfilingLoweringPass(ProfileOptions, false));
  }

  // Parse and add the optimization pipeline after instrumentation lowering
  if (auto Err = PB.parsePassPipeline(MPM, Passes)) {
    return wrap(std::move(Err));
  }

  MPM.run(*Mod, MAM);

  // Generate coverage mapping metadata AFTER InstrProfilingLoweringPass
  if (EnableCoverage) {
    LLVMExtGenerateCoverageMapping(M, SourceFile);
  }

  return nullptr;
}

} // extern "C"
