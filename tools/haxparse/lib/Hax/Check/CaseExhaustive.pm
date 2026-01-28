package Hax::Check::CaseExhaustive;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.001';

# Enforce: case-over-enum must be exhaustive (v0.1 incremental).
#
# This checker is intentionally small and "front-end first":
# - We only attempt exhaustiveness when we can confidently identify the
#   scrutinee's enum type.
# - We treat `else { ... }` as a wildcard arm.
# - We do NOT yet typecheck payload binders.
# - We support stdlib enums by parsing imported modules on-demand.

use Hax::Lexer;
use Hax::Parser;

sub check_module ($mod_ast, %opts) {
  my $std_root = $opts{std_root} // 'std';

  my @errs;

  # alias -> module (from: import X as Alias;)
  my %alias_to_mod;
  for my $it (@{ $mod_ast->{items} // [] }) {
    next unless ref($it) eq 'HASH';
    next unless ($it->{kind} // '') eq 'Import';
    next unless defined($it->{as}) && length($it->{as});
    $alias_to_mod{ $it->{as} } = $it->{module};
  }

  # Cache: "ModulePath::EnumName" -> { variants => {Name=>1,...} }
  my %enum_cache;

  for my $it (@{ $mod_ast->{items} // [] }) {
    next unless ref($it) eq 'HASH';
    next unless ($it->{kind} // '') eq 'Sub';
    _check_sub($it, $mod_ast, \%alias_to_mod, $std_root, \%enum_cache, \@errs);
  }

  return @errs;
}

sub _check_sub ($sub, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs) {
  # Very small local type env: sigil+name -> enum-base string
  my %env;

  for my $p (@{ $sub->{params} // [] }) {
    next unless ref($p) eq 'HASH' && ($p->{kind} // '') eq 'Param';
    my $k = _var_key($p);
    my $t = _type_base($p->{type});
    $env{$k} = $t if defined $t;
  }

  _walk_block($sub->{body}, \%env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs);
}

sub _walk_block ($blk, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs) {
  return unless ref($blk) eq 'HASH' && ($blk->{kind} // '') eq 'Block';
  for my $st (@{ $blk->{stmts} // [] }) {
    next unless ref($st) eq 'HASH';
    my $k = $st->{kind} // '';

    if ($k eq 'VarDecl') {
      my $vk = _var_key($st);
      my $tb = _type_base($st->{type});
      $env->{$vk} = $tb if defined $tb;

      # also walk initializer for nested cases
      _walk_expr($st->{init}, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs) if $st->{init};
      next;
    }

    if ($k eq 'If') {
      _walk_expr($st->{cond}, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs);
      _walk_block($st->{then}, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs);
      _walk_block($st->{else}, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs) if $st->{else};
      next;
    }

    if ($k eq 'Case') {
      _check_case($st, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs);

      # Walk arms too
      for my $w (@{ $st->{whens} // [] }) {
        _walk_block($w->{body}, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs) if ref($w) eq 'HASH';
      }
      _walk_block($st->{else}, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs) if $st->{else};
      next;
    }

    if ($k eq 'Return') {
      _walk_expr($st->{expr}, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs) if $st->{expr};
      next;
    }

    if ($k eq 'Assign') {
      _walk_expr($st->{lhs}, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs);
      _walk_expr($st->{rhs}, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs);
      next;
    }

    if ($k eq 'ExprStmt') {
      _walk_expr($st->{expr}, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs);
      next;
    }
  }
}

sub _walk_expr ($e, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs) {
  return unless ref($e) eq 'HASH';
  my $k = $e->{kind} // '';

  if ($k eq 'Call') {
    _walk_expr($e->{callee}, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs);
    _walk_expr($_, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs) for @{ $e->{args} // [] };
    return;
  }

  if ($k eq 'BinOp') {
    _walk_expr($e->{lhs}, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs);
    _walk_expr($e->{rhs}, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs);
    return;
  }

  if ($k eq 'Unary') {
    _walk_expr($e->{expr}, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs);
    return;
  }
}

sub _check_case ($case, $env, $mod_ast, $alias_to_mod, $std_root, $enum_cache, $errs) {
  # If there's an else arm, we consider it exhaustive for now.
  return if $case->{else};

  my $scrut = $case->{expr};
  return unless ref($scrut) eq 'HASH';
  return unless ($scrut->{kind} // '') eq 'Var';

  my $vk = _var_key($scrut);
  my $tb = $env->{$vk};
  return unless defined $tb && length $tb;

  my ($enum_mod, $enum_name) = _resolve_enum_type($tb, $alias_to_mod);
  return unless defined $enum_name;

  my $variants = _load_enum_variants($enum_mod, $enum_name, $mod_ast, $std_root, $enum_cache);
  return unless $variants && %$variants;

  my %seen;
  for my $w (@{ $case->{whens} // [] }) {
    next unless ref($w) eq 'HASH' && ($w->{kind} // '') eq 'When';
    my $p = $w->{pat};
    next unless ref($p) eq 'HASH' && ($p->{kind} // '') eq 'PatternVariant';
    my $vn = $p->{name};
    $seen{$vn} = 1 if defined $vn;
  }

  my @missing = sort grep { !$seen{$_} } keys %$variants;
  return if !@missing;

  push @$errs, _mk_err($case, "case over enum must be exhaustive (missing: " . join(', ', @missing) . ")");
}

sub _resolve_enum_type ($type_base, $alias_to_mod) {
  # Type base is a string like:
  #   "Option::Option" (imported module aliased to Option, enum Option)
  #   "MyEnum" (local)
  my @parts = split /::/, $type_base;
  if (@parts >= 2 && exists $alias_to_mod->{ $parts[0] }) {
    return ($alias_to_mod->{ $parts[0] }, $parts[1]);
  }
  if (@parts == 1) {
    return (undef, $parts[0]);
  }
  # Not handled yet (fully-qualified without alias, nested, etc.)
  return (undef, undef);
}

sub _load_enum_variants ($enum_mod, $enum_name, $mod_ast, $std_root, $enum_cache) {
  my $cache_key = ($enum_mod // '<local>') . "::" . $enum_name;
  return $enum_cache->{$cache_key} if exists $enum_cache->{$cache_key};

  my $variants;

  if (!defined $enum_mod) {
    # Local enum in this module
    for my $it (@{ $mod_ast->{items} // [] }) {
      next unless ref($it) eq 'HASH' && ($it->{kind} // '') eq 'Enum';
      next unless ($it->{name} // '') eq $enum_name;
      $variants = { map { ($_->{name} // '') => 1 } @{ $it->{variants} // [] } };
      last;
    }
  } else {
    my $path = _module_to_path($enum_mod, $std_root);
    if (-f $path) {
      # Prefer a real parse (when possible), but stdlib may use syntax that
      # the current front-end does not parse yet (e.g. enum payload binder
      # names without sigils). In that case, fall back to a shallow scan.
      my $ast = _parse_file($path);
      if ($ast && ref($ast) eq 'HASH') {
        for my $it (@{ $ast->{items} // [] }) {
          next unless ref($it) eq 'HASH' && ($it->{kind} // '') eq 'Enum';
          next unless ($it->{name} // '') eq $enum_name;
          $variants = { map { ($_->{name} // '') => 1 } @{ $it->{variants} // [] } };
          last;
        }
      }

      if (!$variants || !%$variants) {
        $variants = _scan_enum_variants($path, $enum_name);
      }
    }
  }

  $variants //= {};
  $enum_cache->{$cache_key} = $variants;
  return $variants;
}

sub _module_to_path ($mod, $std_root) {
  my $rel = $mod;
  $rel =~ s{::}{/}g;
  my $std_path = "$std_root/$rel.hax";
  return -f $std_path ? $std_path : "$rel.hax";
}

sub _parse_file ($path) {
  open(my $fh, '<:encoding(UTF-8)', $path) or return undef;
  my $src = do { local $/; <$fh> };
  close $fh;
  my $lex = Hax::Lexer->new(file => $path, src => $src);
  my $p   = Hax::Parser->new(lexer => $lex);
  my $ast;
  eval { $ast = $p->parse; 1 } or return undef;
  return $ast;
}

sub _scan_enum_variants ($path, $enum_name) {
  # Shallow scan for enum variants:
  #   pub enum Name[...] {
  #     None;
  #     Some(T value);
  #   }
  my %out;

  open(my $fh, '<:encoding(UTF-8)', $path) or return {};

  my $in = 0;
  while (my $line = <$fh>) {
    if (!$in) {
      # Enter the enum block for the name.
      if ($line =~ /^\s*(?:pub\s+)?enum\s+\Q$enum_name\E\b/) {
        # The opening brace may be on the same line as the enum header.
        $in = ($line =~ /\{/) ? 2 : 1;
      }
      next;
    }

    # Wait until we see the opening brace.
    if ($in == 1) {
      if ($line =~ /\{/) {
        $in = 2;
      }
      next;
    }

    # Inside braces.
    last if $line =~ /^\s*\}/;
    next if $line =~ /^\s*$/;
    next if $line =~ /^\s*--/;  # comment fence or comment line

    if ($line =~ /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|;)/) {
      $out{$1} = 1;
    }
  }

  close $fh;
  return \%out;
}

sub _type_base ($t) {
  return undef unless ref($t) eq 'HASH';
  my $k = $t->{kind} // '';
  return $t->{name} if $k eq 'TypeName';
  return $t->{base} if $k eq 'TypeApply';
  return undef;
}

sub _var_key ($node) {
  my $sigil = $node->{sigil} // '';
  my $name  = $node->{name}  // '';
  return $sigil . $name;
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

Hax::Check::CaseExhaustive - Enforce enum exhaustiveness for C<case>

=head1 SYNOPSIS

  use Hax::Check::CaseExhaustive;
  my @errs = Hax::Check::CaseExhaustive::check_module($ast);

=head1 DESCRIPTION

This checker enforces an incremental Hax v0.1 rule:

  case ($x) {
    when Some(Int $n) { ... }
  }

If the scrutinee C<$x> is a known enum type and the C<case> has no C<else>
arm, then the set of C<when> variants must cover all enum variants.

This checker:

=over 4

=item * Uses a minimal local type environment from explicit C<var> and
sub parameter declarations.

=item * Treats C<else { ... }> as a wildcard arm.

=item * Optionally parses stdlib modules on-demand to discover enum variants
for imported enums.

=item * Does not yet typecheck payload binders.

=back

=head1 AUTHOR

Hax project contributors.

=head1 LICENSE

Same terms as the Hax project.

=cut
