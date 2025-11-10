# Code Coverage Support in Crystal

This document describes the LLVM-based source code coverage implementation in the Crystal compiler and how to use it.

## Overview

Crystal now supports source-based code coverage using LLVM's instrumentation profiling infrastructure. This provides accurate line-by-line and function-level coverage data that integrates with standard LLVM coverage tools (`llvm-cov`, `llvm-profdata`).

## Usage

### Basic Usage

1. **Compile with coverage instrumentation:**
   ```bash
   crystal build --coverage your_program.cr
   ```

2. **Run your program:**
   ```bash
   ./your_program
   ```
   This generates a `default.profraw` file containing raw runtime coverage data.

3. **Convert profraw to indexed format:**
   ```bash
   llvm-profdata merge -sparse default.profraw -o default.profdata
   ```
   This step is **always required** - `llvm-cov` needs the indexed `.profdata` format.

   To merge multiple runs into a single report:
   ```bash
   llvm-profdata merge -sparse run1.profraw run2.profraw -o merged.profdata
   ```

4. **Generate coverage reports:**
   ```bash
   # Summary report
   llvm-cov report your_program -instr-profile=default.profdata

   # Detailed source view
   llvm-cov show your_program -instr-profile=default.profdata path/to/source.cr
   ```

### Advanced Usage

#### HTML Coverage Report
```bash
llvm-cov show your_program -instr-profile=default.profdata \
  -format=html -output-dir=coverage_html
```

#### Line-by-Line Coverage
```bash
llvm-cov show your_program -instr-profile=default.profdata \
  path/to/source.cr -show-line-counts-or-regions
```

#### Export to LCOV Format
```bash
llvm-cov export your_program -instr-profile=default.profdata \
  -format=lcov > coverage.lcov
```

## Implementation Details

### Architecture

The implementation consists of four main components:

1. **Instrumentation** - Inserts coverage counters into LLVM IR
2. **Lowering Pass** - Converts intrinsics to actual counter increments
3. **Coverage Mapping** - Generates metadata mapping counters to source locations
4. **Runtime Library** - Writes profiling data at program exit

### Component Details

#### 1. Instrumentation (`src/llvm/coverage.cr`)

The `LLVM::Coverage` module provides Crystal-level APIs for inserting coverage instrumentation:

- `instrument_function(func)` - Adds coverage counters to a function
- Inserts `llvm.instrprof.increment` intrinsics at function entry points
- Creates profile name variables for each instrumented function
- Computes function hashes using DJB2 algorithm

**Key files:**
- `src/llvm/coverage.cr` - Crystal API
- `src/llvm/lib_llvm_ext.cr` - FFI bindings

#### 2. InstrProfiling Lowering Pass (`src/llvm/ext/llvm_ext.cc`)

The C++ extension integrates LLVM's `InstrProfilingLoweringPass`:

```cpp
InstrProfOptions ProfileOptions;
ProfileOptions.Atomic = true;  // Thread-safe counters
MPM.addPass(InstrProfilingLoweringPass(ProfileOptions, false));
```

This pass converts `llvm.instrprof.increment` intrinsics into:
- Counter arrays (`__profc_*` sections)
- Profile data structures (`__profd_*` sections)
- Atomic increment operations

**Key function:** `LLVMExtRunPassesWithCoverage()`

#### 3. Coverage Mapping Generation (`src/llvm/ext/llvm_ext.cc`)

After instrumentation lowering, `LLVMExtGenerateCoverageMapping()` creates:

**a) `__llvm_covmap` section:**
- Header: version (6), filenames length
- Compressed filename table (zlib)
- One per binary

**b) `__llvm_covfun` sections:**
- Function name hash (MD5)
- Function structural hash (matches instrumentation)
- Filenames hash (MD5 of compressed table)
- Coverage region data (ULEB128-encoded)
- One per instrumented function

**Key APIs used:**
- `coverage::CoverageFilenamesSectionWriter` - Compresses filenames
- `coverage::CoverageMappingWriter` - Encodes regions
- `coverage::CounterMappingRegion` - Defines source regions

**Format details:**
```
covmap: [unused:i32, filenames_len:i32, unused:i32, version:i32, compressed_filenames]
covfun: [name_md5:i64, data_len:i32, func_hash:i64, filenames_hash:i64, mapping_data:bytes]
```

#### 4. Runtime Library Linking

The compiler automatically links LLVM's profiler runtime:

```crystal
link_flags << "-lclang_rt.profile-x86_64"
link_flags << "-Wl,--whole-archive"  # Ensure runtime initialization
```

The runtime:
- Initializes counter arrays at startup
- Registers an `atexit()` handler
- Writes `default.profraw` on program exit

### Compiler Integration

#### Build Flow

1. **Parser/Codegen** - Normal compilation to LLVM IR
2. **Coverage Instrumentation** - Insert `llvm.instrprof.increment` intrinsics
   ```crystal
   if @code_coverage
     llvm_modules.each do |type_name, info|
       info.mod.functions.each do |func|
         LLVM::Coverage.instrument_function(func)
       end
     end
   end
   ```
3. **Optimization** - Run with custom pass pipeline
   ```crystal
   LibLLVMExt.run_passes_with_coverage(
     llvm_mod, pass_pipeline, target_machine,
     options, enable_coverage=1, source_filename
   )
   ```
4. **InstrProfiling Pass** - Lower intrinsics to counters
5. **Coverage Mapping** - Generate `__llvm_covmap` and `__llvm_covfun`
6. **Linking** - Link with profiler runtime

#### Key Files Modified

