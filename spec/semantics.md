# Hax Semantics (v0.1)

This document captures semantic rules that are not fully expressible in the EBNF grammar.

## Guiding principles

- **Native compilation friendly:** predictable control-flow and data representation.
- **Explicitness over magic:** no implicit truthiness, no implicit list/scalar context, no implicit coercions.
- **Aliasing is explicit:** by default values are passed/copied by value; mutation across boundaries uses explicit references.

## Modules and qualification

- Each file defines exactly one module via `module Name::Here;`.
- **Module identity is declared, not path-derived.** The compiler may enforce a *path-consistency check* (error or warning) but the `module` declaration is authoritative.
- `::` is the only namespace/type qualification operator.
- `.` is reserved for instance field/method access.

## Imports

Supported forms:

- `import A::B;`
- `import A::B as B;`
- `from A::B import X, Y;`

Rules:

- Imports are compile-time only and do **not** execute code.
- No wildcard imports in v0.1.
- Selective imports (`from ... import ...`) introduce unqualified names. Collisions are compile-time errors.

Unqualified name lookup order:

1. Local variables / parameters
2. Local declarations in the current module
3. Names introduced by `from ... import ...`
4. Otherwise: compile-time error (must qualify or import)

## Types (core)

Builtin types:

- `Int`, `Num`, `Bool`, `Str`, `Void`

Composite types:

- Arrays: `[T]`
- Hashes: `{K:V}`
- Generic instantiations: `Type[A, B, ...]`

**Void:** `Void` is a type with no value. A `Void`-returning function produces no value and cannot be used where a value is required.


## `Never` type

`Never` is a builtin bottom type representing computations that **do not return**
to their caller.

### Meaning
- An expression of type `Never` never produces a runtime value.
- Evaluating a `Never` expression terminates control flow (e.g. by panicking or aborting).

Typical sources of `Never`:
- `panic(...)` (and other noreturn functions such as `...::panic(...)` or
  `...::abort(...)`)
- Future language features may add additional noreturn constructs.

### Subtyping rule (bottom type)
`Never` is a subtype of every type:

- `Never ≤ T` for all types `T`

This means a `Never` expression is permitted anywhere a value of type `T`
is required.

### Type compatibility
For v0.1, type checking is strict equality **except** for `Never`:

- Values must normally match exactly: `T` is compatible with `T`
- Additionally: `Never` is compatible with any `T`

No other implicit conversions are performed.

### Control-flow effects
Any statement whose evaluation is of type `Never` is a *terminator* for the
current control-flow path:

- Code following a `Never` terminator in the same block is unreachable.
- A function with declared return type `T` is considered complete if every path
  either:
  - returns a `T`, or
  - terminates with a `Never` statement.

### `if` / `case` result typing with `Never`
When an `if` (or `case`) expression has branch result types:

- If both branches have the same type `T`, the expression type is `T`.
- If one branch is `Never` and the other is `T`, the expression type is `T`.
- Otherwise (two different non-`Never` types), it is a type error in v0.1.

### Short-circuit boolean operators and `Never`
Short-circuit semantics are preserved:

- `and` / `or` remain `Bool`-typed expressions.
- If the left operand evaluates to `Never`, the entire expression is `Never`.
- If only the right operand is `Never`, the result remains `Bool`
  (due to short-circuiting).


## Variables and scopes

- `var` declares a local variable (shorthand for `var(local)`).
- `var(static)` declares a persistent local whose storage lasts for the program lifetime but is scoped to the enclosing function/block.
- `var(global)` declares a module/global variable (only valid at top level).

No truthiness: `if`, `while`, `for` conditions must be `Bool`.

## Values, copying, and containers

- Scalars, structs, classes, arrays, and hashes have **by-value** semantics.
- Assigning one container to another yields an independent value (as-if deep copy).
- Implementations may optimize by value semantics using COW/moves, but this must not be observable.

### Hash literals

- Hash literals use `=>` as the key/value separator: `{ "a" => 1, "b" => 2 }`.

### Hash indexing

v0.1 proposal (library/typing rule):

- Reading `%h{"k"}` returns `Option[V]` to represent missing keys explicitly.
- Writing `%h{"k"} = v` inserts/overwrites.

(Exact surface may be implemented as a library wrapper or intrinsic; the semantic goal is explicit missing-key handling.)

## References: `^` variables and `addr()`

### `addr()`

