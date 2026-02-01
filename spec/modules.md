# Modules and Program Roots (v0.1)

This document defines how a Hax program chooses its root module and how
`import` and `from ... import ...` resolve modules on disk.

## Program root

A program is checked/compiled starting from a single *root source file path*.

* The root file is the compilation entry.
* The program entrypoint `main` (Rule B) is searched for in the module defined
  by the root file.
* The root file may omit a `module ...` declaration. In that case, the root
  file is treated as an anonymous root module and `main` must appear in that
  file.
* If the root file contains a `module Foo::Bar` declaration, the root module
  name is `Foo::Bar` and `main` must appear in that module (i.e. in that file).
* The root file path is still the starting point for module search (see
  **Import roots**).

## Module path mapping

A module path `A::B::C` maps to a relative file path `A/B/C.hax`.

## Import roots

When resolving an imported module path, the toolchain searches for the mapped
file in this order:

1. **Project roots** (in order):
   1. The directory containing the root file.
   2. Each directory provided via `-I <dir>` (in CLI order).
2. **Standard library root**:
   1. The directory provided via `--std <dir>`, or `std` by default.

The first match wins and becomes the resolved path.

## Errors

If no candidate file exists, resolution fails with an error that includes the
module path and the default mapped file name.
