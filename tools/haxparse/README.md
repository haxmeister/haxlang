# haxparse

Parse Hax v0.1 source files into an AST.

Status: WIP parser front-end (syntax only).

Implemented:
- module header
- import / from-import
- sub definitions (pub/priv accepted)
- blocks
- statements: var, if/else, case/when/else, return, assignment, expr-stmt
- expressions: literals, variables, qualified names, calls, unary (not/-), binary (+-*/% and/or comparisons)

Not yet:
- enums/structs/classes
- loops
- field/method access (.)
- indexing
