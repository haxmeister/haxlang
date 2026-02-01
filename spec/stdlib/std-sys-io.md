# std::sys::IO (v0.1)

```hax
module std::sys::IO;
```

`std::sys::*` modules form the **toolchain/runtime boundary**. They are the only
place in v0.1 where the standard library may rely on **intrinsics**.

`std::sys::IO` provides a minimal, POSIX-shaped façade used by `std::io`.

## Types

### `IOError`

```hax
pub struct IOError {
  pub field Int code;
  pub field Str msg;
}
```

- `code` is the platform error code (e.g., POSIX `errno`).
- `msg` is a short, context string suitable for diagnostics.

## Output

```hax
from std::core::Result import Result;

pub sub write_stdout(Str $s) -> Result[Int, IOError];
pub sub write_stderr(Str $s) -> Result[Int, IOError];
```

- On success, returns `Ok(nbytes)`.
- On failure, returns `Err(IOError{code, msg})`.

`std::io::print` / `std::io::eprint` may choose to ignore errors in v0.1.

## Whole-file operations

```hax
pub sub read_file(Str $path) -> Result[Str, IOError];
pub sub write_file(Str $path, Str $data) -> Result[Int, IOError];
```

These are **whole-operation** helpers and intentionally do not specify streaming,
buffering, or partial I/O semantics in v0.1.

## Intrinsics

The following intrinsics are required by this module (see `spec/intrinsics.md`).

```hax
__sys_write(Int fd, Str buf) -> Int
__sys_errno() -> Int

__sys_read_file(Str path) -> Result[Str, Int]
__sys_write_file(Str path, Str data) -> Result[Int, Int]
```

For `__sys_read_file` / `__sys_write_file`, the error payload is an OS error
code (e.g., POSIX `errno`).
