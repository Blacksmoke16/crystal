# Crystal Compiler Development Notes

## Macro Methods Implementation (Issue #8835)

User-defined macro methods (`macro def`) allow reusable logic within macros, reducing code duplication in macro-heavy codebases.

### Syntax

```crystal
# Top-level macro method
macro def format_name(name : StringLiteral) : StringLiteral
  name.underscore.upcase
end

# Type-scoped macro method
class Foo
  macro def helper(items : ArrayLiteral) : ArrayLiteral
    items.map { |x| x.stringify }
  end
end

# Usage inside macro context
macro generate
  {{ format_name("HelloWorld") }}      # top-level
  {{ Foo.helper([1, 2, 3]) }}          # type-scoped
end
```

### Key Implementation Details

**Files modified:**

1. `src/compiler/crystal/syntax/ast.cr`
   - Added `return_type : ASTNode?` and `macro_method? : Bool` to `Macro` class

2. `src/compiler/crystal/syntax/parser.cr`
   - Added `parse_macro_method` at line ~3253
   - Detects `macro def` and parses with type restrictions enabled
   - Body parsed as regular expressions (not macro body syntax)

3. `src/compiler/crystal/semantic/semantic_visitor.cr`
   - Added check at line ~311-316 to error when macro method called outside `{{ }}`

4. `src/compiler/crystal/semantic/cleanup_transformer.cr`
   - Added `transform(node : Macro)` override at line ~135
   - Skips body transformation for macro methods (body contains macro expressions not valid as regular Crystal)

5. `src/compiler/crystal/macros/methods.cr`
   - `interpret_user_macro_method?` at line ~95 - entry point for user macro method calls
   - `lookup_macro_method` at line ~111 - searches scope chain
   - `find_macro_method_in_type` at line ~126 - checks if macro is a macro_method
   - `execute_macro_method` at line ~137 - validates types, creates sub-interpreter, executes body
   - `execute_type_macro_method?` at line ~2295 (in TypeNode#interpret) - handles type-scoped calls

6. `spec/compiler/codegen/macro_spec.cr`
   - Tests at line ~1893-2055

### Type Validation

Parameter and return type validation uses these methods in `methods.cr`:
- `validate_macro_method_arg_type` - checks args match restrictions
- `validate_macro_method_return_type` - checks return value
- `macro_type_names_from_restriction` - extracts type names from AST
- `macro_type_matches?` - compares actual vs expected types

Supported types: `ArrayLiteral`, `StringLiteral`, `NumberLiteral`, `SymbolLiteral`, `BoolLiteral`, `HashLiteral`, `NamedTupleLiteral`, `TupleLiteral`, `RangeLiteral`, `RegexLiteral`, `MacroId`, `TypeNode`, `NilLiteral`, `ProcLiteral`, `ASTNode` (matches any)

Union types supported: `x : StringLiteral | SymbolLiteral`

### Execution Flow

```
Inside macro {{ ... }}:
  MacroInterpreter.visit(Call)
    └─ No receiver? → interpret_top_level_call(node)
        ├─ Built-in? (env, flag?, puts, etc.) → handle directly
        └─ Not built-in? → interpret_user_macro_method?(node)
            ├─ lookup_macro_method(name, args, named_args)
            │     ├─ Check @scope for macro with macro_method?=true
            │     └─ Check @program for macro with macro_method?=true
            └─ execute_macro_method(macro, node, args, named_args)
                  ├─ Validate argument types
                  ├─ Create MacroInterpreter with param bindings
                  ├─ Execute body
                  ├─ Validate return type
                  └─ Return result ASTNode
```

### Key Design Decisions

1. **Body semantics**: Pure macro code - no `{{ }}` needed inside body
2. **Recursion**: Supported - macro methods can call other macro methods
3. **Default values**: Supported on parameters
4. **Untyped parameters**: Accept any ASTNode
5. **Blocks**: Not supported (can add later)

### Testing

```bash
# Run macro def tests
./bin/crystal spec spec/compiler/codegen/macro_spec.cr -e "macro def"

# Run all macro tests
./bin/crystal spec spec/compiler/codegen/macro_spec.cr

# Manual test
./bin/crystal eval '
macro def array_size(arr : ArrayLiteral) : NumberLiteral
  arr.size
end

macro test
  {{ array_size([1, 2, 3]) }}
end

puts test
'
```

### Build Commands

```bash
# Rebuild compiler after changes
make clean all
```
