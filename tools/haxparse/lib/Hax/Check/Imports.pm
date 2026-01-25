package Hax::Check::Imports;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.001';

# Imports-only name resolution checks (v0.1):
# - Detect collisions introduced by `from A::B import X, Y;`
# - Detect duplicate names inside a single from-import list
# - Detect collisions between from-import names and `import ... as Alias;` aliases
#
# Notes:
# - `import A::B;` does not introduce an unqualified name in v0.1 (only qualification via `A::B::...`),
#   so we do not check it for collisions unless an explicit `as` alias is used.

sub check_module ($mod_ast) {
  my @errs;

  my %unqual;   # name -> first node that introduced it
  my %alias;    # alias -> first node

  for my $it (@{ $mod_ast->{items} // [] }) {
    next if !$it || ref($it) ne 'HASH';

    my $k = $it->{kind} // '';
    if ($k eq 'Import') {
      my $as = $it->{as};
      next unless defined $as && length $as;

      if (exists $unqual{$as}) {
        push @errs, _mk_err($it, "import alias '$as' collides with from-import name");
      } elsif (exists $alias{$as}) {
        push @errs, _mk_err($it, "duplicate import alias '$as'");
      } else {
        $alias{$as} = $it;
      }
    }
    elsif ($k eq 'FromImport') {
      my %seen_local;
      for my $name (@{ $it->{names} // [] }) {
        if ($seen_local{$name}++) {
          push @errs, _mk_err($it, "duplicate name '$name' in from-import list");
          next;
        }
        if (exists $unqual{$name}) {
          push @errs, _mk_err($it, "from-import name collision for '$name'");
          next;
        }
        if (exists $alias{$name}) {
          push @errs, _mk_err($it, "from-import name '$name' collides with import alias");
          next;
        }
        $unqual{$name} = $it;
      }
    }
  }

  return @errs;
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
