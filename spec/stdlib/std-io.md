# std::io (v0.1)

```hax
module std::io;
```

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
  NotFound { Str path };
  PermissionDenied { Str path };
  Other { Str message };
}
```
