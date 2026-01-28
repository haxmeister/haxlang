package Hax::Check::ResolveImports;

use v5.36;
use strict;
use warnings;

use Hax::Lexer;
use Hax::Parser;

our $VERSION = '0.001';

# Import-only name resolution for Hax v0.1.
#
# Checks:
#  - imported modules exist on disk
#  - from-imported symbols exist in the target module (prefers AST, falls back to scan)
#
# Does NOT:
#  - resolve local names beyond import surfaces
#  - typecheck
#  - validate visibility (pub/priv) beyond exported surface (only `pub` is considered exported)
#
# Assumptions:
#  - Module path maps to file path: A::B::C -> A/B/C.hax
#  - stdlib root is 'std/' relative to repo root
#  - user modules are relative to current working directory

sub check_module ($mod_ast, %opts) {
  my $std_root = $opts{std_root} // 'std';
  my $include  = $opts{include}  // [];
  $include = [$include] if ref($include) ne 'ARRAY';

  my %export_cache;  # path -> { name => 1 }
  my %parse_cache;   # path -> ast|undef
  my %in_progress;   # path -> 1 (cycle breaker)

  my @errs;

  for my $it (@{ $mod_ast->{items} // [] }) {
    next unless ref($it) eq 'HASH';
    next unless ($it->{kind} // '') =~ /^(Import|FromImport)$/;

    if ($it->{kind} eq 'Import') {
      _check_import($it, $std_root, $include, \%parse_cache, \%in_progress, \@errs);
    } else {
      _check_from_import($it, $std_root, $include, \%export_cache, \%parse_cache, \%in_progress, \@errs);
    }
  }

  return @errs;
}

sub _check_import ($it, $std_root, $include, $parse_cache, $in_progress, $errs) {
  my $mod = $it->{module};
  my $path = _module_to_path($mod, $std_root, $include);

  if (!-f $path) {
    push @$errs, _mk_err($it, "imported module not found: $mod ($path)");
  }
}

sub _check_from_import ($it, $std_root, $include, $export_cache, $parse_cache, $in_progress, $errs) {
  my $mod = $it->{module};
  my $path = _module_to_path($mod, $std_root, $include);

  if (!-f $path) {
    push @$errs, _mk_err($it, "from-import module not found: $mod ($path)");
    return;
  }

  my %exports = %{ _exports_for_path($path, $export_cache, $parse_cache, $in_progress) };
  for my $name (@{ $it->{names} // [] }) {
    if (!$exports{$name}) {
      push @$errs, _mk_err($it, "symbol '$name' not found in module $mod");
    }
  }
}

sub _module_to_path ($mod, $std_root, $include) {
  my $rel = $mod;
  $rel =~ s{::}{/}g;

  my @candidates;
  push @candidates, "$std_root/$rel.hax" if defined $std_root && length $std_root;
  push @candidates, "$rel.hax";
  for my $dir (@{ $include // [] }) {
    next if !defined $dir || $dir eq '';
    push @candidates, "$dir/$rel.hax";
  }

  for my $p (@candidates) {
    return $p if -f $p;
  }
  # Return the default project-relative path for error messages.
  return "$rel.hax";
}

sub _exports_for_path ($path, $export_cache, $parse_cache, $in_progress) {
  return $export_cache->{$path} if exists $export_cache->{$path};

  # Cycle breaker (A imports B imports A) while doing recursive parse in the future.
  if ($in_progress->{$path}++) {
    $export_cache->{$path} = {};
    return $export_cache->{$path};
  }

  my $ast = _parse_file($path, $parse_cache);
  my $exports = {};

  if ($ast && ref($ast) eq 'HASH') {
    $exports = _exports_from_ast($ast);
  }

  if (!$exports || !%$exports) {
    $exports = _scan_exports($path);
  }

  delete $in_progress->{$path};
  $export_cache->{$path} = $exports;
  return $exports;
}

sub _parse_file ($path, $parse_cache) {
  return $parse_cache->{$path} if exists $parse_cache->{$path};

  open(my $fh, '<:encoding(UTF-8)', $path) or do {
    $parse_cache->{$path} = undef;
    return undef;
  };
  my $src = do { local $/; <$fh> };
  close $fh;

  my $lex = Hax::Lexer->new(file => $path, src => $src);
  my $p   = Hax::Parser->new(lexer => $lex);
  my $ast;
  eval { $ast = $p->parse; 1 } or do {
    $parse_cache->{$path} = undef;
    return undef;
  };

  $parse_cache->{$path} = $ast;
  return $ast;
}

sub _exports_from_ast ($mod_ast) {
  # Exported surface for v0.1: top-level items with explicit pub.
  my %out;

  for my $it (@{ $mod_ast->{items} // [] }) {
    next unless ref($it) eq 'HASH';
    next unless ($it->{vis} // '') eq 'pub';

    my $k = $it->{kind} // '';
    next unless $k =~ /^(Sub|Enum|Struct|Class)$/;

    my $name = $it->{name};
    $out{$name} = 1 if defined $name && $name ne '';
  }

  return \%out;
}

sub _scan_exports ($path) {
  # Shallow fallback scan for exports:
  #   pub sub NAME
  #   pub enum NAME
  #   pub struct NAME
  #   pub class NAME
  my %out;

  open(my $fh, '<:encoding(UTF-8)', $path) or return {};
  while (my $line = <$fh>) {
    if ($line =~ /^\s*pub\s+(sub|enum|struct|class)\s+([A-Za-z_][A-Za-z0-9_]*)/) {
      $out{$2} = 1;
    }
  }
  close $fh;
  return \%out;
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