- `src/compiler/crystal/command.cr` - Added `--coverage` flag
- `src/compiler/crystal/compiler.cr` - Coverage orchestration
- `src/compiler/crystal/codegen/codegen.cr` - Link profiler runtime
- `src/llvm/coverage.cr` - Coverage instrumentation API
- `src/llvm/ext/llvm_ext.cc` - C++ pass integration
- `src/llvm/lib_llvm_ext.cr` - FFI bindings

### Technical Challenges Solved

#### 1. Coverage Format Version
- **Issue:** LLVM 21 uses coverage format version 6, but enum is named `Version7`
- **Solution:** Used numeric value 6, not enum ordinal

#### 2. Function Hash Matching
- **Issue:** Coverage mapping function hash must match instrumentation hash
- **Solution:** Use same DJB2 hash algorithm in both places:
  ```cpp
  uint64_t hash = 5381;
  for (size_t i = 0; i < Len; i++) {
    hash = ((hash << 5) + hash) + (unsigned char)FuncName[i];
  }
  ```

#### 3. Filename Compression
- **Issue:** LLVM expects compressed filenames in covmap
- **Solution:** Use `CoverageFilenamesSectionWriter` with compression enabled:
  ```cpp
  coverage::CoverageFilenamesSectionWriter writer(filenames);
  writer.write(os, /*Compress=*/true);
  ```

#### 4. Filenames Hash
- **Issue:** Covfun filenames hash must match covmap data
- **Solution:** Compute MD5 of compressed filename buffer:
  ```cpp
  MD5 hasher;
  hasher.update(ArrayRef<uint8_t>(FilenamesBuffer));
  uint64_t hash = hasher.final().low();
  ```

#### 5. Source File Mapping
- **Issue:** Coverage mapped to compilation unit names (_main) instead of source files
- **Solution:** Pass actual source filename through compilation pipeline:
  ```crystal
  @source_filename = program.filename || "unknown.cr"
  compiler.optimize(llvm_mod, target_machine, @source_filename)
  ```

#### 6. Region Encoding
- **Issue:** Manual ULEB128 encoding was error-prone
- **Solution:** Use LLVM's `CoverageMappingWriter` API:
  ```cpp
  coverage::CoverageMappingWriter writer(
    VirtualFileMapping, Expressions, Regions
  );
  writer.write(os);
  ```

## Profraw File Format

The `default.profraw` file uses LLVM's indexed instrumentation profile format:

```
[Header]
  Magic: 0xFF6C70726F667281
  Version: 8
  DataSize: size of counters
  PaddingBytesAfterCounters: 0
  NamesSize: size of function names
  CountersDelta: offset to counters
  NamesDelta: offset to names
  ValueDataDelta: 0

[Counters]
  Array of uint64_t counter values

[Function Names]
  Compressed function name strings
```

## Limitations

1. **Source location granularity:** Currently tracks function-level coverage with single region per function. Future work could add statement and branch coverage.

2. **Multi-file programs:** Coverage mapping currently uses primary source file for all instrumented functions. Multi-file support would require tracking source file per function.

3. **Generic instantiations:** Each generic instantiation gets its own coverage data. Reports show all instantiations.

4. **Optimization interaction:** Some optimizations may affect coverage accuracy (inlining, dead code elimination).

## Future Enhancements

- **Branch coverage:** Track conditional branch outcomes
- **Statement-level coverage:** Finer-grained region mapping
- **Integration with CI:** Generate coverage badges, track over time
- **Coverage-guided testing:** Skip tests if relevant code unchanged
- **Differential coverage:** Show coverage delta between versions

## Debugging

### Enable debug output (for development):
Add debug `errs()` statements in `src/llvm/ext/llvm_ext.cc` to inspect:
- Module IR before/after lowering
- Intrinsic counts
- Generated globals
- Coverage mapping metadata

Example debug code:
```cpp
// In LLVMExtRunPassesWithCoverage(), before MPM.run():
errs() << "[Coverage Debug] Found " << intrinsic_count << " intrinsics\n";

// After MPM.run():
for (auto &F : *Mod) {
  if (!F.isDeclaration()) {
    F.print(errs());
  }
}
```

### Common issues:

**"unsupported coverage format version"**
- Check LLVM version compatibility
- Verify `CovMapVersion = 6` is used

**"no filename found for function"**
- Filenames hash mismatch between covmap and covfun
- Ensure same compressed buffer is hashed

**"malformed coverage data: ULEB128 too big"**
- Region encoding error
- Use `CoverageMappingWriter` API, not manual encoding

**No profraw file generated**
- Profiler runtime not linked
- Check for `libclang_rt.profile-x86_64.a` in link command
- Ensure `--whole-archive` flag is used

## References

- [LLVM Code Coverage Mapping Format](https://llvm.org/docs/CoverageMappingFormat.html)
- [LLVM Profile Runtime](https://clang.llvm.org/docs/SourceBasedCodeCoverage.html)
- [InstrProfiling Pass Documentation](https://llvm.org/docs/Passes.html#instrprofiling)
- [LLVM Coverage Tools](https://llvm.org/docs/CommandGuide/llvm-cov.html)

## Contributing

When modifying coverage implementation:

1. Test with simple programs first
2. Verify with `llvm-profdata show` that profraw is valid
3. Check covmap/covfun sections with `objdump -s`
4. Compare output with Clang-generated coverage
5. Test with `llvm-cov report` and `llvm-cov show`

## License

This implementation follows Crystal's Apache 2.0 license and uses LLVM's instrumentation profiling APIs.
