package Hax::AST::Pretty;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.001';

sub pretty ($ast) {
  my @out;
  _node($ast, 0, \@out);
  return join("", @out);
}

sub _emit ($out, $indent, $line) {
  push @$out, ("  " x $indent) . $line . "\n";
}

sub _node ($n, $indent, $out) {
  return unless ref($n) eq 'HASH';
  my $k = $n->{kind} // '<unknown>';

  if ($k eq 'Module') {
    _emit($out, $indent, "Module $n->{name}");
    for my $it (@{ $n->{items} // [] }) {
      _node($it, $indent+1, $out);
    }
    return;
  }

  if ($k eq 'Import') {
    my $as = defined $n->{as} ? " as $n->{as}" : "";
    _emit($out, $indent, "Import $n->{module}$as");
    return;
  }

  if ($k eq 'FromImport') {
    _emit($out, $indent, "FromImport $n->{module} [" . join(", ", @{ $n->{names} // [] }) . "]");
    return;
  }

  if ($k eq 'Sub') {
    my $vis = $n->{vis} ? "$n->{vis} " : "";
    my $ret = _type_str($n->{ret});
    _emit($out, $indent, "${vis}Sub $n->{name} -> $ret");
    for my $p (@{ $n->{params} // [] }) {
      _node($p, $indent+1, $out);
    }
    _node($n->{body}, $indent+1, $out);
    return;
  }

  if ($k eq 'Param') {
    my $ref = $n->{ref} ? "^" : "";
    _emit($out, $indent, "Param ${ref}" . _type_str($n->{type}) . " $n->{sigil}$n->{name}");
    return;
  }

  if ($k eq 'Block') {
    _emit($out, $indent, "Block");
    for my $st (@{ $n->{stmts} // [] }) {
      _node($st, $indent+1, $out);
    }
    return;
  }

  if ($k eq 'VarDecl') {
    my $st = $n->{storage} ? "($n->{storage}) " : "";
    my $rf = $n->{ref} ? "^" : "";
    _emit($out, $indent, "VarDecl ${st}${rf}" . _type_str($n->{type}) . " $n->{sigil}$n->{name}");
    _node($n->{init}, $indent+1, $out) if $n->{init};
    return;
  }

  if ($k eq 'If') {
    _emit($out, $indent, "If");
    _emit($out, $indent+1, "Cond");
    _node($n->{cond}, $indent+2, $out);
    _emit($out, $indent+1, "Then");
    _node($n->{then}, $indent+2, $out);
    if ($n->{else}) {
      _emit($out, $indent+1, "Else");
      _node($n->{else}, $indent+2, $out);
    }
    return;
  }

  if ($k eq 'Case') {
    _emit($out, $indent, "Case");
    _emit($out, $indent+1, "Expr");
    _node($n->{expr}, $indent+2, $out);
    for my $w (@{ $n->{whens} // [] }) {
      _node($w, $indent+1, $out);
    }
    if ($n->{else}) {
      _emit($out, $indent+1, "Else");
      _node($n->{else}, $indent+2, $out);
    }
    return;
  }

  if ($k eq 'When') {
    _emit($out, $indent, "When");
    _node($n->{pat}, $indent+1, $out);
    _node($n->{body}, $indent+1, $out);
    return;
  }

  if ($k eq 'PatternVariant') {
    _emit($out, $indent, "Pattern $n->{name}");
    _node($n->{bind}, $indent+1, $out) if $n->{bind};
    return;
  }

  if ($k eq 'PatBind') {
    my $t = $n->{type} ? _type_str($n->{type}) . " " : "";
    _emit($out, $indent, "Bind ${t}$n->{sigil}$n->{name}");
    return;
  }

  if ($k eq 'Return') {
    _emit($out, $indent, "Return");
    _node($n->{expr}, $indent+1, $out) if $n->{expr};
    return;
  }

  if ($k eq 'Assign') {
    _emit($out, $indent, "Assign $n->{op}");
    _node($n->{lhs}, $indent+1, $out);
    _node($n->{rhs}, $indent+1, $out);
    return;
  }

  if ($k eq 'ExprStmt') {
    _emit($out, $indent, "ExprStmt");
    _node($n->{expr}, $indent+1, $out);
    return;
  }

  if ($k eq 'BinOp') {
    _emit($out, $indent, "BinOp $n->{op}");
    _node($n->{lhs}, $indent+1, $out);
    _node($n->{rhs}, $indent+1, $out);
    return;
  }

  if ($k eq 'Unary') {
    _emit($out, $indent, "Unary $n->{op}");
    _node($n->{expr}, $indent+1, $out);
    return;
  }

  if ($k eq 'Call') {
    _emit($out, $indent, "Call");
    _node($n->{callee}, $indent+1, $out);
    for my $a (@{ $n->{args} // [] }) {
      _node($a, $indent+1, $out);
    }
    return;
  }

  if ($k eq 'Var') {
    _emit($out, $indent, "Var $n->{sigil}$n->{name}");
    return;
  }

  if ($k eq 'Name') {
    _emit($out, $indent, "Name $n->{name}");
    return;
  }

  if ($k =~ /^Lit/) {
    _emit($out, $indent, "$k $n->{value}");
    return;
  }

  _emit($out, $indent, "UnknownNode $k");
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

1;
