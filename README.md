# Hax

Hax is a statically typed programming language with a Perl-flavored surface syntax, designed for native compilation with explicit, predictable semantics.

v0.1 is intentionally small and spec-driven:

- **Grammar is frozen for v0.1**
- **`spec/grammar.ebnf` is normative**
- No new syntax is planned for v0.1

## Repository layout

- `spec/` — language specification (grammar, lexer, semantics)
- `std/` — **normative** standard library implemented in Hax
- `examples/` — sample Hax programs (both library-mode and program-mode)
- `tools/` — tooling (parser/checker front-end, test harness)

## Tooling

The front-door developer tool is `haxc` (currently shipped from `tools/haxparse/bin`).

### Check a program (requires an entrypoint)

```bash
tools/haxparse/bin/haxc check path/to/main.hax
```

Program mode rules (v0.1):

- `main` is special-cased and **does not** require `pub`.
- `main` must have signature `() -> Void | int | int32`.
- The root file may omit `module`; it is treated as the implicit root module.

### Check a library/module (no entrypoint required)

```bash
tools/haxparse/bin/haxc checklib path/to/module.hax
```

### Dump the checked AST (for compiler development)

```bash
tools/haxparse/bin/haxc ast --lib path/to/module.hax
```

`haxc ast` prints the **checked/resolved** AST used by the checker, including annotations such as inferred types and enum `case` exhaustiveness.

### Run tests

```bash
tools/haxparse/bin/haxprove
```

`haxprove` auto-chdirs to the repo root, so tests are location-independent.

## Standard library

The `std/` directory is a **normative part of the Hax definition**. If the written spec and the standard library disagree, `std/` is the source of truth.

For v0.1 I/O:

- `std::io` provides `print`, `eprint`, `read_file`, and `write_file`.
- `std::sys::IO` defines the intrinsic-backed boundary used by `std::io`.

See `std/README.md` for details.

## Specification

Start here:

- `spec/grammar.ebnf` — normative syntax
- `spec/lexer.md` — comments and strings
- `spec/semantics.md` — typing, `case` exhaustiveness, `Never`, and other semantic rules
