package Hax::Check::CaseBinderScope;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.001';

# Case binder scope (incremental v0.1):
#   - Pattern binders introduced by `when Variant(...) { ... }` are in scope
#     only inside that arm body.
#   - Using a variable ($x/@x/%x/^x) that is not bound in the current scope
#     is an error.
#
# Current bindings recognized:
#   - sub params
#   - `var ...;` declarations
#   - `:=` assignment to a Var (binds in current block scope)
#   - `when` pattern binders (arm-local)
#
# This is intentionally small and lexical-only; it ignores non-sigil names
# (e.g. `Foo`, `Bar::Baz`) and does not resolve fields/methods yet.

sub check_module ($mod_ast) {
  my @errs;
  _check_items($mod_ast->{items} // [], \@errs);
  return @errs;
}

sub _check_items ($items, $errs) {
  for my $it (@$items) {
    next if !$it || ref($it) ne 'HASH';
    my $k = $it->{kind} // '';
    if ($k eq 'Sub') {
      _check_sub($it, $errs);
    }
  }
}

sub _check_sub ($sub, $errs) {
  my @scopes = ( {} ); # stack of lexical scopes

  for my $p (@{ $sub->{params} // [] }) {
    next if !$p || ref($p) ne 'HASH';
    next if (($p->{kind} // '') ne 'Param');
    _bind($p->{sigil}, $p->{name}, \@scopes);
  }

  _check_block($sub->{body}, \@scopes, $errs);
}

sub _check_block ($blk, $scopes, $errs) {
  return if !$blk || ref($blk) ne 'HASH';
  return if (($blk->{kind} // '') ne 'Block');

  push @$scopes, {}; # new lexical scope
  for my $st (@{ $blk->{stmts} // [] }) {
    _check_stmt($st, $scopes, $errs);
  }
  pop @$scopes;
}

sub _check_stmt ($st, $scopes, $errs) {
  return if !$st || ref($st) ne 'HASH';
  my $k = $st->{kind} // '';

  if ($k eq 'VarDecl') {
    # init runs in current scope (no self-reference rule enforced yet)
    _check_expr($st->{init}, $scopes, $errs) if $st->{init};

    _bind($st->{sigil}, $st->{name}, $scopes);
    return;
  }

  if ($k eq 'Assign') {
    _check_expr($st->{rhs}, $scopes, $errs);

    # `:=` on Var binds (like `let`). `=` requires existing binding if lhs is Var.
    if (($st->{op} // '') eq ':=') {
      if ((_kind($st->{lhs}) // '') eq 'Var') {
        _bind($st->{lhs}{sigil}, $st->{lhs}{name}, $scopes);
      } else {
        push @$errs, _mk_err($st->{lhs} // $st, "':=' left-hand side must be a variable");
      }
    } else {
      # '=' rebind; ensure var exists if lhs is Var, and walk lhs for any var refs.
      _check_expr($st->{lhs}, $scopes, $errs);
      if ((_kind($st->{lhs}) // '') eq 'Var') {
        my $key = _key($st->{lhs}{sigil}, $st->{lhs}{name});
        if (!_is_bound($key, $scopes)) {
          push @$errs, _mk_err($st->{lhs}, "Assignment to undefined variable $key");
        }
      }
    }
    return;
  }

  if ($k eq 'ExprStmt') {
    _check_expr($st->{expr}, $scopes, $errs);
    return;
  }

  if ($k eq 'Return') {
    _check_expr($st->{expr}, $scopes, $errs) if $st->{expr};
    return;
  }

  if ($k eq 'If') {
    _check_expr($st->{cond}, $scopes, $errs);
    _check_block($st->{then}, $scopes, $errs);
    _check_block($st->{else}, $scopes, $errs) if $st->{else};
    return;
  }

  if ($k eq 'Case') {
    _check_expr($st->{expr}, $scopes, $errs);

    for my $w (@{ $st->{whens} // [] }) {
      next if !$w || ref($w) ne 'HASH';
      next if (($w->{kind} // '') ne 'When');

      my @arm_scopes = (@$scopes); # copy stack refs (we will push a new scope)
      push @arm_scopes, {};

      # bind pattern vars into arm-local scope
      my $pat = $w->{pat};
      if ($pat && ref($pat) eq 'HASH' && (($pat->{kind} // '') eq 'PatternVariant')) {
        for my $b (@{ $pat->{binds} // [] }) {
          next if !$b || ref($b) ne 'HASH';
          next if (($b->{kind} // '') ne 'PatBind');
          _bind($b->{sigil}, $b->{name}, \@arm_scopes);
        }
      }

      _check_block($w->{body}, \@arm_scopes, $errs);
    }

    if ($st->{else}) {
      _check_block($st->{else}, $scopes, $errs);
    }
    return;
  }

  # Fallback: if it's a statement-shaped node with expr-ish fields we don't know yet,
  # at least try to walk common keys to catch Var uses.
  for my $key (qw(expr cond lhs rhs init)) {
    _check_expr($st->{$key}, $scopes, $errs) if exists $st->{$key};
  }
  for my $key (qw(then else body)) {
    _check_block($st->{$key}, $scopes, $errs) if exists $st->{$key};
  }
}

sub _check_expr ($e, $scopes, $errs) {
  return if !$e;
  return if ref($e) ne 'HASH';

  my $k = $e->{kind} // '';

  if ($k eq 'Var') {
    my $key = _key($e->{sigil}, $e->{name});
    if (!_is_bound($key, $scopes)) {
      push @$errs, _mk_err($e, "Undefined variable $key");
    }
    return;
  }

  if ($k eq 'Call') {
    _check_expr($e->{callee}, $scopes, $errs);
    for my $a (@{ $e->{args} // [] }) {
      _check_expr($a, $scopes, $errs);
    }
    return;
  }

  if ($k eq 'BinOp') {
    _check_expr($e->{lhs}, $scopes, $errs);
    _check_expr($e->{rhs}, $scopes, $errs);
    return;
  }

  if ($k eq 'Unary') {
    _check_expr($e->{expr}, $scopes, $errs);
    return;
  }

  if ($k eq 'Case') {
    # case as expression isn't in grammar today, but keep it safe.
    _check_expr($e->{expr}, $scopes, $errs);
    for my $w (@{ $e->{whens} // [] }) {
      next if !$w || ref($w) ne 'HASH';
      my @arm_scopes = (@$scopes);
      push @arm_scopes, {};
      my $pat = $w->{pat};
      if ($pat && ref($pat) eq 'HASH' && (($pat->{kind} // '') eq 'PatternVariant')) {
        for my $b (@{ $pat->{binds} // [] }) {
          next if !$b || ref($b) ne 'HASH';
          next if (($b->{kind} // '') ne 'PatBind');
          _bind($b->{sigil}, $b->{name}, \@arm_scopes);
        }
      }
      _check_block($w->{body}, \@arm_scopes, $errs);
    }
    _check_block($e->{else}, $scopes, $errs) if $e->{else};
    return;
  }

  # Literals / names: no vars inside
  return if $k =~ /^Lit/;
  return if $k eq 'Name';

  # Generic recursive walk over hash values to catch nested expressions.
  for my $v (values %$e) {
    if (ref($v) eq 'HASH' && exists $v->{kind}) {
      _check_expr($v, $scopes, $errs);
    } elsif (ref($v) eq 'ARRAY') {
      for my $x (@$v) {
        _check_expr($x, $scopes, $errs) if ref($x) eq 'HASH';
      }
    }
  }
}

sub _bind ($sigil, $name, $scopes) {
  my $key = _key($sigil, $name);
  $scopes->[-1]{$key} = 1;
  return;
}

sub _is_bound ($key, $scopes) {
  for (my $i = $#$scopes; $i >= 0; $i--) {
    return 1 if $scopes->[$i]{$key};
  }
  return 0;
}

sub _key ($sigil, $name) {
  $sigil //= '';
  $name  //= '';
  return "$sigil$name";
}

sub _kind ($n) {
  return if !$n || ref($n) ne 'HASH';
  return $n->{kind};
}

sub _mk_err ($node, $msg) {
  my $sp = $node->{span} || {};
  return {
    msg  => $msg,
    file => $sp->{file}  // '<unknown>',
    line => $sp->{sline} // 0,
    col  => $sp->{scol}  // 0,
  };
}

1;
