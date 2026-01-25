# haxparse

Parse Hax v0.1 source files into an AST.

This tool:
- Performs lexing and parsing only
- Builds a plain hashref AST
- Does NOT do name resolution, typechecking, or code generation

Intended as a spec-validation and development tool.
