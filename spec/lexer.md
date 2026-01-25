# Lexer (v0.1)

## Source text and identifiers

- Source is UTF-8.
- Identifiers are ASCII in v0.1: `[A-Za-z_][A-Za-z0-9_]*`.

## Whitespace

- Whitespace separates tokens; statements end with `;`.

## Comments

- Comments are block comments delimited by `--` and `--`.
- Comments may span multiple lines.
- Comments are not nestable.
- Comment delimiters are not recognized inside string literals.
- Unterminated comments are a lexer error.

Example:

```hax
-- this is a comment --
var Int $x = 1; -- inline -- var Int $y = 2;
--
multiline
comment
--
```

## Strings

### Double-quoted strings

- Delimited by `"`.
- Escapes processed: `\`, `"`, `\n`, `\r`, `\t`.
- Any other `\X` is a lexer error in v0.1.

### Single-quoted strings (raw)

- Delimited by `'`.
- No escape processing (backslashes are literal).
- Intended for raw literals.

## Numbers

- Integers: decimal only in v0.1 (`0` or `[1-9][0-9]*`).
- Floats: `digits '.' digits` in v0.1.

## Operators (not exhaustive)

- `::` qualification
- `:=` bind/rebind
- `->` return type annotation
- `== != <= >=`
- `=>` hash literal key/value separator
