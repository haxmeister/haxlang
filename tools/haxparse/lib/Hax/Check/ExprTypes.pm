package Hax::Check::ExprTypes;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.001';

# ExprTypes (slice 1)
#
# Goals:
# - No inference. Only check what we can prove from explicit annotations / known literals.
# - Local-only: only checks calls to locally-declared subs (same module AST).
# - Uses a simple lexical environment (stack) of known variable types:
#     * params
#     * var decls
#     * case pattern binders (PatternVariant bind)
#
# Enforces (when types are known):
# - var init type matches declared var type
# - := assignment type matches declared var type
# - return expr type matches declared return type
# - call arity matches
# - call arg types match param types (only when arg type is known)

sub check_module ($ast, %opts) {
  my @errs;

  my $subs = _collect_sub_sigs($ast);

  # Walk each sub body with its own env.
  for my $item (@{ $ast->{items} // [] }) {
    next if !$item || ref($item) ne 'HASH';
    next if ($item->{kind} // '') ne 'Sub';

    my $env = _env_new();
    for my $p (@{ $item->{params} // [] }) {
      _env_bind($env, $p->{sigil}, $p->{name}, $p->{type});
    }

    _walk_block($item->{body}, $env, $subs, \@errs, $item->{ret});
  }

  return @errs;
}

# -----------------------
# Sub signature collection
# -----------------------

sub _collect_sub_sigs ($ast) {
  my %subs;
  for my $it (@{ $ast->{items} // [] }) {
    next if !$it || ref($it) ne 'HASH';
    next if ($it->{kind} // '') ne 'Sub';
    my $name = $it->{name} // next;
    my @params = map { $_->{type} } @{ $it->{params} // [] };
    $subs{$name} = {
      params => \@params,
      ret    => $it->{ret},
      node   => $it,
    };
  }
  return \%subs;
}

# -------------
# Env primitives
# -------------

sub _env_new () { return [ {} ]; }

sub _env_push ($env) { push @$env, {}; }

sub _env_pop ($env)  { pop @$env; }

sub _env_key ($sigil, $name) { return ($sigil // '') . ($name // ''); }

sub _env_bind ($env, $sigil, $name, $type) {
  return if !$sigil || !$name;
  $env->[-1]{ _env_key($sigil, $name) } = $type;
}

sub _env_lookup ($env, $sigil, $name) {
  my $k = _env_key($sigil, $name);
  for (my $i = $#$env; $i >= 0; $i--) {
    return $env->[$i]{$k} if exists $env->[$i]{$k};
  }
  return undef;
}

# ----------------
# AST walking
# ----------------

sub _walk_block ($blk, $env, $subs, $errs, $ret_type) {
  return if !$blk || ref($blk) ne 'HASH';
  return if ($blk->{kind} // '') ne 'Block';

  _env_push($env);

  for my $st (@{ $blk->{stmts} // [] }) {
    _walk_stmt($st, $env, $subs, $errs, $ret_type);
  }

  _env_pop($env);
}

sub _walk_stmt ($n, $env, $subs, $errs, $ret_type) {
  return if !$n || ref($n) ne 'HASH';
  my $k = $n->{kind} // '';

  if ($k eq 'VarDecl') {
    _env_bind($env, $n->{sigil}, $n->{name}, $n->{type});
    if ($n->{init}) {
      my $rhs_t = _infer_expr_type($n->{init}, $env, $subs, $errs);
      _check_assign_compat($n, $n->{type}, $rhs_t, $errs, "initializer");
    }
    return;
  }

  if ($k eq 'Assign') {
    # We only enforce := (rebind) for now; '=' may be statement-only depending on your grammar.
    return if ($n->{op} // '') ne ':=';

    my $lhs = $n->{lhs};
    my $rhs = $n->{rhs};

    # Only support var LHS in slice 1.
    if ($lhs && ref($lhs) eq 'HASH' && ($lhs->{kind} // '') eq 'Var') {
      my $lhs_t = _env_lookup($env, $lhs->{sigil}, $lhs->{name});
      my $rhs_t = _infer_expr_type($rhs, $env, $subs, $errs);
      _check_assign_compat($n, $lhs_t, $rhs_t, $errs, "assignment");
    }
    return;
  }

  if ($k eq 'Return') {
    return if !$n->{expr};
    my $expr_t = _infer_expr_type($n->{expr}, $env, $subs, $errs);
    _check_assign_compat($n, $ret_type, $expr_t, $errs, "return");
    return;
  }

  if ($k eq 'If') {
    _infer_expr_type($n->{cond}, $env, $subs, $errs);
    _walk_block($n->{then}, $env, $subs, $errs, $ret_type);
    _walk_block($n->{else}, $env, $subs, $errs, $ret_type) if $n->{else};
    return;
  }

  if ($k eq 'While') {
    _infer_expr_type($n->{cond}, $env, $subs, $errs);
    _walk_block($n->{body}, $env, $subs, $errs, $ret_type);
    return;
  }

  if ($k eq 'Case') {
    _infer_expr_type($n->{expr}, $env, $subs, $errs);

    for my $w (@{ $n->{whens} // [] }) {
      _walk_when($w, $env, $subs, $errs, $ret_type);
    }
    if ($n->{else}) {
      _walk_block($n->{else}, $env, $subs, $errs, $ret_type);
    }
    return;
  }

  # Expression statement
  _infer_expr_type($n, $env, $subs, $errs);
  return;
}

sub _walk_when ($w, $env, $subs, $errs, $ret_type) {
  return if !$w || ref($w) ne 'HASH';
  return if ($w->{kind} // '') ne 'When';

  my $pat = $w->{pat};
  _env_push($env);

  # PatternVariant bind is arm-local
  if ($pat && ref($pat) eq 'HASH' && ($pat->{kind} // '') eq 'PatternVariant') {
    my $b = $pat->{bind};
    if ($b && ref($b) eq 'HASH' && ($b->{kind} // '') eq 'PatBind') {
      _env_bind($env, $b->{sigil}, $b->{name}, $b->{type});
    }
  }

  _walk_block($w->{body}, $env, $subs, $errs, $ret_type);
  _env_pop($env);
}

# ----------------
# Type inference (explicit-only)
# ----------------

sub _infer_expr_type ($n, $env, $subs, $errs) {
  return undef if !$n || ref($n) ne 'HASH';
  my $k = $n->{kind} // '';

  if ($k eq 'Var') {
    my $t = _env_lookup($env, $n->{sigil}, $n->{name});
    if (!$t) {
      _err($errs, $n, "undefined variable $n->{sigil}$n->{name}");
      return undef;
    }
    return $t;
  }

  if ($k eq 'Call') {
    my $callee = $n->{callee};
    # Only support direct name calls in slice 1.
    if ($callee && ref($callee) eq 'HASH' && ($callee->{kind} // '') eq 'Name') {
      my $name = $callee->{name};
      my $sig  = $subs->{$name};
      if ($sig) {
        my $want = scalar @{ $sig->{params} // [] };
        my $got  = scalar @{ $n->{args} // [] };
        if ($want != $got) {
          _err($errs, $n, "call arity mismatch: $name expects $want args, got $got");
        } else {
          for (my $i=0; $i<$want; $i++) {
            my $pt = $sig->{params}[$i];
            my $at = _infer_expr_type($n->{args}[$i], $env, $subs, $errs);
            if ($pt && $at && !_type_eq($pt, $at)) {
              _err($errs, $n->{args}[$i], "call arg type mismatch for $name arg ".($i+1).": expected "._type_str($pt).", got "._type_str($at));
            }
          }
        }
        return $sig->{ret};
      }
    }
    return undef;
  }

  if ($k eq 'BinOp') {
    my $op = $n->{op} // '';
    if ($op =~ /^(==|!=|<|<=|>|>=)$/) {
      return { kind => 'TypeName', name => 'Bool' };
    }
    return undef;
  }

  if ($k eq 'UnOp') {
    return undef;
  }

  if ($k eq 'LitBool') { return { kind => 'TypeName', name => 'Bool' }; }
  if ($k eq 'LitInt')  { return { kind => 'TypeName', name => 'Int'  }; }
  if ($k eq 'LitFloat'){ return { kind => 'TypeName', name => 'Float'}; }
  if ($k eq 'LitStr')  { return { kind => 'TypeName', name => 'Str'  }; }

  if ($k eq 'Block') {
    _walk_block($n, $env, $subs, $errs, undef);
    return undef;
  }

  # Recurse where sensible
  if ($k eq 'If') {
    _infer_expr_type($n->{cond}, $env, $subs, $errs);
    _walk_block($n->{then}, $env, $subs, $errs, undef);
    _walk_block($n->{else}, $env, $subs, $errs, undef) if $n->{else};
    return undef;
  }

  if ($k eq 'Case') {
    _infer_expr_type($n->{expr}, $env, $subs, $errs);
    for my $w (@{ $n->{whens} // [] }) { _walk_when($w, $env, $subs, $errs, undef); }
    _walk_block($n->{else}, $env, $subs, $errs, undef) if $n->{else};
    return undef;
  }

  return undef;
}

# -------------
# Type helpers
# -------------

sub _type_str ($t) {
  return "<unknown>" if !$t || ref($t) ne 'HASH';
  my $k = $t->{kind} // '';
  return $t->{name} if $k eq 'TypeName';
  if ($k eq 'TypeArray') {
    return "[" . _type_str($t->{elem}) . "]";
  }
  if ($k eq 'TypeApply') {
    return $t->{base} . "[" . join(", ", map { _type_str($_) } @{ $t->{args} // [] }) . "]";
  }
  if ($k eq 'TypeHash') {
    return "{" . _type_str($t->{key}) . ":" . _type_str($t->{val}) . "}";
  }
  return "<type>";
}

sub _type_eq ($a, $b) {
  return 0 if !$a || !$b;
  return _type_str($a) eq _type_str($b);
}

sub _check_assign_compat ($node, $lhs_t, $rhs_t, $errs, $what) {
  return if !$lhs_t || !$rhs_t;           # no inference: only check when both known
  return if _type_eq($lhs_t, $rhs_t);
  _err($errs, $node, "$what type mismatch: expected "._type_str($lhs_t).", got "._type_str($rhs_t));
}

# -------------
# Errors
# -------------

sub _err ($errs, $node, $msg) {
  my $sp = $node->{span} // {};
  push @$errs, {
    msg  => $msg,
    file => $sp->{file}  // "<unknown>",
    line => $sp->{sline} // 0,
    col  => $sp->{scol}  // 0,
  };
  return;
}

1;
