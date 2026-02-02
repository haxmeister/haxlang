package Hax::ASTDump;

use v5.36;
use strict;
use warnings;

<<<<<<< HEAD
our $VERSION = '0.001';

# Developer-facing AST dump for debugging.
#
# This is intentionally *not* a stable public format. It is, however:
# - deterministic (field order is fixed)
# - readable (indent reflects tree structure)
# - lossless for compiler-relevant annotations (e.g. _type, _exhaustive)

sub dump ($ast, %opt) {
=======
use Exporter 'import';
our @EXPORT_OK = qw(dump_module_ast);
our $VERSION = '0.001';

# Debug-only checked AST dumper. Not a stable interface.

my %FIELD_ORDER = (
  Module => [qw(span name items)],
  Import => [qw(span module as)],
  Sub    => [qw(span name vis params ret body)],
  Param  => [qw(span name sigil type ref)],
  Block  => [qw(span stmts)],
  VarDecl=> [qw(span name sigil type init op ref storage)],
  Assign => [qw(span lhs rhs op)],
  Return => [qw(span expr)],
  If     => [qw(span cond then else)],
  Case   => [qw(span expr whens else _exhaustive)],
  When   => [qw(span pat body)],
  PatternVariant => [qw(span name bind)],
  PatBind=> [qw(span name sigil type)],
  ExprStmt => [qw(span expr)],
  Call   => [qw(span callee args _type)],
  Name   => [qw(span name)],
  Var    => [qw(span name sigil _type)],
  BinOp  => [qw(span lhs rhs op _type)],
  LitInt => [qw(span value _type)],
  LitStr => [qw(span value _type)],
  LitBool=> [qw(span value _type)],
  TypeName => [qw(span name)],
  TypeApply => [qw(span args base)],
);

sub dump_module_ast ($ast, %opt) {
>>>>>>> 4b558b9 (add Core IR spec, ast + lower tooling, and tests)
  my $mode     = $opt{mode}     // '<unknown>';
  my $root     = $opt{root}     // '<unknown>';
  my $std_root = $opt{std_root} // '<unknown>';
  my $include  = $opt{include}  // [];

  my @out;
  push @out, "HAX AST v0.1";
  push @out, "phase: checked_ast";
  push @out, "mode: $mode";
  push @out, "root: $root";
  push @out, "stdlib: $std_root";
  push @out, "include: " . join(", ", @$include);
  push @out, "";
<<<<<<< HEAD

=======
>>>>>>> 4b558b9 (add Core IR spec, ast + lower tooling, and tests)
  push @out, _pp_value($ast, 0);
  return join("\n", @out) . "\n";
}

<<<<<<< HEAD
# -----------------
# Pretty-printer core
# -----------------

sub _indent ($n) { return '  ' x $n; }

sub _is_node ($v) {
  return 0 if !defined $v;
  return 0 if ref($v) ne 'HASH';
  return 1 if exists $v->{kind};
  return 0;
}

sub _is_span ($v) {
  return 0 if !defined $v || ref($v) ne 'HASH';
  return 1 if exists $v->{file} && exists $v->{sline} && exists $v->{scol} && exists $v->{eline} && exists $v->{ecol};
  return 0;
}

sub _span_str ($sp) {
  return '<no-span>' if !_is_span($sp);
  return sprintf(
    "%s:%d:%d..%d:%d",
    ($sp->{file} // '<unknown>'),
    ($sp->{sline} // 0),
    ($sp->{scol}  // 0),
    ($sp->{eline} // 0),
    ($sp->{ecol}  // 0),
  );
=======
sub _indent ($n) { return '  ' x $n; }

sub _is_node ($v) {
  return defined($v) && ref($v) eq 'HASH' && exists $v->{kind};
}

sub _pp_scalar ($v) {
  return 'null' if !defined $v;
  return $v if $v =~ /\A-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\z/;
  my $s = "$v";
  $s =~ s/\\/\\\\/g;
  $s =~ s/\n/\\n/g;
  $s =~ s/\r/\\r/g;
  $s =~ s/\t/\\t/g;
  $s =~ s/"/\\"/g;
  return '"' . $s . '"';
>>>>>>> 4b558b9 (add Core IR spec, ast + lower tooling, and tests)
}

sub _pp_value ($v, $lvl) {
  my $pad = _indent($lvl);

<<<<<<< HEAD
  if (!defined $v) {
    return $pad . "null";
  }

  if (!ref($v)) {
    # Quote strings with escapes; keep numbers bare.
    if ($v =~ /\A-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\z/) {
      return $pad . $v;
    }
    my $s = $v;
    $s =~ s/\\/\\\\/g;
    $s =~ s/\n/\\n/g;
    $s =~ s/\r/\\r/g;
    $s =~ s/\t/\\t/g;
    $s =~ s/\"/\\\"/g;
    return $pad . '"' . $s . '"';
  }

  if (ref($v) eq 'ARRAY') {
    return $pad . "[]" if !@$v;
    my @lines;
    push @lines, $pad . "[";
    for my $elem (@$v) {
      push @lines, _pp_value($elem, $lvl + 1);
    }
    push @lines, $pad . "]";
    return join("\n", @lines);
  }

  if (_is_node($v)) {
    return _pp_node($v, $lvl);
  }

  if (_is_span($v)) {
    return $pad . '(Span ' . _span_str($v) . ')';
  }

  if (ref($v) eq 'HASH') {
    my @keys = sort keys %$v;
    return $pad . "{}" if !@keys;
    my @lines;
    push @lines, $pad . "{";
    for my $k (@keys) {
      push @lines, _indent($lvl + 1) . "$k: " . _pp_inline($v->{$k}, $lvl + 1);
    }
    push @lines, $pad . "}";
    return join("\n", @lines);
  }

  return $pad . "<unknown>";
}

sub _pp_inline ($v, $lvl) {
  # Inline small scalars, otherwise put value on next lines.
  return 'null' if !defined $v;
  return $v if !ref($v) && $v =~ /\A-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\z/;
  return $v if !ref($v) && $v =~ /\A[A-Za-z0-9_:\/\.\-]+\z/; # safe-ish
  my $s = _pp_value($v, $lvl);
  $s =~ s/^\s+//;
  return $s;
}

sub _field_order ($node) {
  my @preferred = qw(
    kind
    span
    name
    vis
    module
    as
    names
    items
    tparams
    variants
    fields
    params
    ret
    body
    stmts
    cond
    then
    else
    expr
    whens
    pat
    bind
    sigil
    type
    init
    lhs
    rhs
    op
    callee
    args
    value
    text
    _exhaustive
    _type
  );

  my %has = map { ($_ => 1) } keys %$node;
  my @out;

  for my $k (@preferred) {
    push @out, $k if $has{$k};
    delete $has{$k};
  }

  # Remaining keys: stable sort, but put annotation-ish keys (leading '_') last.
  my @rest = sort keys %has;
  my @non_anno = grep { $_ !~ /^_/ } @rest;
  my @anno     = grep { $_ =~ /^_/ } @rest;
  push @out, @non_anno, @anno;
  return @out;
}

sub _pp_node ($n, $lvl) {
  my $pad = _indent($lvl);
  my $kind = $n->{kind} // '<node>';

  my @lines;
  push @lines, $pad . "($kind";

  # Span on its own line, always near the top.
  if (my $sp = $n->{span}) {
    push @lines, _indent($lvl + 1) . "span: " . _span_str($sp);
  }

  for my $k (_field_order($n)) {
    next if $k eq 'kind' || $k eq 'span';
    next if !exists $n->{$k};
    my $v = $n->{$k};

    if (!ref($v)) {
      push @lines, _indent($lvl + 1) . "$k: " . _pp_inline($v, $lvl + 1);
      next;
    }

    # Complex values: newline then indented block.
    my $pp = _pp_value($v, $lvl + 2);
    my @pp = split /\n/, $pp;
    push @lines, _indent($lvl + 1) . "$k:";
    push @lines, @pp;
  }

  push @lines, $pad . ")";
  return join("\n", @lines);
}

1;

__END__

=pod

=head1 NAME

Hax::ASTDump - developer-facing AST dump for debugging

=head1 SYNOPSIS

  use Hax::ASTDump ();

  my $text = Hax::ASTDump::dump($checked_ast,
    mode     => 'library',
    root     => $path,
    std_root => $std_dir,
    include  => \@include_dirs,
  );
  print $text;

=head1 DESCRIPTION

This module renders a deterministic, human-readable dump of the compiler's
checked AST for use in debugging and tests.

=head1 STABILITY

The dump format is B<not> a stable public interface. It may change at any time
to reflect internal compiler needs.

=cut
=======
  if (!defined $v || !ref($v)) {
    return $pad . _pp_scalar($v);
  }

  if (ref($v) eq 'ARRAY') {
    return _pp_array($v, $lvl);
  }

  if (ref($v) eq 'HASH') {
    return _pp_node($v, $lvl) if _is_node($v);
    return _pp_hash($v, $lvl);
  }

  return $pad . _pp_scalar(ref($v));
}

sub _pp_array ($a, $lvl) {
  my $pad = _indent($lvl);
  return $pad . '[]' if !@$a;

  my @out;
  push @out, $pad . '[';
  for my $it (@$a) {
    push @out, _pp_value($it, $lvl + 1);
  }
  push @out, $pad . ']';
  return join("\n", @out);
}

sub _pp_hash ($h, $lvl) {
  my $pad = _indent($lvl);
  my @k = sort keys %$h;
  return $pad . '{}' if !@k;

  my @out;
  push @out, $pad . '{';
  for my $k (@k) {
    push @out, $pad . '  ' . $k . ': ' . _pp_value($h->{$k}, 0);
  }
  push @out, $pad . '}';
  return join("\n", @out);
}

sub _pp_node ($n, $lvl) {
  my $pad  = _indent($lvl);
  my $kind = $n->{kind} // 'Unknown';

  my @keys;
  if (exists $FIELD_ORDER{$kind}) {
    @keys = @{ $FIELD_ORDER{$kind} };
  } else {
    @keys = grep { $_ ne 'kind' } sort keys %$n;
  }

  my @out;
  push @out, $pad . '(' . $kind;

  for my $k (@keys) {
    next if $k eq 'kind';
    next if !exists $n->{$k};

    my $v = $n->{$k};

    if (ref($v) eq 'ARRAY') {
      push @out, $pad . '  ' . $k . ':';
      push @out, _pp_array($v, $lvl + 2);
      next;
    }

    if (_is_node($v)) {
      push @out, $pad . '  ' . $k . ':';
      push @out, _pp_node($v, $lvl + 2);
      next;
    }

    push @out, $pad . '  ' . $k . ': ' . _pp_value($v, 0);
  }

  push @out, $pad . ')';
  return join("\n", @out);
}

1;
>>>>>>> 4b558b9 (add Core IR spec, ast + lower tooling, and tests)
