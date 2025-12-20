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
   - Added `check_macro_method_outside_expansion` helper for proper error messages

4. `src/compiler/crystal/semantic/cleanup_transformer.cr`
   - Added `transform(node : Macro)` override at line ~135
   - Skips body transformation for macro methods (body contains macro expressions not valid as regular Crystal)

5. `src/compiler/crystal/macros/methods.cr`
   - `interpret_user_macro_method?` at line ~95 - entry point for user macro method calls
   - `lookup_macro_method` at line ~111 - searches scope chain
   - `find_macro_method_in_type` at line ~126 - checks if macro is a macro_method
   - `execute_macro_method` at line ~137 - validates types, creates sub-interpreter, executes body
   - `execute_type_macro_method?` at line ~2295 (in TypeNode#interpret) - handles type-scoped calls

6. `src/compiler/crystal/semantic/restrictions.cr`
   - Modified `Macro#overrides?` to allow macro/macro def coexistence

7. `src/compiler/crystal/syntax/to_s.cr`
   - Updated `visit(node : Macro)` for macro def output

8. `src/compiler/crystal/tools/formatter.cr`
   - Updated `visit(node : Macro)` for macro def formatting

9. `spec/compiler/codegen/macro_spec.cr`
   - Tests at line ~1893-2120

10. `spec/compiler/parser/to_s_spec.cr`
    - Tests for macro def to_s

11. `spec/compiler/formatter/formatter_spec.cr`
    - Tests for macro def formatting

### Type Validation

Parameter and return type validation uses `validate_macro_method_type` in `methods.cr`, which leverages:
- `@program.lookup_macro_type(restriction)` - converts restriction AST to `MacroType`
- `value.macro_is_a?(macro_type)` - checks if value matches the type (with inheritance)

Supported types: All AST node types (`ArrayLiteral`, `StringLiteral`, `NumberLiteral`, etc.), `ASTNode` (matches any)

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
6. **Visibility**: `private macro def` supported - errors when called with explicit receiver
7. **Coexistence**: `macro foo` and `macro def foo` can coexist in the same type

### Visibility (private macro def)

Private macro methods error when called with an explicit receiver:

```crystal
class Foo
  private macro def helper(x : StringLiteral) : StringLiteral
    x.upcase
  end

  macro generate
    {{ helper("hello") }}      # OK - no receiver
  end
end

{{ Foo.helper("hello") }}      # Error: private macro 'helper' called for Foo
```

Implementation in `src/compiler/crystal/macros/methods.cr`:
- `execute_type_macro_method?` checks `macro_method.visibility.private?` before execution

### Coexistence with Regular Macros

A type can have both `macro foo` and `macro def foo`. They're called in different contexts:

```crystal
class Foo
  macro foo
    "from regular macro"
  end

  macro def foo : StringLiteral
    "from macro method"
  end
end

Foo.foo              # Calls regular macro (outside {{ }})
{{ Foo.foo }}        # Calls macro method (inside {{ }})
```

Implementation:
- `src/compiler/crystal/semantic/restrictions.cr`: `Macro#overrides?` returns false when comparing macro method with regular macro
- `src/compiler/crystal/types.cr`: `lookup_macro` skips macro methods
- `src/compiler/crystal/macros/methods.cr`: `find_macro_method_in_type` searches for macro methods only

### to_s and Formatter Support

Both `to_s.cr` and `formatter.cr` handle macro methods:
- Write `macro def` instead of `macro`
- Handle return type (`: Type`)
- Format body as regular Crystal expressions (not macro body syntax)

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
