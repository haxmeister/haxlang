# Hax

Hax is a compiled programming language with a Perl-flavored surface syntax, designed for native compilation with explicit, predictable semantics.

This repository currently contains the language specification (grammar + semantics) and a few example programs.

## Repository layout

- `spec/` — language specification (grammar, lexer, semantics)
- `examples/` — small Hax examples
- `tools/` — tooling (reserved for compiler/parser tools)

## Normative Standard Library

The `std/` directory is a normative part of the Hax language definition.

- If the written specification and the standard library disagree, the standard library is the source of truth.
- Language changes are not considered complete until `std/` has been updated to reflect them.
- The goal is that all non-primitive functionality lives in `std/` as Hax code, with a small, explicit set of compiler/runtime intrinsics.

### Intrinsics

Any symbol beginning with `__` is an intrinsic provided by the compiler/runtime.
Intrinsics are intentionally few and must be documented in the spec whenever added or changed.

### Standard library is normative

Hax defines its semantics through real Hax code in `std/`.
If the spec and `std/` disagree, `std/` wins.


## Status

Spec is evolving; see `spec/changelog.md`.
