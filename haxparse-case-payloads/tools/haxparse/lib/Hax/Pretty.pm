package Hax::Pretty;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.001';

sub dump_ast ($ast, %opt) {
  my $out = '';
  _pp(\$out, $ast, 0, \%opt);
  return $out;
}

sub _indent ($n) { return '  ' x $n; }

sub _line ($outref, $n, $s) {
  $$outref .= _indent($n) . $s . "\n";
}

sub _pp ($outref, $node, $lvl, $opt) {
  if (!defined $node) {
    _line($outref, $lvl, "(undef)");
    return;
  }
  if (ref($node) ne 'HASH') {
    _line($outref, $lvl, "$node");
    return;
  }

  my $k = $node->{kind} // '<?>';
  if ($k eq 'Module') {
    _line($outref, $lvl, "Module $node->{name}");
    for my $it (@{ $node->{items} // [] }) { _pp($outref, $it, $lvl+1, $opt); }
    return;
  }

  if ($k eq 'Import') {
    my $as = defined($node->{as}) ? " as $node->{as}" : "";
    _line($outref, $lvl, "Import $node->{module}$as");
    return;
  }

  if ($k eq 'FromImport') {
    my $names = join(", ", @{ $node->{names} // [] });
    _line($outref, $lvl, "FromImport $node->{module} import $names");
    return;
  }

  if ($k eq 'Sub') {
    my $vis = $node->{vis} ? "$node->{vis} " : "";
    my $ret = _pp_type_inline($node->{ret});
    my $params = join(", ", map { _pp_param_inline($_) } @{ $node->{params} // [] });
    _line($outref, $lvl, "${vis}Sub $node->{name}($params) -> $ret");
    _pp($outref, $node->{body}, $lvl+1, $opt);
    return;
  }

  if ($k eq 'Enum') {
    my $vis = $node->{vis} ? "$node->{vis} " : "";
    my $name = $node->{name} // "<Enum>";
    my $tp = "";
    if (my $tps = $node->{tparams}) {
      $tp = "[" . join(", ", @$tps) . "]" if @$tps;
    }
    _line($outref, $lvl, "${vis}enum ${name}${tp} {");
    for my $v (@{ $node->{variants} // [] }) {
      _pp($outref, $v, $lvl+1, $opt);
    }
    _line($outref, $lvl, "}");
    return;
  }

  if ($k eq 'EnumVariant') {
    my $name = $node->{name} // "<Variant>";
    my @fields = @{ $node->{fields} // [] };
    if (@fields) {
      my $inside = join(", ", map { _pp_enum_field_inline($_) } @fields);
      _line($outref, $lvl, "$name($inside);");
    } else {
      _line($outref, $lvl, "$name;");
    }
    return;
  }



  if ($k eq 'Block') {
    _line($outref, $lvl, "Block");
    for my $st (@{ $node->{stmts} // [] }) { _pp($outref, $st, $lvl+1, $opt); }
    return;
  }

  if ($k eq 'VarDecl') {
    my $stor = defined($node->{storage}) ? "($node->{storage}) " : "";
    my $ref  = $node->{ref} ? "^" : "";
    my $ty   = _pp_type_inline($node->{type});
    my $nm   = "$node->{sigil}$node->{name}";
    my $init = '';
    if (defined $node->{init}) {
      my $op = $node->{op} // '=';
      $init = " $op " . _pp_expr_inline($node->{init});
    }
    _line($outref, $lvl, "Var $stor$ref$ty $nm$init");
    return;
  }

  if ($k eq 'Assign') {
    _line($outref, $lvl, "Assign $node->{op} " . _pp_expr_inline($node->{lhs}) . " = " . _pp_expr_inline($node->{rhs}));
    return;
  }

  if ($k eq 'ExprStmt') {
    _line($outref, $lvl, "Expr " . _pp_expr_inline($node->{expr}));
    return;
  }

  if ($k eq 'Return') {
    if (defined $node->{expr}) {
      _line($outref, $lvl, "Return " . _pp_expr_inline($node->{expr}));
    } else {
      _line($outref, $lvl, "Return");
    }
    return;
  }

  if ($k eq 'If') {
    _line($outref, $lvl, "If " . _pp_expr_inline($node->{cond}));
    _line($outref, $lvl+1, "Then");
    _pp($outref, $node->{then}, $lvl+2, $opt);
    if ($node->{else}) {
      _line($outref, $lvl+1, "Else");
      _pp($outref, $node->{else}, $lvl+2, $opt);
    }
    return;
  }

  if ($k eq 'Case') {
    _line($outref, $lvl, "Case " . _pp_expr_inline($node->{expr}));
    for my $w (@{ $node->{whens} // [] }) { _pp($outref, $w, $lvl+1, $opt); }
    if ($node->{else}) {
      _line($outref, $lvl+1, "Else");
      _pp($outref, $node->{else}, $lvl+2, $opt);
    }
    return;
  }

  if ($k eq 'When') {
    _line($outref, $lvl, "When " . _pp_pat_inline($node->{pat}));
    _pp($outref, $node->{body}, $lvl+1, $opt);
    return;
  }

  # Fallback
  _line($outref, $lvl, $k);
}

sub _pp_type_inline ($t) {
  return "<type?>" if !$t || ref($t) ne 'HASH';
  my $k = $t->{kind} // '';
  if ($k eq 'TypeName') { return $t->{name} // '<type>'; }
  if ($k eq 'TypeArray') { return "[" . _pp_type_inline($t->{elem}) . "]"; }
  if ($k eq 'TypeHash') { return "{" . _pp_type_inline($t->{key}) . ":" . _pp_type_inline($t->{val}) . "}"; }
  if ($k eq 'TypeApply') {
    my $base = $t->{base} // '<base>';
    my $args = join(", ", map { _pp_type_inline($_) } @{ $t->{args} // [] });
    return "$base\[$args\]";
  }
  return "<type:$k>";
}


sub _pp_enum_field_inline ($f) {
  return "<field?>" if !$f || ref($f) ne 'HASH';
  my $ty = _pp_type_inline($f->{type});
  if (defined($f->{sigil}) && defined($f->{name})) {
    return "$ty $f->{sigil}$f->{name}";
  }
  return "$ty";
}

sub _pp_param_inline ($p) {
  return "<param?>" if !$p || ref($p) ne 'HASH';
  my $r = $p->{ref} ? "^" : "";
  my $ty = _pp_type_inline($p->{type});
  return "$r$ty $p->{sigil}$p->{name}";
}

sub _pp_pat_inline ($p) {
  return "<pat?>" if !$p || ref($p) ne 'HASH';
  my $k = $p->{kind} // '';
  return "<pat:$k>" if $k ne 'PatternVariant';
  my $name = $p->{name} // '<Variant>';
  my @binds;
  if ($p->{binds} && ref($p->{binds}) eq 'ARRAY') {
    @binds = @{ $p->{binds} };
  } elsif ($p->{bind}) {
    # Back-compat for older ASTs.
    @binds = ($p->{bind});
  }
  if (@binds) {
    my $inner = join(", ", map {
      my $b = $_;
      my $ty = $b->{type} ? _pp_type_inline($b->{type}) . " " : "";
      $ty . "$b->{sigil}$b->{name}"
    } @binds);
    return "$name($inner)";
  }
  return $name;
}

sub _pp_expr_inline ($e) {
  return "<expr?>" if !$e || ref($e) ne 'HASH';
  my $k = $e->{kind} // '';
  if ($k eq 'LitInt' || $k eq 'LitNum') { return $e->{value}; }
  if ($k eq 'LitBool') { return $e->{value} ? "true" : "false"; }
  if ($k eq 'LitStr') { return '"' . _escape($e->{value} // '') . '"'; }
  if ($k eq 'LitRawStr') { return "'" . ($e->{value} // '') . "'"; }
  if ($k eq 'Var') { return ($e->{sigil} // '$') . ($e->{name} // '?'); }
  if ($k eq 'Name') { return $e->{name} // '<name>'; }
  if ($k eq 'Unary') { return $e->{op} . " " . _pp_expr_inline($e->{expr}); }
  if ($k eq 'BinOp') { return "(" . _pp_expr_inline($e->{lhs}) . " $e->{op} " . _pp_expr_inline($e->{rhs}) . ")"; }
  if ($k eq 'Call') {
    my $cal = _pp_expr_inline($e->{callee});
    my $args = join(", ", map { _pp_expr_inline($_) } @{ $e->{args} // [] });
    return "$cal($args)";
  }
  return "<expr:$k>";
}

sub _escape ($s) {
  $s =~ s/\\/\\\\/g;
  $s =~ s/"/\\"/g;
  $s =~ s/\n/\\n/g;
  $s =~ s/\r/\\r/g;
  $s =~ s/\t/\\t/g;
  return $s;
}

1;
