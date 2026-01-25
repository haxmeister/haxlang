package Hax::Check::ResolveImports;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.001';

# Import-only name resolution for Hax v0.1.
#
# Checks:
#  - imported modules exist on disk
#  - from-imported symbols exist in the target module (syntactic scan only)
#
# Does NOT:
#  - resolve local names
#  - typecheck
#  - validate visibility (pub/priv)
#
# Assumptions:
#  - Module path maps to file path: A::B::C -> A/B/C.hax
#  - stdlib root is 'std/' relative to repo root
#  - user modules are relative to current working directory

sub check_module ($mod_ast, %opts) {
  my $std_root = $opts{std_root} // 'std';

  my @errs;

  for my $it (@{ $mod_ast->{items} // [] }) {
    next unless ref($it) eq 'HASH';
    next unless ($it->{kind} // '') =~ /^(Import|FromImport)$/;

    if ($it->{kind} eq 'Import') {
      _check_import($it, $std_root, \\@errs);
    } else {
      _check_from_import($it, $std_root, \\@errs);
    }
  }

  return @errs;
}

sub _check_import ($it, $std_root, $errs) {
  my $mod = $it->{module};
  my $path = _module_to_path($mod, $std_root);

  if (!-f $path) {
    push @$errs, _mk_err($it, "imported module not found: $mod ($path)");
  }
}

sub _check_from_import ($it, $std_root, $errs) {
  my $mod = $it->{module};
  my $path = _module_to_path($mod, $std_root);

  if (!-f $path) {
    push @$errs, _mk_err($it, "from-import module not found: $mod ($path)");
    return;
  }

  my %exports = _scan_exports($path);
  for my $name (@{ $it->{names} // [] }) {
    if (!$exports{$name}) {
      push @$errs, _mk_err($it, "symbol '$name' not found in module $mod");
    }
  }
}

sub _module_to_path ($mod, $std_root) {
  my $rel = $mod;
  $rel =~ s{::}{/}g;
  my $std_path = "$std_root/$rel.hax";
  return -f $std_path ? $std_path : "$rel.hax";
}

sub _scan_exports ($path) {
  # Very shallow scan:
  #   pub sub NAME
  #   pub enum NAME
  #   pub struct NAME
  #   pub class NAME
  my %out;

  open(my $fh, '<:encoding(UTF-8)', $path) or return %out;
  while (my $line = <$fh>) {
    if ($line =~ /^\s*pub\s+(sub|enum|struct|class)\s+([A-Za-z_][A-Za-z0-9_]*)/) {
      $out{$2} = 1;
    }
  }
  close $fh;
  return %out;
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
