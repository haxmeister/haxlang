package Hax::Check::Unreachable;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.003';

# Conservative unreachable-code checker for Hax v0.1.
# Flags statements after an unconditional terminator (return or Never-typed expression)
# within the same block.
#
# Notes:
# - We do not assume `case` without `else` is exhaustive (type info not available here).
# - This checker expects ExprTypes to have annotated expressions with a computed
#   type in `$node->{_type}`. In particular, panic-like noreturn calls are typed
#   as `Never`, and any statement whose evaluated expression is `Never` is
#   treated as terminating the current block.

sub check_module ($mod_ast) {
  my @errs;
  _check_items($mod_ast->{items} // [], \@errs);
  return @errs;
}

sub _check_items ($items, $errs) {
  for my $it (@$items) {
    next if !$it || ref($it) ne 'HASH';
    if (($it->{kind} // '') eq 'Sub') {
      _check_block($it->{body}, $errs);
    }
  }
}

sub _check_block ($blk, $errs) {
  return if !$blk || ref($blk) ne 'HASH';
  return if ($blk->{kind} // '') ne 'Block';

  my $terminated = 0;
  for my $st (@{ $blk->{stmts} // [] }) {
    next if !$st || ref($st) ne 'HASH';

    if ($terminated) {
      push @$errs, _mk_err($st, "unreachable statement");
      next;
    }

    # Recurse into nested blocks first (so we report inner unreachables too)
    my $k = $st->{kind} // '';
    if ($k eq 'If') {
      _check_block($st->{then}, $errs);
      _check_block($st->{else}, $errs) if $st->{else};
    } elsif ($k eq 'Case') {
      for my $w (@{ $st->{whens} // [] }) {
        _check_block($w->{body}, $errs);
      }
      _check_block($st->{else}, $errs) if $st->{else};
    }

    if (_stmt_terminates($st)) {
      $terminated = 1;
      next;
    }
  }
}

sub _stmt_terminates ($st) {
my $k = $st->{kind} // '';
return 1 if $k eq 'Return';

if ($k eq 'VarDecl') {
  # If the initializer is Never, the declaration terminates the block.
  return _expr_is_never($st->{init});
}

if ($k eq 'ExprStmt') {
  return _expr_is_never($st->{expr});
}

if ($k eq 'Assign') {
  return _expr_is_never($st->{rhs});
}

if ($k eq 'If') {
  # If evaluating the condition never returns, the whole statement terminates.
  return 1 if _expr_is_never($st->{cond});

  return 0 unless $st->{else};
  return _block_terminates($st->{then}) && _block_terminates($st->{else});
}

if ($k eq 'While') {
  return 1 if _expr_is_never($st->{cond});
  return 0;
}

if ($k eq 'Case') {
  # Conservative: only terminating if there is an else and all branches terminate.
  return 0 unless $st->{else};
  for my $w (@{ $st->{whens} // [] }) {
    return 0 unless _block_terminates($w->{body});
  }
  return _block_terminates($st->{else});
}

return 0;

}

sub _block_terminates ($blk) {
  return 0 if !$blk || ref($blk) ne 'HASH';
  return 0 if ($blk->{kind} // '') ne 'Block';
  my $stmts = $blk->{stmts} // [];
  return 0 if !@$stmts;
  return _stmt_terminates($stmts->[-1]);
}

sub _expr_is_never ($e) {
  return 0 if !$e || ref($e) ne 'HASH';
  my $t = $e->{_type};
  return 0 if !$t || ref($t) ne 'HASH';
  return 0 unless ($t->{kind} // '') eq 'TypeName';
  return (($t->{name} // '') eq 'Never') ? 1 : 0;
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
