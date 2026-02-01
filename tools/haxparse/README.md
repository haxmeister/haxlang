# tools/haxparse

This directory contains the v0.1 front-end tooling for Hax (parser + semantic checker) and its test harness.

## Primary tool: `haxc`

`haxc` is the front-door CLI for parsing and checking Hax source.

All commands accept:

- `-I <dir>` — add an import root for `import`/`from ... import ...`
- `--std <dir>` — path to the standard library root (defaults to `./std` when run from repo root)

### Program mode checking

```bash
tools/haxparse/bin/haxc check FILE.hax
```

Program mode enforces an entrypoint (v0.1 Rule B):

- `main` is special-cased and does not require `pub`.
- `main` must have signature `() -> Void | int | int32`.
- The root file may omit `module`; it is treated as the implicit root module.

### Library/module mode checking

```bash
tools/haxparse/bin/haxc checklib FILE.hax
```

`checklib` is a thin wrapper over `haxc check --lib`.

### Checked AST dump (debugging)

```bash
tools/haxparse/bin/haxc ast [--lib] FILE.hax
```

`haxc ast` prints the **checked/resolved** AST used by the checker, including annotations (e.g. inferred types and enum `case` exhaustiveness).

The AST dump is a compiler debugging view, not a stable external interface.

## Tests: `haxprove`

Run the test suite:

```bash
tools/haxparse/bin/haxprove
```

`haxprove` auto-chdirs to the repo root so tests are location-independent.

Examples are checked as part of the suite:

- `examples/ok/*.hax` via library/module mode
- `examples/prog_ok/*.hax` via program mode

## Legacy developer utilities

These scripts are useful during development:

- `tools/haxparse/bin/haxpp` — pretty-print the parsed AST (no semantic checks)
- `tools/haxparse/bin/haxpretty` — human-readable parse tree (no semantic checks)
- `tools/haxparse/bin/haxparse-ok` — parse+check a directory (historical; mostly superseded by `haxc`)