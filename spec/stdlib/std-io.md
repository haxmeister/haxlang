# std::io (v0.1)

```hax
module std::io;
```

`std::io` is the user-facing I/O surface in v0.1. It is specified as a thin
wrapper over `std::sys::IO`.

## Printing

```hax
pub sub print(Str $s) -> Void;
pub sub eprint(Str $s) -> Void;
```

## Whole-file operations

```hax
from std::core::Result import Result;

pub sub read_file(Str $path) -> Result[Str, IoError];
pub sub write_file(Str $path, Str $data) -> Result[Int, IoError];
```

## Errors

```hax
pub enum IoError {
  NotFound(Str path);
  PermissionDenied(Str path);
  Other(Str message);
}
```
