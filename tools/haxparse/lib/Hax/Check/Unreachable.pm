package Hax::Check::Unreachable;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.006';

# Unreachable-code checker for Hax v0.1.
#
# Goals:
# - Report a clear diagnostic when a statement cannot execute.
# - Keep noise down: within a given "dead" region, report only the first
#   unreachable statement.
# - Use `Never`-typed expressions as terminators.
# - Be path-sensitive for `case` when CaseExhaustive has already proven
#   the case is total by annotating `$case->{_exhaustive} = 1`.
#
# This checker expects ExprTypes to have annotated expressions with a computed
# type in `$node->{_type}`.

sub check_module ($mod_ast) {
  my @errs;
  _check_items($mod_ast->{items} // [], \@errs);
  return @errs;
}

sub _check_items ($items, $errs) {
  for my $it (@$items) {
    next if !$it || ref($it) ne 'HASH';
    next unless (($it->{kind} // '') eq 'Sub');
    _check_block($it->{body}, $errs);
  }
}

sub _check_block ($blk, $errs, $outer_dead = 0) {
  return if $outer_dead;
  return if !$blk || ref($blk) ne 'HASH';
  return if ($blk->{kind} // '') ne 'Block';

  my $terminated    = 0;
  my $dead_reported = 0;
  my $term_reason   = '';

  for my $st (@{ $blk->{stmts} // [] }) {
    next if !$st || ref($st) ne 'HASH';

    if ($terminated) {
      if (!$dead_reported) {
        my $why = length($term_reason) ? " ($term_reason)" : '';
        push @$errs, _mk_err($st, "unreachable statement$why");
        $dead_reported = 1;
      }
      next; # suppress duplicates inside this dead region
    }

    my $k = $st->{kind} // '';

    # Recurse / mark inner regions.
    if ($k eq 'If') {
      # If the condition is `Never`, evaluating it never returns. The whole `if`
      # is a terminator. We still *visit* the branch blocks, but in an
      # outer-dead context so this checker emits no nested unreachable noise.
      my $outer_dead = _expr_is_never($st->{cond}) ? 1 : 0;
      _check_block($st->{then}, $errs, $outer_dead);
      _check_block($st->{else}, $errs, $outer_dead) if $st->{else};
    } elsif ($k eq 'Case') {
      # If the scrutinee is `Never`, evaluating it never returns. The whole `case`
      # is a terminator. Visit arms in an outer-dead context to suppress nested
      # unreachable reports for the same cause.
      my $outer_dead = _expr_is_never($st->{expr}) ? 1 : 0;
      for my $w (@{ $st->{whens} // [] }) {
        next unless ref($w) eq 'HASH';
        _check_block($w->{body}, $errs, $outer_dead);
      }
      _check_block($st->{else}, $errs, $outer_dead) if $st->{else};
    }

    my ($term, $reason) = _stmt_terminates_with_reason($st);
    if ($term) {
      $terminated  = 1;
      $term_reason = $reason // '';
      next;
    }
  }
}

sub _stmt_terminates_with_reason ($st) {
  my $k = $st->{kind} // '';

  return (1, 'after return') if $k eq 'Return';

  if ($k eq 'VarDecl') {
    return (1, 'initializer is Never') if _expr_is_never($st->{init});
    return (0, undef);
  }

  if ($k eq 'ExprStmt') {
    return (1, 'expression is Never') if _expr_is_never($st->{expr});
    return (0, undef);
  }

  if ($k eq 'Assign') {
    return (1, 'rhs is Never') if _expr_is_never($st->{rhs});
    return (0, undef);
  }

  if ($k eq 'If') {
    return (1, 'if condition is Never') if _expr_is_never($st->{cond});
    return (0, undef) unless $st->{else};
    return (_block_terminates($st->{then}) && _block_terminates($st->{else}))
      ? (1, 'after if (both branches terminate)')
      : (0, undef);
  }

  if ($k eq 'While') {
    return (1, 'while condition is Never') if _expr_is_never($st->{cond});
    return (0, undef);
  }

  if ($k eq 'Case') {
    return (1, 'case scrutinee is Never') if _expr_is_never($st->{expr});

    my $total = ($st->{else} || $st->{_exhaustive}) ? 1 : 0;
    return (0, undef) unless $total;

    for my $w (@{ $st->{whens} // [] }) {
      return (0, undef) unless _block_terminates($w->{body});
    }
    if ($st->{else}) {
      return (0, undef) unless _block_terminates($st->{else});
    }
    return (1, 'after case (all arms terminate)');
  }

  return (0, undef);
}

sub _mark_block_unreachable ($blk, $reason, $errs) {
  return if !$blk || ref($blk) ne 'HASH';
  return if ($blk->{kind} // '') ne 'Block';
  my $stmts = $blk->{stmts} // [];
  return if !@$stmts;
  my $first = $stmts->[0];
  return if !$first || ref($first) ne 'HASH';
  push @$errs, _mk_err($first, "unreachable statement ($reason)");
}

sub _block_terminates ($blk) {
  return 0 if !$blk || ref($blk) ne 'HASH';
  return 0 if ($blk->{kind} // '') ne 'Block';
  my $stmts = $blk->{stmts} // [];
  return 0 if !@$stmts;
  my ($term, undef) = _stmt_terminates_with_reason($stmts->[-1]);
  return $term ? 1 : 0;
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
