# Annotation Base Type Implementation Notes

## Goal
Implement GitHub issue #12655 - expose a base `Annotation` type in Crystal that:
- Serves as the metaclass for all annotation types (`Foo.class` returns `Annotation`)
- Is a metaclass of itself (`Annotation.class` returns `Annotation`)
- Can be used in generic types like `Hash(Annotation.class, Int32)`
- Supports `{{ Annotation.subclasses }}` macro method

## Current Implementation Status

### Completed
1. **Created `AnnotationBaseType`** in `src/compiler/crystal/types.cr` (~line 2915)
   - Extends `NonGenericClassType` with `Value` as superclass
   - `metaclass` returns `self` (metaclass of itself)
   - Tracks annotation metaclasses via `@annotation_metaclasses` array
   - Implements `each_concrete_type` for polymorphic dispatch

2. **Created `AnnotationMetaclassType`** in `src/compiler/crystal/types.cr` (~line 2897)
   - Each annotation gets its own metaclass (like `Foo.class`)
   - Has `Annotation` as superclass
   - Registers itself with `AnnotationBaseType` on creation
   - Each instance has a unique type ID for hash key discrimination

3. **Modified `AnnotationType`** in `src/compiler/crystal/types.cr` (~line 2881)
   - `metaclass` now returns a new `AnnotationMetaclassType` instance (cached)

4. **Created `Annotation` type in program** in `src/compiler/crystal/program.cr` (~line 228)
   ```crystal
   types["Annotation"] = @annotation = AnnotationBaseType.new self, self, "Annotation", value
   ```

5. **Codegen support added in multiple files:**
   - `src/compiler/crystal/codegen/llvm_id.cr` - ID assignment for annotation types
   - `src/compiler/crystal/codegen/llvm_typer.cr` - LLVM type (int32) for both types
   - `src/compiler/crystal/codegen/cast.cr` - `assign_distinct` and `upcast_distinct` handlers
   - `src/compiler/crystal/codegen/debug.cr` - Added to debug type sinkhole
   - `src/compiler/crystal/codegen/types.cr` - `passed_as_self?` and `passed_by_value?`
   - `src/compiler/crystal/codegen/primitives.cr` - `crystal_type_id` primitive
   - `src/compiler/crystal/codegen/type_id.cr` - `type_id_impl` for AnnotationBaseType
   - `src/compiler/crystal/semantic/type_to_restriction.cr` - Added to nil-returning convert

### Working Features
- `Foo.class` returns `Annotation` (verified with `typeof`)
- `Annotation.class` returns `Annotation`
- `Foo == Bar` returns `false` (different annotations are distinguishable)
- `Foo.crystal_type_id` and `Bar.crystal_type_id` return different values
- `Hash(Annotation.class, Int32)` works with annotation types as keys
- Hash lookup correctly finds different annotation keys

### Test Status
Tests are in `spec/compiler/semantic/annotation_spec.cr` (lines 1277-1347)

**Passing:**
- `types Annotation`
- `types Annotation.class as Annotation`
- `types user annotation .class as Annotation` (after adding `inject_primitives: true`)
- `types builtin annotation .class as Annotation`

**Failing (need investigation):**
- `allows Annotation.class as generic type argument` - needs correct expected type
- `Annotation.subclasses includes user-defined annotations` - macro subclasses issue
- `Annotation.subclasses includes built-in annotations` - macro subclasses issue
- `Annotation.all_subclasses works` - macro subclasses issue

## Key Technical Details

### Type Hierarchy
```
AnnotationType (e.g., Foo) - the annotation definition itself
  └── metaclass -> AnnotationMetaclassType (e.g., Foo.class)
                     └── superclass -> AnnotationBaseType (Annotation)
                     └── metaclass -> AnnotationBaseType (Annotation)

AnnotationBaseType (Annotation)
  └── metaclass -> self (metaclass of itself)
  └── @annotation_metaclasses -> [Foo.class, Bar.class, ...]
```

### LLVM Representation
- Both `AnnotationBaseType` and `AnnotationMetaclassType` are represented as `int32` (type ID)
- Each `AnnotationMetaclassType` gets a unique type ID via `assign_id_impl`
- `AnnotationBaseType` uses `assign_id_from_subtypes` with `annotation_metaclasses`

### Key Methods
- `AnnotationMetaclassType#metaclass` returns `program.annotation_type`
- `AnnotationBaseType#metaclass` returns `self`
- `AnnotationBaseType#each_concrete_type` yields all annotation metaclasses
- `type_id_impl(value, type : AnnotationBaseType)` returns `value` directly (like VirtualMetaclassType)

### Codegen Settings
- `passed_as_self?`: `AnnotationMetaclassType` = false, `AnnotationBaseType` = true (needs runtime value)
- `passed_by_value?`: Both = false (represented as int32, not struct)

## Remaining Work

1. **Fix `Annotation.subclasses` macro** - The macro system needs to see annotation types as subclasses of `Annotation`. This likely requires:
   - Checking how `subclasses` macro method works
   - May need to implement `subclasses` on `AnnotationBaseType`
   - Or register annotations differently so the macro system finds them

2. **Verify all codegen tests pass** - Run full compiler test suite

3. **Create `src/annotation.cr`** - Standard library file defining `struct Annotation` (may already exist from previous work)

## Files Modified
- `src/compiler/crystal/program.cr`
- `src/compiler/crystal/types.cr`
- `src/compiler/crystal/codegen/llvm_id.cr`
- `src/compiler/crystal/codegen/llvm_typer.cr`
- `src/compiler/crystal/codegen/cast.cr`
- `src/compiler/crystal/codegen/debug.cr`
- `src/compiler/crystal/codegen/types.cr`
- `src/compiler/crystal/codegen/primitives.cr`
- `src/compiler/crystal/codegen/type_id.cr`
- `src/compiler/crystal/semantic/type_to_restriction.cr`
- `spec/compiler/semantic/annotation_spec.cr`

## Test Commands
```bash
# Build compiler
crystal clear_cache && make clean llvm_ext all

# Run annotation tests
./bin/crystal spec spec/compiler/semantic/annotation_spec.cr

# Test runtime behavior
./bin/crystal run /tmp/test_annotation.cr

# Test hash functionality
./bin/crystal eval 'annotation Foo; end; annotation Bar; end; h = {} of Annotation.class => Int32; h[Foo] = 1; h[Bar] = 2; puts h[Foo], h[Bar]'
```
