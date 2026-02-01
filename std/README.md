# Hax Standard Library (v0.1)

The `std/` tree is a **normative** part of the Hax v0.1 definition.

If the written specification and `std/` disagree, `std/` is treated as the source of truth for behavior.

## Layering

The standard library is structured in two layers:

* `std::sys::*` — the **intrinsic boundary**
  * Minimal surface that maps to compiler/runtime-provided intrinsics.
  * Documented normatively (and kept small).

* `std::*` — the **user-facing** API
  * Pure Hax code wrapping `std::sys::*`.
  * Intended to keep user code stable even when the intrinsic boundary evolves.

## I/O (current surface)

### `std::io`

`std::io` is a thin wrapper over `std::sys::IO`.

* `print(Str) -> Void`
* `eprint(Str) -> Void`
* `read_file(Str) -> Result<Str, IoError>`
* `write_file(Str, Str) -> Result<Int, IoError>`

### `std::sys::IO`

`std::sys::IO` defines the normative intrinsic-backed API:

* `write_stdout(Str) -> Void`
* `write_stderr(Str) -> Void`
* `read_file(Str) -> Result<Str, IoError>`
* `write_file(Str, Str) -> Result<Int, IoError>`

## Not present in v0.1

The standard library does not expose `open()`-style streaming file handles in v0.1.
