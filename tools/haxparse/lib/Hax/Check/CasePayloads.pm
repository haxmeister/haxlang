package Hax::Check::CasePayloads;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.001';

# Enforce: case arm payload binders must match the matched enum variant arity.
#
# This is an incremental v0.1 rule that deliberately avoids a full type system:
# - We only check arity when we can confidently identify the scrutinee's enum
#   type from explicit annotations (sub params / var decls).
# - We do not yet type-check the payload binder types.
# - We support imported enums by parsing modules on-demand (with a shallow scan
#   fallback) using the same module->path logic as other checkers.

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

  # Cache: "ModulePath::EnumName" -> { tparams=>[...], variants=>{ V=>{fields=>[...]}, ... } }
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
    my $t = $p->{type};
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
      my $tb = $st->{type};
      $env->{$vk} = $tb if defined $tb;

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

      # Walk arms too.
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
  my $scrut = $case->{expr};
  return unless ref($scrut) eq 'HASH';
  return unless ($scrut->{kind} // '') eq 'Var';

  my $vk = _var_key($scrut);
  my $t  = $env->{$vk};
  return unless ref($t) eq 'HASH';

  my ($base, $args) = _enum_base_and_args($t);
  return unless defined $base && length $base;

  my ($enum_mod, $enum_name) = _resolve_enum_type($base, $alias_to_mod);
  return unless defined $enum_name;

  my $info = _load_enum_info($enum_mod, $enum_name, $mod_ast, $std_root, $enum_cache);
  return unless $info && ref($info->{variants}) eq 'HASH';

  my %tparam_map;
  if (ref($info->{tparams}) eq 'ARRAY' && ref($args) eq 'ARRAY') {
    my $n = @{ $info->{tparams} };
    for (my $i = 0; $i < $n; $i++) {
      my $tp = $info->{tparams}[$i];
      my $av = $args->[$i];
      $tparam_map{$tp} = $av if defined $tp && ref($av) eq 'HASH';
    }
  }

  for my $w (@{ $case->{whens} // [] }) {
    next unless ref($w) eq 'HASH';

    my $p = $w->{pat};
    next unless ref($p) eq 'HASH' && ($p->{kind} // '') eq 'PatternVariant';

    my $vn = $p->{name};
    next unless defined $vn && length $vn;
    next unless exists $info->{variants}{$vn};

    my $fields = $info->{variants}{$vn}{fields} // [];
    $fields = [] unless ref($fields) eq 'ARRAY';

    my $expect = scalar(@$fields);
    my $got = _pat_arity($p);

    if ($got != $expect) {
      push @$errs, _mk_err($p, "case arm for variant $vn expects $expect payload binder(s), got $got");
      next;
    }

    # Type check payload binder annotations (explicit only).
    my $binds = _pat_binds($p);
    for (my $i = 0; $i < @$binds; $i++) {
      my $b = $binds->[$i];
      next unless ref($b) eq 'HASH' && ($b->{kind} // '') eq 'PatBind';
      my $want_t = $fields->[$i]{type};
      next unless ref($want_t) eq 'HASH';

      $want_t = _subst_type($want_t, \%tparam_map) if %tparam_map;

      # If the binder omits an explicit type, infer it from the matched enum
      # variant payload type. This keeps the rest of the pipeline (ExprTypes)
      # from treating the binder variable as undefined.
      if (!ref($b->{type}) || ref($b->{type}) ne 'HASH') {
        $b->{type} = $want_t;
        next;
      }

      my $want = _type_sig($want_t);
      my $got  = _type_sig($b->{type});
      next if $want eq $got;

      push @$errs, _mk_err($b, "case arm for variant $vn payload binder type mismatch: expected $want, got $got");
    }
  }
}

sub _pat_arity ($pat) {
  return 0 unless ref($pat) eq 'HASH';
  if ($pat->{binds} && ref($pat->{binds}) eq 'ARRAY') {
    return scalar @{ $pat->{binds} };
  }
  return $pat->{bind} ? 1 : 0;
}
sub _pat_binds ($pat) {
  return [] unless ref($pat) eq 'HASH';
  return $pat->{binds} if ref($pat->{binds}) eq 'ARRAY';
  return [ $pat->{bind} ] if $pat->{bind};
  return [];
}


sub _resolve_enum_type ($type_base, $alias_to_mod) {
  my @parts = split /::/, $type_base;
  if (@parts >= 2 && exists $alias_to_mod->{ $parts[0] }) {
    return ($alias_to_mod->{ $parts[0] }, $parts[1]);
  }
  if (@parts == 1) {
    return (undef, $parts[0]);
  }
  return (undef, undef);
}

sub _load_enum_info ($enum_mod, $enum_name, $mod_ast, $std_root, $enum_cache) {
  my $cache_key = ($enum_mod // '<local>') . "::" . $enum_name;
  return $enum_cache->{$cache_key} if exists $enum_cache->{$cache_key};

  my $out;

  if (!defined $enum_mod) {
    for my $it (@{ $mod_ast->{items} // [] }) {
      next unless ref($it) eq 'HASH' && ($it->{kind} // '') eq 'Enum';
      next unless ($it->{name} // '') eq $enum_name;

      my %v;
      for my $vr (@{ $it->{variants} // [] }) {
        next unless ref($vr) eq 'HASH' && ($vr->{kind} // '') eq 'EnumVariant';
        my $vn = $vr->{name} // '';
        next unless length $vn;
        my @fields = map {
          +{ type => (ref($_) eq 'HASH' ? $_->{type} : undef) }
        } @{ $vr->{fields} // [] };
        $v{$vn} = { fields => \@fields };
      }

      $out = {
        tparams  => $it->{tparams} // [],
        variants => \%v,
      };
      last;
    }
  } else {
    my $path = _module_to_path($enum_mod, $std_root);
    if (-f $path) {
      my $ast = _parse_file($path);
      if ($ast && ref($ast) eq 'HASH') {
        for my $it (@{ $ast->{items} // [] }) {
          next unless ref($it) eq 'HASH' && ($it->{kind} // '') eq 'Enum';
          next unless ($it->{name} // '') eq $enum_name;

          my %v;
          for my $vr (@{ $it->{variants} // [] }) {
            next unless ref($vr) eq 'HASH' && ($vr->{kind} // '') eq 'EnumVariant';
            my $vn = $vr->{name} // '';
            next unless length $vn;
            my @fields = map {
              +{ type => (ref($_) eq 'HASH' ? $_->{type} : undef) }
            } @{ $vr->{fields} // [] };
            $v{$vn} = { fields => \@fields };
          }

          $out = {
            tparams  => $it->{tparams} // [],
            variants => \%v,
          };
          last;
        }
      }

      if (!$out || ref($out->{variants}) ne 'HASH' || !%{ $out->{variants} }) {
        $out = _scan_enum_info($path, $enum_name);
      }
    }
  }

  $out //= { tparams => [], variants => {} };
  $enum_cache->{$cache_key} = $out;
  return $out;
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

sub _scan_enum_arity ($path, $enum_name) {
  # Shallow scan for enum variants and their payload arity.
  my %out;

  open(my $fh, '<:encoding(UTF-8)', $path) or return {};

  my $in = 0;
  while (my $line = <$fh>) {
    if (!$in) {
      if ($line =~ /^\s*(?:pub\s+)?enum\s+\Q$enum_name\E\b/) {
        $in = ($line =~ /\{/) ? 2 : 1;
      }
      next;
    }

    if ($in == 1) {
      if ($line =~ /\{/) {
        $in = 2;
      }
      next;
    }

    last if $line =~ /^\s*\}/;
    next if $line =~ /^\s*$/;
    next if $line =~ /^\s*--/;

    # Variant;
    if ($line =~ /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*;\s*$/) {
      $out{$1} = 0;
      next;
    }

    # Variant(...);
    if ($line =~ /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\((.*)\)\s*;\s*$/) {
      my ($name, $inner) = ($1, $2);
      $inner =~ s/^\s+|\s+$//g;
      if (!length $inner) {
        $out{$name} = 0;
      } else {
        my $n = 1 + (() = ($inner =~ /,/g));
        $out{$name} = $n;
      }
      next;
    }
  }

  close $fh;
  return \%out;
}

sub _scan_enum_info ($path, $enum_name) {
  # Fallback scanner used when we cannot fully parse/import the enum AST.
  # Returns a structure compatible with _get_enum_info():
  #   { tparams => [...], variants => { Name => { fields => [ {type=>...}, ... ] } } }
  #
  # Types are unknown in this fallback; we only recover payload arity so
  # case binder checks can proceed without crashing.

  my $arity = _scan_enum_arity($path, $enum_name);
  my %v;
  for my $vn (keys %$arity) {
    my $n = $arity->{$vn} // 0;
    $v{$vn} = { fields => [ map { +{ type => undef } } (1..$n) ] };
  }

  return { tparams => [], variants => \%v };
}


sub _var_key ($node) {
  my $sigil = $node->{sigil} // '';
  my $name  = $node->{name}  // '';
  return $sigil . $name;
}


sub _type_sig ($t) {
  return '<unknown>' unless ref($t) eq 'HASH';
  my $k = $t->{kind} // '';
  if ($k eq 'TypeName') {
    return $t->{name} // '<anon>';
  }
  if ($k eq 'TypeApply') {
    my $b = $t->{base} // '<anon>';
    my @a = map { _type_sig($_) } @{ $t->{args} // [] };
    return $b . '[' . join(',', @a) . ']';
  }
  if ($k eq 'TypeArray') {
    return '[' . _type_sig($t->{elem}) . ']';
  }
  if ($k eq 'TypeHash') {
    return '{' . _type_sig($t->{key}) . ':' . _type_sig($t->{val}) . '}';
  }
  return '<unknown>';
}

sub _enum_base_and_args ($t) {
  return (undef, undef) unless ref($t) eq 'HASH';
  my $k = $t->{kind} // '';
  return ($t->{name}, []) if $k eq 'TypeName';
  return ($t->{base}, ($t->{args} // [])) if $k eq 'TypeApply';
  return (undef, undef);
}

sub _subst_type ($t, $map) {
  return $t unless ref($t) eq 'HASH' && ref($map) eq 'HASH' && %$map;
  my $k = $t->{kind} // '';
  if ($k eq 'TypeName') {
    my $n = $t->{name};
    return $map->{$n} if defined $n && exists $map->{$n};
    return $t;
  }
  if ($k eq 'TypeApply') {
    my @na = map { _subst_type($_, $map) } @{ $t->{args} // [] };
    return { %$t, args => \@na };
  }
  if ($k eq 'TypeArray') {
    return { %$t, elem => _subst_type($t->{elem}, $map) };
  }
  if ($k eq 'TypeHash') {
    return { %$t, key => _subst_type($t->{key}, $map), val => _subst_type($t->{val}, $map) };
  }
  return $t;
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

Hax::Check::CasePayloads - Enforce enum payload binder arity in C<case> patterns

=head1 SYNOPSIS

  use Hax::Check::CasePayloads;
  my @errs = Hax::Check::CasePayloads::check_module($ast);

=head1 DESCRIPTION

This checker enforces an incremental Hax v0.1 rule:

  enum Opt { Some(Int $n); None; }

  case ($x) {
    when Some(Int $n) { ... }   # ok
    when None(Int $n) { ... }   # error (unit variant)
  }

When the scrutinee's enum type can be identified from explicit annotations,
then each C<when> arm that matches a known variant must provide exactly as many
payload binders as the enum variant declares.

This checker:

=over 4

=item * Uses a minimal local type environment from explicit sub parameters and
C<var> declarations.

=item * Resolves imported enums by parsing modules on-demand (AST-first) with a
shallow scan fallback.

=item * Does not yet type-check payload binder types (only binder count).

=back

=head1 AUTHOR

Hax project contributors.

=head1 LICENSE

Same terms as the Hax project.

=cut
