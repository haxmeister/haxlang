# Hax Standard Library (v0.1)

The `std/` directory is a **normative part of the Hax language definition**.

- If the written specification and the standard library disagree, `std/` is the source of truth.
- Language changes are not considered complete until `std/` has been updated to reflect them.

## Layering

The standard library is intentionally split into two layers:

### `std::*` — user-facing APIs

These are ordinary Hax modules intended for user code.

### `std::sys::*` — intrinsic boundary

`std::sys::*` modules define the small set of operations provided by the compiler/runtime.
These are the only places where intrinsic-backed functions live.

## v0.1 I/O

### `std::sys::IO`

Defines the intrinsic-backed I/O boundary used by higher-level modules.

### `std::io`

A thin wrapper over `std::sys::IO` providing:

- `print(Str) -> Void`
- `eprint(Str) -> Void`
- `read_file(Str) -> Result[Str, IoError]`
- `write_file(Str, Str) -> Result[Int, IoError]`

In v0.1, `print`/`eprint` intentionally ignore underlying write errors.

## Prelude

`std::prelude` exists and is intentionally small in v0.1. It is imported explicitly:

```hax
import std::prelude;
```