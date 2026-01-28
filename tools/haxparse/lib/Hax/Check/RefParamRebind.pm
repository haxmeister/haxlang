package Hax::Check::RefParamRebind;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.001';

# Semantic check (incremental v0.1):
#   - Reference parameters (declared with leading '^' in the param type position)
#     may not be rebound with ':='.
#
# Example (illegal):
#   pub sub f(^Int $p) -> Void {
#     $p := addr($x);
#   }
#
# This is not a borrow checker. We only detect direct Assign statements
# where the LHS is a simple Var referring to a ref parameter.

sub check_module ($mod_ast) {
  my @errs;

  for my $it (@{ $mod_ast->{items} // [] }) {
    next if !$it || ref($it) ne 'HASH';
    next unless (($it->{kind} // '') eq 'Sub');
    _check_sub($it, \@errs);
  }

  return @errs;
}

sub _check_sub ($sub, $errs) {
  my %ref_params;

  for my $p (@{ $sub->{params} // [] }) {
    next if !$p || ref($p) ne 'HASH';
    next unless (($p->{kind} // '') eq 'Param');
    next unless $p->{ref};
    my $sigil = $p->{sigil} // '$';
    my $name  = $p->{name}  // '';
    next if $name eq '';
    $ref_params{"$sigil$name"} = 1;
  }

  _walk_node($sub->{body}, \%ref_params, $errs);
  return;
}

sub _walk_node ($node, $ref_params, $errs) {
  return if !$node || ref($node) ne 'HASH';

  my $k = $node->{kind} // '';

  if ($k eq 'Assign') {
    if (($node->{op} // '') eq ':=') {
      my $lhs = $node->{lhs};
      if ($lhs && ref($lhs) eq 'HASH' && (($lhs->{kind} // '') eq 'Var')) {
        my $key = ($lhs->{sigil} // '') . ($lhs->{name} // '');
        if ($key ne '' && $ref_params->{$key}) {
          push @$errs, _mk_err($node, "^ parameters cannot be rebound with := ($key)");
        }
      }
    }
    _walk_node($node->{lhs}, $ref_params, $errs) if $node->{lhs};
    _walk_node($node->{rhs}, $ref_params, $errs) if $node->{rhs};
    return;
  }

  if ($k eq 'Block') {
    _walk_node($_, $ref_params, $errs) for @{ $node->{stmts} // [] };
    return;
  }

  if ($k eq 'If') {
    _walk_node($node->{cond}, $ref_params, $errs) if $node->{cond};
    _walk_node($node->{then}, $ref_params, $errs) if $node->{then};
    _walk_node($node->{else}, $ref_params, $errs) if $node->{else};
    return;
  }

  if ($k eq 'While') {
    _walk_node($node->{cond}, $ref_params, $errs) if $node->{cond};
    _walk_node($node->{body}, $ref_params, $errs) if $node->{body};
    return;
  }

  if ($k eq 'Case') {
    _walk_node($node->{expr}, $ref_params, $errs) if $node->{expr};
    _walk_node($_, $ref_params, $errs) for @{ $node->{whens} // [] };
    _walk_node($node->{else}, $ref_params, $errs) if $node->{else};
    return;
  }

  if ($k eq 'When') {
    _walk_node($node->{body}, $ref_params, $errs) if $node->{body};
    return;
  }

  if ($k eq 'VarDecl') {
    _walk_node($node->{init}, $ref_params, $errs) if $node->{init};
    return;
  }

  if ($k eq 'ExprStmt') {
    _walk_node($node->{expr}, $ref_params, $errs) if $node->{expr};
    return;
  }

  if ($k eq 'Return') {
    _walk_node($node->{expr}, $ref_params, $errs) if $node->{expr};
    return;
  }

  # Expression shapes
  if ($k eq 'Unary') {
    _walk_node($node->{expr}, $ref_params, $errs) if $node->{expr};
    return;
  }
  if ($k eq 'BinOp') {
    _walk_node($node->{lhs}, $ref_params, $errs) if $node->{lhs};
    _walk_node($node->{rhs}, $ref_params, $errs) if $node->{rhs};
    return;
  }
  if ($k eq 'Call') {
    _walk_node($node->{callee}, $ref_params, $errs) if $node->{callee};
    _walk_node($_, $ref_params, $errs) for @{ $node->{args} // [] };
    return;
  }

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

Hax::Check::RefParamRebind - Disallow rebinding of C<^> parameters using C<:=>

=head1 SYNOPSIS

  use Hax::Check::RefParamRebind;

  my @errs = Hax::Check::RefParamRebind::check_module($mod_ast);
  die $errs[0]{msg} if @errs;

=head1 DESCRIPTION

This checker enforces a small but important rule for Hax v0.1:

  pub sub f(^Int $p) -> Void {
    $p := addr($x);   # illegal
  }

Reference parameters (declared with a leading C<^> in the parameter type
position) are aliases to caller-owned storage. Rebinding them with C<:=>
would break that aliasing model, so it is forbidden.

This is intentionally incremental. It is I<not> a borrow checker. We only
detect direct assignment statements where the LHS is a simple variable
reference to a ref parameter.

=head1 FUNCTIONS

=head2 check_module

  my @errs = Hax::Check::RefParamRebind::check_module($mod_ast);

Returns a list of error hashrefs (empty if no violations).

=head1 AUTHOR

Hax project contributors.

=head1 LICENSE

Same terms as the Hax project.

=cut
