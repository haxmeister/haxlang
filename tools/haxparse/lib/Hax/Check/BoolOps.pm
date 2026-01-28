package Hax::Check::BoolOps;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.001';

# Bool-operator semantic checks (incremental v0.1):
#   - `not X` requires X to be Bool
#   - `X and Y` requires X and Y to be Bool
#   - `X or  Y` requires X and Y to be Bool
#
# Minimal Bool classification (no full type checker yet):
#   - LitBool is Bool
#   - Var is Bool if it is declared as Bool (params + var decls)
#   - `not` / `and` / `or` produce Bool if operands are Bool
#   - comparisons (== != < <= > >=) produce Bool (operands unchecked for now)

sub check_module ($mod_ast) {
  my @errs;
  _check_items($mod_ast->{items} // [], \@errs);
  return @errs;
}

sub _check_items ($items, $errs) {
  for my $it (@$items) {
    next if !$it || ref($it) ne 'HASH';
    next if (($it->{kind} // '') ne 'Sub');
    _check_sub($it, $errs);
  }
}

sub _check_sub ($sub, $errs) {
  my @scopes = ( {} );

  for my $p (@{ $sub->{params} // [] }) {
    next if !$p || ref($p) ne 'HASH';
    next if (($p->{kind} // '') ne 'Param');
    _bind_bool($p->{sigil}, $p->{name}, $p->{type}, \@scopes);
  }

  _check_block($sub->{body}, \@scopes, $errs);
}

sub _check_block ($blk, $scopes, $errs) {
  return if !$blk || ref($blk) ne 'HASH';
  return if (($blk->{kind} // '') ne 'Block');

  push @$scopes, {};

  for my $st (@{ $blk->{stmts} // [] }) {
    next if !$st || ref($st) ne 'HASH';
    _check_stmt($st, $scopes, $errs);
  }

  pop @$scopes;
}

sub _check_stmt ($st, $scopes, $errs) {
  my $k = $st->{kind} // '';

  if ($k eq 'VarDecl') {
    _bind_bool($st->{sigil}, $st->{name}, $st->{type}, $scopes);
    _check_expr($st->{init}, $scopes, $errs) if $st->{init};
    return;
  }

  if ($k eq 'Assign') {
    _check_expr($st->{lhs}, $scopes, $errs) if $st->{lhs};
    _check_expr($st->{rhs}, $scopes, $errs) if $st->{rhs};
    return;
  }

  if ($k eq 'ExprStmt') {
    _check_expr($st->{expr}, $scopes, $errs) if $st->{expr};
    return;
  }

  if ($k eq 'If') {
    _check_expr($st->{cond}, $scopes, $errs) if $st->{cond};
    _check_block($st->{then}, $scopes, $errs) if $st->{then};
    _check_block($st->{else}, $scopes, $errs) if $st->{else};
    return;
  }

  if ($k eq 'While') {
    _check_expr($st->{cond}, $scopes, $errs) if $st->{cond};
    _check_block($st->{body}, $scopes, $errs) if $st->{body};
    return;
  }

  if ($k eq 'Case') {
    _check_expr($st->{expr}, $scopes, $errs) if $st->{expr};
    for my $w (@{ $st->{whens} // [] }) {
      next if !$w || ref($w) ne 'HASH';
      _check_expr($w->{expr}, $scopes, $errs) if $w->{expr};
      _check_block($w->{body}, $scopes, $errs) if $w->{body};
    }
    _check_block($st->{else}, $scopes, $errs) if $st->{else};
    return;
  }

  if ($k eq 'Return') {
    _check_expr($st->{expr}, $scopes, $errs) if $st->{expr};
    return;
  }

  # Fallback: do nothing (other statements not present in v0.1 yet)
  return;
}

sub _check_expr ($e, $scopes, $errs) {
  return if !$e || ref($e) ne 'HASH';

  my $k = $e->{kind} // '';

  if ($k eq 'Unary' && ($e->{op} // '') eq 'not') {
    my $inner = $e->{expr};
    if (!_expr_is_bool($inner, $scopes)) {
      push @$errs, _mk_err($e, "'not' operand must be Bool");
    }
    _check_expr($inner, $scopes, $errs) if $inner;
    return;
  }

  if ($k eq 'BinOp') {
    my $op = $e->{op} // '';
    if ($op eq 'and' || $op eq 'or') {
      my $lhs = $e->{lhs};
      my $rhs = $e->{rhs};
      if (!_expr_is_bool($lhs, $scopes) || !_expr_is_bool($rhs, $scopes)) {
        push @$errs, _mk_err($e, "'$op' operands must be Bool");
      }
    }

    _check_expr($e->{lhs}, $scopes, $errs) if $e->{lhs};
    _check_expr($e->{rhs}, $scopes, $errs) if $e->{rhs};
    return;
  }

  if ($k eq 'Call') {
    _check_expr($e->{callee}, $scopes, $errs) if $e->{callee};
    _check_expr($_, $scopes, $errs) for @{ $e->{args} // [] };
    return;
  }

  # Leaf nodes / other expr kinds: nothing to enforce yet.
  return;
}

sub _expr_is_bool ($e, $scopes) {
  return 0 if !$e || ref($e) ne 'HASH';

  my $k = $e->{kind} // '';

  return 1 if $k eq 'LitBool';

  if ($k eq 'Unary' && ($e->{op} // '') eq 'not') {
    return _expr_is_bool($e->{expr}, $scopes);
  }

  if ($k eq 'BinOp') {
    my $op = $e->{op} // '';
    if ($op eq 'and' || $op eq 'or') {
      return _expr_is_bool($e->{lhs}, $scopes) && _expr_is_bool($e->{rhs}, $scopes);
    }
    if ($op eq '==' || $op eq '!=' || $op eq '<' || $op eq '<=' || $op eq '>' || $op eq '>=') {
      return 1;
    }
  }

  if ($k eq 'Var') {
    my $key = ($e->{sigil} // '') . ($e->{name} // '');
    for (my $i = $#$scopes; $i >= 0; $i--) {
      return 1 if $scopes->[$i]{$key};
    }
    return 0;
  }

  return 0;
}

sub _bind_bool ($sigil, $name, $type, $scopes) {
  return if !$sigil || !$name;
  return if !$type || ref($type) ne 'HASH';
  return if (($type->{kind} // '') ne 'TypeName');
  return if (($type->{name} // '') ne 'Bool');

  my $key = $sigil . $name;
  $scopes->[-1]{$key} = 1;
  return;
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

__END__

=pod

=head1 NAME

Hax::Check::BoolOps - Enforce Bool operands for C<not/and/or>

=head1 SYNOPSIS

  use Hax::Check::BoolOps;

  my @errs = Hax::Check::BoolOps::check_module($ast);
  die $errs[0]{msg} if @errs;

=head1 DESCRIPTION

This checker incrementally enforces a strict Bool model:

  not X
  X and Y
  X or Y

The operand(s) must classify as C<Bool>.

This is intentionally not a full type checker. For v0.1, an expression
classifies as Bool only if it is:

=over 4

=item * a Bool literal (C<true/false>)

=item * a variable declared as C<Bool>

=item * a nested Bool operator (C<not/and/or>)

=item * a comparison expression (C<== != < <= > >=>)

=back

=head1 FUNCTIONS

=head2 check_module

  my @errs = Hax::Check::BoolOps::check_module($mod_ast);

Returns a list of error hashrefs (empty if no violations).

=head1 AUTHOR

Hax project contributors.

=head1 LICENSE

Same terms as the Hax project.

=cut
