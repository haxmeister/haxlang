# Hax Language Semantics

This document describes the semantic rules of the Hax programming language.
Unless otherwise stated, Hax v0.1 uses strict typing with no implicit
coercions or type inference.

---

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

Examples:
```hax
var int32 $x = panic("nope");
return panic("nope");     -- in a function returning int32
f(panic("nope"));         -- as an argument to any function
```

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

Example:
```hax
fn f(x: int) -> int {
  if x >= 0 {
    return x;
  }
  panic("negative");
}
```

### `if` / `case` result typing with `Never`
When an `if` (or `case`) expression has branch result types:

- If both branches have the same type `T`, the expression type is `T`.
- If one branch is `Never` and the other is `T`, the expression type is `T`.
- Otherwise (two different non-`Never` types), it is a type error in v0.1.

Example:
```hax
var int $y = if cond { 123 } else { panic("no") };
```

### Short-circuit boolean operators and `Never`
Short-circuit semantics are preserved:

- `A and B`: `B` is evaluated only if `A` evaluates to `true`
- `A or B`: `B` is evaluated only if `A` evaluates to `false`

Typing remains `Bool`, but `Never` may appear as a subexpression:

- If `A` is `Never`, the whole expression is `Never`.
- If `B` is `Never`, the whole expression remains `Bool`.
