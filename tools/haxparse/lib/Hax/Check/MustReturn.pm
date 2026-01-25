package Hax::Check::MustReturn;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.001';

# Must-return checker for Hax v0.1.
# For non-Void functions:
# - Every control-flow path must end with `return EXPR;`
# - `return;` (no expr) is an error
# `panic()` and `__panic()` are treated as noreturn terminators.

sub check_module ($mod_ast) {
  my @errs;
  for my $it (@{ $mod_ast->{items} // [] }) {
    next if !$it || ref($it) ne 'HASH';
    next unless ($it->{kind} // '') eq 'Sub';

    my $ret = $it->{ret};
    my $is_void = _type_is_void($ret);

    if ($is_void) {
      _check_void_returns($it->{body}, \@errs);
    } else {
      _check_nonvoid_returns($it->{body}, \@errs, $it->{name});
    }
  }
  return @errs;
}

sub _type_is_void ($t) {
  return 1 if !$t || ref($t) ne 'HASH';
  my $k = $t->{kind} // '';
  return 1 if $k eq 'TypeName' && ($t->{name} // '') eq 'Void';
  return 0;
}

sub _check_void_returns ($blk, $errs) {
  # In Void functions, `return EXPR;` is not allowed, but `return;` is ok.
  _walk_block($blk, sub ($st) {
    return unless ($st->{kind} // '') eq 'Return';
    if (defined $st->{expr}) {
      push @$errs, _mk_err($st, "return with value in Void function");
    }
  });
}

sub _check_nonvoid_returns ($blk, $errs, $fname) {
  # First: forbid bare return;
  _walk_block($blk, sub ($st) {
    return unless ($st->{kind} // '') eq 'Return';
    if (!defined $st->{expr}) {
      push @$errs, _mk_err($st, "bare return in non-Void function");
    }
  });

  # Second: require all paths terminate with return/panic
  if (!_block_must_terminate($blk)) {
    push @$errs, _mk_err($blk, "missing return on some control-flow path");
  }
}

sub _walk_block ($blk, $cb) {
  return if !$blk || ref($blk) ne 'HASH';
  return if ($blk->{kind} // '') ne 'Block';

  for my $st (@{ $blk->{stmts} // [] }) {
    next if !$st || ref($st) ne 'HASH';
    $cb->($st);

    my $k = $st->{kind} // '';
    if ($k eq 'If') {
      _walk_block($st->{then}, $cb);
      _walk_block($st->{else}, $cb) if $st->{else};
    } elsif ($k eq 'Case') {
      for my $w (@{ $st->{whens} // [] }) {
        _walk_block($w->{body}, $cb);
      }
      _walk_block($st->{else}, $cb) if $st->{else};
    }
  }
}

sub _block_must_terminate ($blk) {
  return 0 if !$blk || ref($blk) ne 'HASH';
  return 0 if ($blk->{kind} // '') ne 'Block';

  my $stmts = $blk->{stmts} // [];
  return 0 if !@$stmts;

  # Scan statements; if we hit a terminator, block terminates.
  # If we see an if/case that terminates on all paths, that's a terminator too.
  for my $st (@$stmts) {
    next if !$st || ref($st) ne 'HASH';
    return 1 if _stmt_must_terminate($st);
  }
  return 0;
}

sub _stmt_must_terminate ($st) {
  my $k = $st->{kind} // '';

  return 1 if $k eq 'Return';
  return 1 if $k eq 'ExprStmt' && _expr_is_panic_call($st->{expr});
  return 1 if $k eq 'Assign'   && _expr_is_panic_call($st->{rhs});

  if ($k eq 'If') {
    return 0 unless $st->{else};
    return _block_must_terminate($st->{then}) && _block_must_terminate($st->{else});
  }

  if ($k eq 'Case') {
    # Without type info, require else to consider it total.
    return 0 unless $st->{else};
    for my $w (@{ $st->{whens} // [] }) {
      return 0 unless _block_must_terminate($w->{body});
    }
    return _block_must_terminate($st->{else});
  }

  return 0;
}

sub _expr_is_panic_call ($e) {
  return 0 if !$e || ref($e) ne 'HASH';
  return 0 if ($e->{kind} // '') ne 'Call';

  my $callee = $e->{callee};
  return 0 if !$callee || ref($callee) ne 'HASH';
  return 0 unless ($callee->{kind} // '') eq 'Name';

  my $name = $callee->{name} // '';

  return 1 if $name eq '__panic';
  return 1 if $name eq 'panic';
  return 1 if $name eq 'std::core::Assert::panic';
  return 1 if $name eq 'std::prelude::panic';

  return 0;
}

sub _mk_err ($node, $msg) {
  my $sp = (ref($node) eq 'HASH' ? ($node->{span} || {}) : {});
  return {
    msg  => $msg,
    file => $sp->{file}  // '<unknown>',
    line => $sp->{sline} // 0,
    col  => $sp->{scol}  // 0,
  };
}

1;
