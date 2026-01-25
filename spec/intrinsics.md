# Hax Intrinsics (v0.1)

This document enumerates the **complete intrinsic surface** assumed by the normative `std/` library for Hax v0.1.

An **intrinsic** is a symbol implemented by the compiler/runtime (not in Hax source). Intrinsics are the only
permitted "magic" in v0.1.

## Conventions

- Intrinsic names **must** begin with `__`.
- Intrinsics are **not** imported; they are always available to all modules.
- Intrinsics are compile-time known and link-time resolved by the toolchain/runtime.

## Required intrinsics

### 1) Process termination

#### `__panic`
```
__panic(Str msg) -> Void
```
- Aborts execution immediately.
- **Noreturn:** `__panic` is noreturn; code after a call is unreachable for control-flow checking.

### 2) Output

#### `__print`
```
__print(Str s) -> Void
```
- Writes `s` to the default output stream (stdout).
- No implicit newline.

### 3) String primitives

#### `__strlen`
```
__strlen(Str s) -> Int
```
- Returns the length of `s` in **bytes**.

#### `__memcmp`
```
__memcmp(Str a, Str b, Int n) -> Int
```
- Compares the first `n` bytes of `a` and `b`.
- Returns `<0`, `0`, or `>0` as per lexicographic comparison.

### 4) Minimal syscalls (POSIX-shaped)

#### `__sys_write`
```
__sys_write(Int fd, Str buf) -> Int
```
- Writes `buf` to file descriptor `fd`.
- Returns `>= 0` on success, `< 0` on error.

#### `__sys_errno`
```
__sys_errno() -> Int
```
- Returns the last OS error code.
