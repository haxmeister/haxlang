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
    my $op = $n->{op} // '';

    # '=' is regular assignment.
    # ':=' is the *binding* operator and is only valid for reference variables (sigil '^').
    return if $op ne '=' && $op ne ':=';

    my $lhs = $n->{lhs};
    my $rhs = $n->{rhs};

    # Only support var LHS in slice 1.
    if (!$lhs || ref($lhs) ne 'HASH' || ($lhs->{kind} // '') ne 'Var') {
      _err($errs, $n, "assignment lhs must be a variable");
      return;
    }

    if ($op eq ':=' && ($lhs->{sigil} // '') ne '^') {
      _err($errs, $n, "binding operator ':=' is only allowed for reference variables (^name)");
      return;
    }

    my $lhs_t = _env_lookup($env, $lhs->{sigil}, $lhs->{name});
    if (!$lhs_t) {
      _err($errs, $lhs, "undefined variable $lhs->{sigil}$lhs->{name}");
      return;
    }

    my $rhs_t = _infer_expr_type($rhs, $env, $subs, $errs);
    _check_assign_compat($n, $lhs_t, $rhs_t, $errs, "assignment");
    return;
  }


  if ($k eq 'Return') {
    if (!defined $n->{expr}) {
      if (!_type_is_void($ret_type)) {
        _err($errs, $n, "bare return in non-Void function");
      }
      return;
    }

    my $expr_t = _infer_expr_type($n->{expr}, $env, $subs, $errs);
    if (_type_is_void($ret_type)) {
      _err($errs, $n, "return with value in Void function");
      return;
    }
    _check_assign_compat($n, $ret_type, $expr_t, $errs, "return");
    return;
  }

  if ($k eq 'If') {
    my $cond_t = _infer_expr_type($n->{cond}, $env, $subs, $errs);
    if ($cond_t && !_is_bool_type($cond_t)) {
      _err($errs, $n->{cond}, "if condition must be Bool, got " . _type_str($cond_t));
    }
    _walk_block($n->{then}, $env, $subs, $errs, $ret_type);
    _walk_block($n->{else}, $env, $subs, $errs, $ret_type) if $n->{else};
    return;
  }

  if ($k eq 'While') {
    my $cond_t = _infer_expr_type($n->{cond}, $env, $subs, $errs);
    if ($cond_t && !_is_bool_type($cond_t)) {
      _err($errs, $n->{cond}, "while condition must be Bool, got " . _type_str($cond_t));
    }
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
  my $op  = $n->{op}  // '';
  my $lhs = $n->{lhs};
  my $rhs = $n->{rhs};

  # Logical ops (keywords)
  if ($op eq 'and' || $op eq 'or') {
    my $lt = _infer_expr_type($lhs, $env, $subs, $errs);
    my $rt = _infer_expr_type($rhs, $env, $subs, $errs);
    if ($lt && !_type_eq($lt, { kind => 'TypeName', name => 'Bool' })) {
      _err($errs, $lhs, "'$op' operand must be Bool");
    }
    if ($rt && !_type_eq($rt, { kind => 'TypeName', name => 'Bool' })) {
      _err($errs, $rhs, "'$op' operand must be Bool");
    }
    return { kind => 'TypeName', name => 'Bool' };
  }

  # Comparisons
  if ($op =~ /^(==|!=|<|<=|>|>=)$/) {
    my $lt = _infer_expr_type($lhs, $env, $subs, $errs);
    my $rt = _infer_expr_type($rhs, $env, $subs, $errs);

    # No inference: only check if both operand types are known.
    if ($lt && $rt) {
      if (!_type_eq($lt, $rt)) {
        _err($errs, $n, "cannot compare "._type_str($lt)." $op "._type_str($rt));
      } elsif ($op =~ /^(<|<=|>|>=)$/) {
        my $tn = _type_str($lt);
        if (!_is_int_type($lt) && $tn ne 'Float') {
          _err($errs, $n, "ordering comparison not supported for type $tn");
        }
      }
    }

    return { kind => 'TypeName', name => 'Bool' };
  }

  # Numeric operators
  if ($op =~ /^(\+|-|\*|\/|%)$/) {
    my $lt = _infer_expr_type($lhs, $env, $subs, $errs);
    my $rt = _infer_expr_type($rhs, $env, $subs, $errs);

    # No inference: only check if both operand types are known.
    return undef if !$lt || !$rt;

    if (!_type_eq($lt, $rt)) {
      _err($errs, $n, "cannot apply '$op' to "._type_str($lt)." and "._type_str($rt));
      return undef;
    }

    my $tn = _type_str($lt);
    if (_is_int_type($lt)) {
      return $lt;
    }

    if ($tn eq 'Float') {
      if ($op eq '%') {
        _err($errs, $n, "operator '%' not supported for type Float");
        return undef;
      }
      return $lt;
    }

    _err($errs, $n, "operator '$op' not supported for type $tn");
    return undef;
  }

  return undef;
}

if ($k eq 'Unary') {
  my $op = $n->{op} // '';
  if ($op eq 'not') {
    my $inner = $n->{expr};
    my $it = _infer_expr_type($inner, $env, $subs, $errs);
    if ($it && !_type_eq($it, { kind => 'TypeName', name => 'Bool' })) {
      _err($errs, $inner, "'not' operand must be Bool");
    }
    return { kind => 'TypeName', name => 'Bool' };
  }

  if ($op eq '-') {
    my $inner = $n->{expr};
    my $it = _infer_expr_type($inner, $env, $subs, $errs);
    return undef if !$it;

    my $tn = _type_str($it);
    return $it if _is_int_type($it) || $tn eq 'Float';

    _err($errs, $inner, "unary '-' operand must be an integer or Float");
    return undef;
  }
  return undef;
}

  if ($k eq 'LitBool') { return { kind => 'TypeName', name => 'Bool' }; }
  if ($k eq 'LitInt')  { return { kind => 'TypeName', name => 'int'  }; }
  if ($k eq 'LitFloat'){ return { kind => 'TypeName', name => 'Float'}; }
  if ($k eq 'LitStr')  { return { kind => 'TypeName', name => 'Str'  }; }

  if ($k eq 'Block') {
    _walk_block($n, $env, $subs, $errs, undef);
    return undef;
  }

  # Recurse where sensible
  if ($k eq 'If') {
    my $cond_t = _infer_expr_type($n->{cond}, $env, $subs, $errs);
    if ($cond_t && !_is_bool_type($cond_t)) {
      _err($errs, $n->{cond}, "if condition must be Bool, got " . _type_str($cond_t));
    }
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

sub _canon_type_name ($name) {
  return 'int' if defined($name) && $name eq 'Int'; # legacy alias
  return $name;
}

sub _is_bool_type ($t) {
  return 0 if !$t || ref($t) ne 'HASH';
  return 0 if ($t->{kind} // '') ne 'TypeName';
  my $n = _canon_type_name($t->{name});
  return 1 if defined($n) && $n eq 'Bool';
  return 0;
}

sub _type_is_void ($t) {
  return 1 if !$t || ref($t) ne 'HASH';
  my $k = $t->{kind} // '';
  return 0 unless $k eq 'TypeName';
  my $name = $t->{name} // '';
  return 1 if $name eq 'Void';
  return 1 if $name eq 'Unit';
  return 0;
}


sub _is_int_type ($t) {
  return 0 if !$t || ref($t) ne 'HASH';
  return 0 if ($t->{kind} // '') ne 'TypeName';
  my $n = _canon_type_name($t->{name});
  return 1 if $n eq 'int'  || $n eq 'uint';
  return 1 if $n =~ /^int(8|16|32|64)$/;
  return 1 if $n =~ /^uint(8|16|32|64)$/;
  return 0;
}

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
