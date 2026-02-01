package Hax::Check::Entrypoint;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.001';

# Entrypoint rules for executable compilation.
# v0.1 Rule B:
# - The program root module MUST define exactly one `sub main`.
# - `main` does NOT need to be `pub`.
# - `main` MUST take zero parameters.
# - `main` return type MUST be one of: Void, Int, Int32.

sub check_program ($mod_ast) {
  my @errs;

  my @mains;
  for my $it (@{ $mod_ast->{items} // [] }) {
    next if !$it || ref($it) ne 'HASH';
    next unless (($it->{kind} // '') eq 'Sub');
    next unless (($it->{name} // '') eq 'main');
    push @mains, $it;
  }

  if (!@mains) {
    push @errs, _mk_err($mod_ast, 'missing entrypoint: sub main()');
    return @errs;
  }

  if (@mains > 1) {
    # Point at the second declaration for a clearer message.
    push @errs, _mk_err($mains[1], 'duplicate entrypoint: multiple sub main() declarations');
    return @errs;
  }

  my $m = $mains[0];

  my $params = $m->{params} // [];
  if (@$params) {
    push @errs, _mk_err($params->[0], 'entrypoint main() must not take parameters');
  }

  my $ret = $m->{ret};
  my $ok_ret = _type_is_one_of($ret, qw(Void Unit Int Int32 int int32));
  if (!$ok_ret) {
    push @errs, _mk_err($m, 'entrypoint main() must return Void/Unit or int/int32');
  }

  return @errs;
}

sub _type_is_one_of ($t, @names) {
  # In v0.1, missing return annotation is treated as Void by several checks.
  return 1 if !$t;
  return 0 if ref($t) ne 'HASH';
  return 0 if (($t->{kind} // '') ne 'TypeName');
  my %ok = map { $_ => 1 } @names;
  return $ok{$t->{name} // ''} ? 1 : 0;
}

sub _mk_err ($node, $msg) {
  my $file = $node->{file} // '<unknown>';
  my $line = $node->{line} // 0;
  my $col  = $node->{col}  // 0;
  return { msg => $msg, file => $file, line => $line, col => $col };
}

1;
