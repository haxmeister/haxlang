
## Gate: parse examples/ok

Run:

    tools/haxparse/bin/haxparse-ok

Or specify a directory:

    tools/haxparse/bin/haxparse-ok examples/ok

Exit status is non-zero if any file fails to parse.

## Unreachable-code checking

`haxparse-ok` runs a conservative unreachable-code check (statements after `return` or `panic()` in the same block).

## Must-return checking

`haxparse-ok` enforces that any subroutine with a non-`Void` return type
must return on all control-flow paths (or terminate via `panic`).

## Import resolution (imports only)

`haxparse-ok` validates that imported modules exist and that `from X import Y` refers to exported (`pub`) symbols.

## Import checking

`haxparse-ok` runs an imports-only name resolution check:
- detects collisions from `from ... import ...`
- detects collisions with `import ... as Alias`


## AST pretty-printer

Run:

    tools/haxparse/bin/haxpretty FILE.hax

Prints a human-readable tree of the parsed AST (no semantic checks).

## AST pretty-printer

Pretty-print the parsed AST:

    tools/haxparse/bin/haxpp FILE.hax

