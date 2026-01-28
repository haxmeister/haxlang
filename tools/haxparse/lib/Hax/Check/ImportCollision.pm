package Hax::Check::ImportCollision;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.001';

# v0.1 semantic rule:
#   Within a single module, no two imports may introduce the same *local* binding.
#
# Local binding names (v0.1):
#   - import Foo::Bar;        => Bar
#   - import Foo::Bar as Baz; => Baz
#   - from Foo import X, Y;   => X and Y
#
# Notes:
# - We ONLY check import-vs-import collisions (including from-import names).
# - We DO NOT yet check collisions against enum/struct/sub names.

sub check_module ($mod_ast) {
  my @errs;

  my %seen;   # local_name -> node that introduced it first

  for my $it (@{ $mod_ast->{items} // [] }) {
    next if !$it || ref($it) ne 'HASH';

    my $k = $it->{kind} // '';
    if ($k eq 'Import') {
      my $local = _import_local($it);
      next unless defined $local && length $local;

      if (exists $seen{$local}) {
        push @errs, _mk_err($it, "import name collision for '$local'");
      } else {
        $seen{$local} = $it;
      }
    }
    elsif ($k eq 'FromImport') {
      for my $name (@{ $it->{names} // [] }) {
        next unless defined $name && length $name;

        if (exists $seen{$name}) {
          push @errs, _mk_err($it, "import name collision for '$name'");
        } else {
          $seen{$name} = $it;
        }
      }
    }
  }

  return @errs;
}

sub _import_local ($node) {
  # Grammar builds:
  #   node('Import', ..., module => 'Foo::Bar', as => $as)
  my $as = $node->{as};
  return $as if defined $as && length $as;

  my $m = $node->{module};
  return undef if !defined $m || $m eq '';
  my @parts = split(/::/, $m);
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

Hax::Check::ImportCollision - detect import-local name collisions

=head1 DESCRIPTION

Checks that imports within a single module do not introduce the same local
binding name more than once.

=head1 RULE

Within a single module:

  import Foo::Bar;
  import Baz::Bar;   # ERROR: collision on local name "Bar"

  from Foo import Thing;
  from Baz import Thing;  # ERROR: collision on local name "Thing"

=head1 LIMITATIONS

This checker only considers collisions between imports (including C<from ...
import ...> names). It does not yet check collisions against module items
like enums, structs, or subs.

=cut
