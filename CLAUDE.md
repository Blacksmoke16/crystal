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

### AST Design

Macro methods use a dedicated `MacroDef` AST type that inherits from `MacroBase`:

```crystal
abstract class MacroBase < ASTNode
  # Shared properties: name, args, body, double_splat, block_arg,
  #                    name_location, splat_index, doc, visibility
end

class Macro < MacroBase
  # Regular macros - body contains MacroLiteral/MacroExpression
end

class MacroDef < MacroBase
  property return_type : ASTNode?
  # Macro methods - body contains pure Crystal expressions
end
```

### Key Implementation Details

**Files modified:**

1. `src/compiler/crystal/syntax/ast.cr`
   - `MacroBase` abstract class with shared properties
   - `Macro` for regular macros
   - `MacroDef` for macro methods with `return_type` property

2. `src/compiler/crystal/syntax/parser.cr`
   - `parse_macro_method` returns `MacroDef` (not `Macro` with flag)
   - Parses with type restrictions enabled
   - Body parsed as regular expressions

3. `src/compiler/crystal/types.cr`
   - `macros` hash stores `Array(MacroBase)` (both Macro and MacroDef)
   - `lookup_macro` filters to only return `Macro` instances

4. `src/compiler/crystal/semantic/semantic_visitor.cr`
   - `nesting_exp?` includes `MacroDef` in non-nesting list
   - `check_macro_def_outside_expansion` for error messages

5. `src/compiler/crystal/semantic/cleanup_transformer.cr`
   - `transform(node : MacroDef)` skips body transformation

6. `src/compiler/crystal/macros/methods.cr`
   - `find_macro_methods_in_type` returns `Array(MacroDef)`
   - `execute_macro_method` takes `MacroDef` parameter

7. `src/compiler/crystal/semantic/restrictions.cr`
   - `MacroBase#overrides?` compares `self.class != other.class`

8. `src/compiler/crystal/syntax/to_s.cr`
   - Separate `visit(node : Macro)` and `visit(node : MacroDef)` handlers

9. `src/compiler/crystal/tools/formatter.cr`
   - Separate `visit(node : Macro)` and `visit(node : MacroDef)` handlers

10. `src/compiler/crystal/tools/doc/type.cr`
    - `macro_methods` selects `MacroDef` instances

11. Visitors/Transformers with `MacroDef` handlers:
    - `codegen/codegen.cr`, `semantic/top_level_visitor.cr`
    - `semantic/normalizer.cr`, `semantic/fix_missing_types.cr`
    - `syntax/transformer.cr`, `tools/print_types_visitor.cr`
    - `tools/playground/agent_instrumentor_transformer.cr`, `interpreter/compiler.cr`

12. `spec/compiler/codegen/macro_spec.cr`
    - Tests at line ~1893-2330

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
            │     ├─ Check @scope for MacroDef instances
            │     └─ Check @program for MacroDef instances
            └─ execute_macro_method(macro_def, node, args, named_args)
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
5. **Splat parameters**: `*args` gathers positional arguments into a `TupleLiteral`
6. **Double splat parameters**: `**kwargs` gathers named arguments into a `NamedTupleLiteral`
7. **Blocks**: Supported via `&block` parameter; use `yield` or access `block.body`
8. **Visibility**: `private macro def` supported - errors when called with explicit receiver
9. **Coexistence**: `macro foo` and `macro def foo` can coexist in the same type

### Limitations

- **Splat type restrictions**: Type restrictions on `*args` and `**kwargs` are not validated. In Crystal, these restrictions validate each element within the collection, not the collection itself. We skip this validation since we're doing lightweight type checking.

### Block Support

Macro methods support blocks via `&block` parameter:

```crystal
macro def with_wrapper(&block)
  "before " + {{ yield }} + " after"
end

macro def inspect_block(&block)
  {{ block.body }}
end

# Usage
{{ with_wrapper { "content" } }}      # => "before content after"
{{ inspect_block { 1 + 2 } }}         # => 1 + 2 (the AST)
```

Implementation: `execute_macro_method` binds block to `body_vars` and passes it to sub-interpreter for `yield` support.

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
- `src/compiler/crystal/semantic/restrictions.cr`: `MacroBase#overrides?` returns false when comparing different subclasses
- `src/compiler/crystal/types.cr`: `lookup_macro` filters to only return `Macro` instances
- `src/compiler/crystal/macros/methods.cr`: `find_macro_methods_in_type` selects only `MacroDef` instances

### to_s and Formatter Support

Both `to_s.cr` and `formatter.cr` handle macro methods:
- Write `macro def` instead of `macro`
- Handle return type (`: Type`)
- Format body as regular Crystal expressions (not macro body syntax)

### Control Expressions

Macro methods work in `{% %}` control expressions as well as `{{ }}` output expressions:

```crystal
macro def double(x : NumberLiteral) : NumberLiteral
  x * 2
end

{% for i in [1, 2, 3] %}
  {% pp double(i) %}  # Works in control context
{% end %}

{{ double(5) }}       # Works in output context
```

### API Documentation

Generated API docs display macro methods in their own section ("Macro Method Summary" / "Macro Method Detail"), separate from regular macros. Implementation in:
- `src/compiler/crystal/tools/doc/type.cr` - `macro_methods` method
- `src/compiler/crystal/tools/doc/templates.cr` - `MacrosInheritedTemplate` with `label` parameter
- `src/compiler/crystal/tools/doc/html/type.html` - template for rendering sections

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