- `addr()` may only take **named variables**: `addr($x)`, `addr(@a)`, `addr(%h)`.
- Taking addresses of elements (e.g. `addr(@a[0])`) is not allowed in v0.1.

### `^` variables

- A `^name` variable is a single-value slot that stores an address/reference to a named variable.
- `^name` **auto-dereferences** in expression and lvalue contexts.

### Binding vs write-through

- `:=` binds/rebinds the reference stored in a `^` variable.
- `=` assigns the *referent value* (write-through) when the LHS is a `^` variable.

Rules:

- **Local `^` variables:** initial binding must use `:=`, and rebinding with `:=` is allowed.
- **`^` parameters:** `:=` is forbidden (no exceptions).

Type inference:

- A local `^` variable may omit its referent type; its type is inferred from the first `:=` binding and then becomes fixed.

## Functions

- Defined with `sub name(params...) -> ReturnType { ... }`.
- If `-> ReturnType` is omitted, the return type is `Void`.
- **Return is mandatory** in all non-`Void` functions: every control-flow path must end with `return EXPR;`.
- `return;` is only valid in `Void` functions.
- **Functions do not return references** in v0.1 (no returning aliasing pointers). Use `^` output parameters instead.

### Call/argument semantics

- No list/scalar context; no implicit flattening.
- `$` scalar parameters are by value.
- `@`/`%` parameters are by value (container values).
- `^` parameters are by reference (aliasing) and require explicit types.
- Passing by reference requires `addr(...)` at the call site.

## Control flow

Control-flow forms are statements (not expressions) in v0.1:

- `if/elsif/else`
- `while`
- `for (init; cond; step)`
- `foreach (Type? $x in EXPR) { ... }` (only iteration-over-collection form)
- `case/when/else`
- `break`, `continue`, `return`

## Logical operators

- Use `and`, `or`, `not`.
- `and`/`or` short-circuit.
- Operands must be `Bool`.
- Symbolic `&&`, `||`, `!` do not exist in v0.1.

## Equality and comparisons

- No implicit coercions. Comparing different types is a compile-time error.
- `Num` equality follows IEEE-754: `NaN == NaN` is false.
- `Str` ordering (`<`, `<=`, `>`, `>=`) is **binary lexicographic** (byte-wise), locale-independent.
- Containers compare by value (`==` deep equality). Ordering comparisons are not defined for arrays/hashes/enums in v0.1.

## Enums and `case`

### Enums

- `enum` defines a closed set of variants; variants may be unit-like or carry payload fields.
- Enums are value types.

### `case` on enums: variant matching

When the `case` scrutinee has an enum type, `when` clauses match variants:

- `when Variant { ... }`
- `when Variant($x)` / `when Variant(Type $x)` binds payload fields.

### Exhaustiveness (locked)

- `case` over an enum must be **exhaustive**:
  - either list all variants, or include `else`.
- Duplicate variant clauses are errors.

### Constructor name resolution (locked)

Enum constructors may be used **unqualified** only when the compiler can determine a unique expected enum type at the use site. Otherwise constructors must be qualified:

- `Option::Some(1)`
- `Result::Err("msg")`

Inside `case (expr_enum)`, `when Variant ...` is resolved as a variant of the scrutinee enum type (not a function of the same name).

## OO shape (v1-compatible)

### Names and qualification

- Types live in module namespaces: `Module::Type`.
- `::` is for namespaces/types; `.` is for instance field/method access.

### `struct` vs `class`

- Both `struct` and `class` exist.
- Fields:
  - In `struct`, fields are **public by default**.
  - In `class`, fields are **private by default**.
  - `pub field` / `priv field` may override in either.

### Methods and lowering

- Instance method calls use `.`:
  - `$obj.m(a,b)`
- Field access uses `.` without parentheses:
  - `$obj.field`

Resolution:

- `$obj.name` is a field access
- `$obj.name()` is a method call

Lowering (static dispatch model):

- Non-mutating `method` lowers to `Type::m($obj, a, b)`.
- Mutating `mut method` lowers to `Type::m(addr($obj), a, b)`.

No overloading:

- No multiple methods with the same name within a type.
- No multiple functions with the same name in a module.

Associated functions:

- `sub` inside `struct/class` defines an associated function called as `Type::f(...)`.
- There is no `static` keyword; constructors are just conventional associated functions named `new`.

Mut receiver rule (locked):

- A `mut method` may only be called on an **addressable** receiver:
  - a named variable, or a `^` variable.
- Calling a `mut method` on a temporary is a compile-time error.

