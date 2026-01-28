package Hax::Check::ImportCollision;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.001';

# Import collision checker (v0.1).
#
# Rule (for now): within a single module, imports must not introduce the same
# local binding name twice.
#
# Local binding name rules:
#   import Foo::Bar;        -> Bar
#   import Foo::Bar as Baz; -> Baz
#   from Foo import X, Y;   -> X, Y
#
# Notes:
# - This does NOT yet check collisions against local enum/struct/sub names.
# - This is intentionally import-surface-only.

sub check_module ($mod_ast) {
  my @errs;
  my %seen;  # local name -> first node

  for my $it (@{ $mod_ast->{items} // [] }) {
    next unless ref($it) eq 'HASH';
    my $k = $it->{kind} // '';

    if ($k eq 'Import') {
      my $local = _local_name_for_import($it);
      next unless defined $local && length $local;

      if (exists $seen{$local}) {
        push @errs, _mk_err($it, "import collision on local name '$local'");
      } else {
        $seen{$local} = $it;
      }
      next;
    }

    if ($k eq 'FromImport') {
      for my $name (@{ $it->{names} // [] }) {
        next unless defined $name && length $name;
        if (exists $seen{$name}) {
          push @errs, _mk_err($it, "import collision on local name '$name'");
        } else {
          $seen{$name} = $it;
        }
      }
      next;
    }
  }

  return @errs;
}

sub _local_name_for_import ($it) {
  my $as = $it->{as};
  return $as if defined $as && length $as;

  my $mod = $it->{module};
  return undef if !defined $mod || $mod eq '';
  my @parts = split /::/, $mod;
  return $parts[-1];
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

Hax::Check::ImportCollision - reject duplicate local import bindings

=head1 SYNOPSIS

  my @errs = Hax::Check::ImportCollision::check_module($ast);

=head1 DESCRIPTION

This checker enforces a small import-surface rule for Hax v0.1: within a single
module, imports must not introduce the same local binding name twice.

It currently only reasons about bindings introduced by C<import> and
C<from ... import ...> statements. It does not yet check collisions against
local declarations (enums/structs/subs).

=head1 RULES

=over 4

=item *

C<import Foo::Bar;> binds C<Bar>.

=item *

C<import Foo::Bar as Baz;> binds C<Baz>.

=item *

C<from Foo import X, Y;> binds C<X> and C<Y>.

=back

=head1 AUTHOR

Hax project contributors.

=cut
