# Core IR (v0.1 internal)

## Status

Core IR is an **internal compiler representation** used after successful parsing,
import resolution, and type checking. It is **not** a user-facing language and is
not part of the v0.1 surface syntax contract.

Core IR exists to make control flow and evaluation order explicit and to provide
an input to later compilation stages.

## Goals

Core IR:

- Represents only **well-typed, well-scoped** programs.
- Makes **control flow explicit** using basic blocks and terminators.
- Preserves source-level semantics relevant to control flow, including:
  - exhaustive `case` totality,
  - `Never` as bottom type,
  - must-return properties.
- Is simple to validate mechanically.

## Non-goals

Core IR:

- Does not encode surface syntax.
- Does not promise a stable external serialization.
- Does not perform optimization.
- Does not define runtime ABI details beyond naming intrinsics at call sites.

---

## 1. Core concepts

A Core IR module contains **sub** definitions. A sub contains **basic blocks**.
Blocks contain a list of **instructions** followed by exactly one **terminator**.

Core IR uses the same canonical types as the checked AST, including `Void`, the
integer family, `Bool`, `Str`, enum types, and `Never`.

### 1.1 Never

`Never` is the bottom type. It has no values.

In Core IR:

- Any instruction that produces `Never` is treated as non-returning.
- Any control-flow edge representing a path that cannot continue normally ends
  in `unreachable`.

---

## 2. Sub form

A Core IR sub is defined by:

- a name (compiler-internal resolved path)
- a signature `(p0: T0, p1: T1, ...) -> R`
- an entry block label
- a set of blocks

### 2.1 Returns

A sub is structurally valid iff every reachable control-flow path from entry:

- reaches `return`, or
- reaches `unreachable`.

If the checked AST must-return analysis succeeded for a sub, then the lowered
Core IR must satisfy the same property.

---

## 3. Basic blocks

A block has:

- a label
- an ordered parameter list (possibly empty)
- a list of instructions
- exactly one terminator

Values flow between blocks via block parameters.

---

## 4. Terminators

Terminators end a block and transfer control.

### 4.1 `return <value>`

Ends the sub and returns a value whose type matches the sub return type.

For `Void`, the returned value is the `Void` value `()` (or an equivalent
internal unit token).

### 4.2 `br <label>(args...)`

Unconditional branch to another block.

- The argument list must match the target block parameter list in arity and type.

### 4.3 `condbr <cond> then:<L1>(args...) else:<L2>(args...)`

Conditional branch.

- `cond` has type `Bool`.
- Each target argument list must match its target block parameter list.

### 4.4 `switch_enum <scrutinee> { Variant(args...) -> <L>(args...) ... }`

Switch on an enum scrutinee.

- `scrutinee` has some enum type `E`.
- Each arm pattern is a variant constructor of `E`.
- Variant payload values are introduced either by:
  - arm block parameters, or
  - explicit destructuring instructions within the arm block.

**Exhaustiveness**

- A `switch_enum` produced from an exhaustive checked `case` is exhaustive.
- Exhaustive `switch_enum` has no default/fallthrough.

If the source `case` is non-exhaustive, Core IR must represent the missing path
explicitly as an edge to `unreachable` (or a compiler-defined trap intrinsic).

### 4.5 `unreachable`

Indicates normal control flow cannot proceed.

This corresponds to:

- an expression of type `Never`,
- a statically impossible path,
- or an explicit missing-case edge.

---

## 5. Instructions

Instructions compute values and do not transfer control.

Each instruction produces zero or one result value.

This spec defines the minimal instruction families required for v0.1 lowering.
A compiler may introduce additional instructions if they are type-correct and
validated.

### 5.1 Constants

- `const_int <lit> : <inttype>`
- `const_bool <true|false> : Bool`
- `const_str <literal> : Str`
- `const_void : Void`

### 5.2 Calls

- `call <callee>(args...) : R`

`callee` is a fully resolved symbol (a sub or intrinsic-backed symbol).

If `R` is `Never`, then the containing block must terminate with `unreachable`.

### 5.3 Integer casts

Explicit integer casts lower as:

- `int_cast <to_type>(value) : <to_type>`

### 5.4 Enum construction and destructuring

For enums:

- `enum_make <E::Variant>(args...) : E`

Variant payload extraction may be represented either as:

- block parameters on the variant arm, or
- explicit destructuring instructions.

The representation must make dataflow explicit.

---

## 6. Lowering from checked AST

Lowering consumes a **checked, resolved AST**.

Lowering must preserve:

- evaluation order,
- side effects,
- control-flow totality,
- type correctness.

### 6.1 `case` lowering

A checked AST `case` lowers to `switch_enum`.

- Exhaustive `case` becomes exhaustive `switch_enum`.
- Non-exhaustive `case` includes an explicit missing edge to `unreachable`.

### 6.2 `Never` lowering

An expression of type `Never` lowers such that normal continuation is
impossible. Typical representation:

- `call panic(...) : Never`
- `unreachable`

Lowering may drop subsequent instructions as unreachable.

### 6.3 Implicit returns

If a checked AST sub returns `Void` and ends without an explicit return,
lowering emits `return ()`.

---

## 7. Validation rules

A Core IR sub is valid iff:

1. Every block has exactly one terminator.
2. Every branch target exists.
3. Branch argument lists match target parameter lists in arity and type.
4. Every used value is defined and type-correct.
5. `return` value type matches the sub return type.
6. For `switch_enum`:
   - arm variants belong to the scrutinee enum type,
   - no duplicate variants occur,
   - non-exhaustive lowering includes an explicit missing-to-unreachable edge.
7. No reachable path falls off the end of a block.

---

## 8. Dumping Core IR

A compiler may provide a debugging command (e.g. `haxc lower`) that prints Core
IR.

The dump format is **implementation-defined** and not a stable interface. It must
include at least:

- sub name + signature
- block labels + parameters
- instructions with result types
- terminators with explicit successors
