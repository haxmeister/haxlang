# Hax AST Specification

This document defines the **normative** abstract syntax tree (AST) for the Hax language.
Any conforming parser MUST produce an AST equivalent to the structures described here.

Notes:
- Whitespace, comments, and parentheses used only for grouping do **not** appear in the AST.
- Source locations (`span` / `loc`) are recommended for tooling, but are not required by this document.

## Module

Module {
  name: Path,
  imports: [Import],
  decls: [TopDecl]
}

Path = [Ident]           # e.g. std::core::Result => ["std","core","Result"]

## Imports

Import =
  | ImportModule { module: Path, alias: Ident? }            # import std::prelude; / import X as Y;
  | ImportFrom   { module: Path, items: [Ident] }           # from std::core::Assert import assert, panic;

## Top-level Declarations

TopDecl =
  | EnumDecl
  | StructDecl
  | ClassDecl
  | SubDecl
  | GlobalVarDecl

Visibility = pub | priv

## Enum

EnumDecl {
  name: Ident,
  params: [TypeParam],
  variants: [EnumVariant],
  visibility: Visibility
}

EnumVariant {
  name: Ident,
  payload: [VariantField]      # Some(Int $value) => [{type:Int, name:"value"}]
}

VariantField {
  type: Type,
  name: Ident?                 # optional binder name (if provided in source)
}

## Struct (reserved)

StructDecl {
  name: Ident,
  params: [TypeParam],
  fields: [Field],
  visibility: Visibility
}

Field {
  name: Ident,
  type: Type
}

## Class (reserved)

ClassDecl {
  name: Ident,
  params: [TypeParam],
  fields: [Field],
  methods: [SubDecl],
  visibility: Visibility
}

## Subroutine

SubDecl {
  name: Ident,
  params: [Param],
  ret_type: Type,
  body: Block,
  visibility: Visibility
}

Param {
  name: Ident,                 # source `$x` is stored without the sigil, e.g. "x"
  type: Type                   # ref-ness is represented in Type (see RefType)
}

## Global Variable (reserved)

GlobalVarDecl {
  name: Ident,
  type: Type,
  init: Expr,
  visibility: Visibility,
  init_kind: InitKind
}

## Statements

Block {
  stmts: [Stmt]
}

Stmt =
  | VarDeclStmt
  | ExprStmt
  | ReturnStmt

VarDeclStmt {
  name: Ident,
  type: Type,
  init: Expr,
  init_kind: InitKind          # '=' vs ':='
}

InitKind = AssignEq | BindColonEq

ExprStmt {
  expr: Expr
}

ReturnStmt {
  expr: Expr
}

## Expressions

Expr =
  | Literal
  | Name                        # identifiers and qualified paths
  | Call
  | Assign                      # '=' assignment expression (if your grammar permits it as Expr)
  | Bind                        # ':=' binding expression (if your grammar permits it as Expr)
  | BinaryOp
  | UnaryOp
  | IfExpr
  | CaseExpr
  | BlockExpr

Literal =
  | IntLiteral { value: Int }
  | NumLiteral { value: Num }
  | StrLiteral { value: Str }
  | BoolLiteral { value: Bool }

Name {
  path: Path                    # ["Result","Ok"] for Result::Ok
}

Call {
  callee: Expr,                 # typically Name, but can be any Expr if grammar allows
  args: [Expr]
}

BinaryOp {
  op: BinOp,
  lhs: Expr,
  rhs: Expr
}

# BinOp includes at least operators used in examples: +, /, %, ==, and, or
BinOp = "+" | "/" | "%" | "==" | "and" | "or"

UnaryOp {
  op: UnOp,
  expr: Expr
}

UnOp = "-" | "not"

IfExpr {
  cond: Expr,
  then: Block,
  else: Block?                  # present if source has else; otherwise null/absent
}

CaseExpr {
  expr: Expr,
  arms: [CaseArm]
}

CaseArm {
  pattern: Pattern,
  body: Block
}

BlockExpr {
  block: Block
}

## Patterns (minimum, as used in examples)

Pattern =
  | PatCtor                      # Some(Int $n) / None
  | PatWildcard                  # reserved for later `_` support

PatCtor {
  name: Path,                    # constructor name, optionally qualified
  args: [PatBinder]              # empty list for nullary ctors (e.g. None)
}

PatBinder {
  type: Type,
  name: Ident                    # binder name (source `$n` stored without sigil)
}

PatWildcard { }

## Types

Type =
  | NamedType
  | GenericType
  | RefType

NamedType {
  name: Path                     # Int, Bool, std::core::Result, etc
}

GenericType {
  base: NamedType,               # base.name may be qualified
  params: [Type]                 # Result[Int, Str]
}

RefType {
  inner: Type                    # ^Int, ^Result[Int, Str], etc
}

## Lexical atoms

Ident = string                   # excluding sigils like '$'
