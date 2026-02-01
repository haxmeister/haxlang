package Hax::Parser;

use v5.36;
use strict;
use warnings;

use Hax::AST qw(node span);

our $VERSION = '0.005';

sub new ($class, %args) {
  my $lex = $args{lexer} // die "lexer required";
  my $self = bless { lex => $lex, cur => undef }, $class;
  $self->{cur} = $self->{lex}->next_token;
  return $self;
}

sub _err ($self, $msg) {
  my $t = $self->{cur};
  die "$msg at $t->{file}:$t->{line}:$t->{col}\n";
}

sub _eat ($self, $type, $value=undef) {
  my $t = $self->{cur};
  $self->_err("Expected $type") unless $t->{type} eq $type;
  $self->_err("Expected $value") if defined $value && $t->{value} ne $value;
  $self->{cur} = $self->{lex}->next_token;
  return $t;
}

sub _peek ($self, $type, $value=undef) {
  my $t = $self->{cur};
  return 0 unless $t->{type} eq $type;
  return 1 if !defined($value);
  return $t->{value} eq $value;
}

sub _eat_kw ($self, $kw) { $self->_eat('KW', $kw) }
sub _peek_kw ($self, $kw) { $self->_peek('KW', $kw) }
sub _eat_p ($self, $p) { $self->_eat('PUNCT', $p) }
sub _peek_p ($self, $p) { $self->_peek('PUNCT', $p) }
sub _eat_op ($self, $op) { $self->_eat('OP', $op) }
sub _peek_op ($self, $op) { $self->_peek('OP', $op) }

sub parse ($self) {
  return $self->parse_module;
}

# Program/root parse: module header is optional.
# If absent, the file is treated as an anonymous root module.
sub parse_program ($self) {
  return $self->parse_module if $self->_peek_kw('module');
  return $self->parse_implicit_module;
}

sub parse_implicit_module ($self) {
  my $t0 = $self->{cur};
  my @items;
  while (!$self->_peek('EOF')) {
    push @items, $self->parse_item;
  }

  # Name is informational; the program root is chosen by CLI path.
  return node('Module', span($t0, $t0), name => '__root__', items => \@items);
}

sub parse_module ($self) {
  my $t0 = $self->_eat_kw('module');
  my $name = $self->parse_qual_name;
  $self->_eat_p(';');

  my @items;
  while (!$self->_peek('EOF')) {
    push @items, $self->parse_item;
  }

  return node('Module', span($t0, $t0), name => $name, items => \@items);
}

sub parse_item ($self) {
  if ($self->_peek_kw('import') || $self->_peek_kw('from')) {
    return $self->parse_import;
  }

  my $vis;
  if ($self->_peek_kw('pub') || $self->_peek_kw('priv')) {
    $vis = $self->_eat('KW')->{value};
  }

  if ($self->_peek_kw('enum')) {
    return $self->parse_enum($vis);
  }

  if ($self->_peek_kw('sub')) {
    return $self->parse_sub($vis);
  }

  $self->_err("Unexpected top-level item");
}
sub parse_import ($self) {
  my $t0 = $self->{cur};

  if ($self->_peek_kw('import')) {
    $self->_eat_kw('import');
    my $q = $self->parse_qual_name;
    my $as;
    if ($self->_peek_kw('as')) {
      $self->_eat_kw('as');
      $as = $self->_eat('IDENT')->{value};
    }
    $self->_eat_p(';');
    return node('Import', span($t0, $t0), module => $q, as => $as);
  }

  $self->_eat_kw('from');
  my $q = $self->parse_qual_name;
  $self->_eat_kw('import');
  my @names;
  push @names, $self->_eat('IDENT')->{value};
  while ($self->_peek_p(',')) {
    $self->_eat_p(',');
    push @names, $self->_eat('IDENT')->{value};
  }
  $self->_eat_p(';');
  return node('FromImport', span($t0, $t0), module => $q, names => \@names);
}

sub parse_qual_name ($self) {
  my $id = $self->_eat('IDENT')->{value};
  my @parts = ($id);
  while ($self->_peek_op('::')) {
    $self->_eat_op('::');
    push @parts, $self->_eat('IDENT')->{value};
  }
  return join('::', @parts);
}

# ---- Types ----

sub parse_type ($self) {
  my $t0 = $self->{cur};

  if ($self->_peek_p('[')) {
    $self->_eat_p('[');
    my $elem = $self->parse_type;
    $self->_eat_p(']');
    return node('TypeArray', span($t0, $self->{cur}), elem => $elem);
  }

  if ($self->_peek_p('{')) {
    $self->_eat_p('{');
    my $k = $self->parse_type;
    $self->_eat_p(':');
    my $v = $self->parse_type;
    $self->_eat_p('}');
    return node('TypeHash', span($t0, $self->{cur}), key => $k, val => $v);
  }

  my $base;
  if ($self->_peek('KW')) {
    $base = $self->_eat('KW')->{value};
  } else {
    $base = $self->parse_qual_name;
  }

  if ($self->_peek_p('[')) {
    $self->_eat_p('[');
    my @args;
    push @args, $self->parse_type;
    while ($self->_peek_p(',')) {
      $self->_eat_p(',');
      push @args, $self->parse_type;
    }
    $self->_eat_p(']');
    return node('TypeApply', span($t0, $self->{cur}), base => $base, args => \@args);
  }

  return node('TypeName', span($t0, $self->{cur}), name => $base);
}


# ---- Enums ----

sub parse_enum ($self, $vis) {
  my $t0 = $self->_eat_kw('enum');
  my $name = $self->_eat('IDENT')->{value};

  # Optional type params: enum Name[T,U] { ... }
  my @tparams;
  if ($self->_peek_p('[')) {
    $self->_eat_p('[');
    push @tparams, $self->_eat('IDENT')->{value};
    while ($self->_peek_p(',')) {
      $self->_eat_p(',');
      push @tparams, $self->_eat('IDENT')->{value};
    }
    $self->_eat_p(']');
  }

  $self->_eat_p('{');
  my @variants;

  # Allow empty enums (reserved); otherwise parse variants until '}'
  while (!$self->_peek_p('}')) {
    my $vt0 = $self->{cur};
    my $vname = $self->_eat('IDENT')->{value};

    my @fields;
    if ($self->_peek_p('(')) {
      $self->_eat_p('(');
      if (!$self->_peek_p(')')) {
        push @fields, $self->parse_enum_field;
        while ($self->_peek_p(',')) {
          $self->_eat_p(',');
          push @fields, $self->parse_enum_field;
        }
      }
      $self->_eat_p(')');
    }

    $self->_eat_p(';');
    push @variants, node('EnumVariant', span($vt0, $self->{cur}), name => $vname, fields => \@fields);
  }

  $self->_eat_p('}');
  return node('Enum', span($t0, $self->{cur}), vis => $vis, name => $name, tparams => \@tparams, variants => \@variants);
}

sub parse_enum_field ($self) {
  my $t0 = $self->{cur};
  my $type = $self->parse_type;

  # Optional binder: Int $value
  my ($sigil, $name);
  if ($self->_peek_p('$') || $self->_peek_p('@') || $self->_peek_p('%')) {
    ($sigil, $name) = $self->parse_var_name;
  }

  return node('EnumField', span($t0, $self->{cur}), type => $type, sigil => $sigil, name => $name);
}


# ---- Subroutines ----

sub parse_sub ($self, $vis) {
  my $t0 = $self->_eat_kw('sub');
  my $name = $self->_eat('IDENT')->{value};

  $self->_eat_p('(');
  my @params;
  if (!$self->_peek_p(')')) {
    push @params, $self->parse_param;
    while ($self->_peek_p(',')) {
      $self->_eat_p(',');
      push @params, $self->parse_param;
    }
  }
  $self->_eat_p(')');

  my $ret;
  if ($self->_peek_op('->')) {
    $self->_eat_op('->');
    $ret = $self->parse_type;
  } else {
    $ret = node('TypeName', span($t0, $t0), name => 'Void');
  }

  my $body = $self->parse_block;

  return node('Sub', span($t0, $t0), vis => $vis, name => $name, params => \@params, ret => $ret, body => $body);
}

sub parse_param ($self) {
  my $t0 = $self->{cur};

  my $is_ref = 0;
  if ($self->_peek_p('^')) {
    $self->_eat_p('^');
    $is_ref = 1;
  }

  my $type = $self->parse_type;

  my ($sigil, $name) = $self->parse_var_name;
  return node('Param', span($t0, $t0), ref => $is_ref, type => $type, sigil => $sigil, name => $name);
}

sub parse_var_name ($self) {
  my $t = $self->{cur};
  $self->_err("Expected variable sigil")
    unless $self->_peek_p('$') || $self->_peek_p('@') || $self->_peek_p('%') || $self->_peek_p('^');
  my $sigil = $self->_eat('PUNCT')->{value};

  my $name = $self->_eat('IDENT')->{value};
  return ($sigil, $name);
}

# ---- Blocks / Statements ----

sub parse_block ($self) {
  my $t0 = $self->_eat_p('{');
  my @stmts;
  while (!$self->_peek_p('}')) {
    push @stmts, $self->parse_stmt;
  }
  $self->_eat_p('}');
  return node('Block', span($t0, $t0), stmts => \@stmts);
}

sub parse_stmt ($self) {
  my $t0 = $self->{cur};

  if ($self->_peek_kw('var')) {
    return $self->parse_var_decl;
  }
  if ($self->_peek_kw('if')) {
    return $self->parse_if;
  }
  if ($self->_peek_kw('case')) {
    return $self->parse_case;
  }
  if ($self->_peek_kw('return')) {
    return $self->parse_return;
  }

  my $expr = $self->parse_expr;
  if ($self->_peek_op(':=') || $self->_peek_p('=')) {
    my $op = $self->_peek_op(':=') ? $self->_eat_op(':=')->{value} : $self->_eat_p('=')->{value};
    my $rhs = $self->parse_expr;
    $self->_eat_p(';');
    return node('Assign', span($t0, $t0), op => $op, lhs => $expr, rhs => $rhs);
  }

  $self->_eat_p(';');
  return node('ExprStmt', span($t0, $t0), expr => $expr);
}

sub parse_var_decl ($self) {
  my $t0 = $self->_eat_kw('var');

  my $storage;
  if ($self->_peek_p('(')) {
    $self->_eat_p('(');
    $storage = $self->_eat('KW')->{value};
    $self->_eat_p(')');
  }

  my $is_ref = 0;
  if ($self->_peek_p('^')) {
    $self->_eat_p('^');
    $is_ref = 1;
  }

  my $type = $self->parse_type;

  my ($sigil, $name) = $self->parse_var_name;

  my $init;
  my $op;
  if ($self->_peek_p('=') || $self->_peek_op(':=')) {
    if ($self->_peek_op(':=')) { $op = $self->_eat_op(':=')->{value}; }
    else { $op = $self->_eat_p('=')->{value}; }
    $init = $self->parse_expr;
  }

  $self->_eat_p(';');
  return node('VarDecl', span($t0, $t0), storage => $storage, ref => $is_ref, type => $type,
    sigil => $sigil, name => $name, op => $op, init => $init);
}

sub parse_if ($self) {
  my $t0 = $self->_eat_kw('if');
  $self->_eat_p('(');
  my $cond = $self->parse_expr;
  $self->_eat_p(')');
  my $then = $self->parse_block;

  my $else;
  if ($self->_peek_kw('else')) {
    $self->_eat_kw('else');
    $else = $self->parse_block;
  }

  return node('If', span($t0, $t0), cond => $cond, then => $then, else => $else);
}

sub parse_case ($self) {
  my $t0 = $self->_eat_kw('case');
  $self->_eat_p('(');
  my $scrut = $self->parse_expr;
  $self->_eat_p(')');
  $self->_eat_p('{');
  my @whens;
  my $else;
  while ($self->_peek_kw('when')) {
    push @whens, $self->parse_when;
  }
  if ($self->_peek_kw('else')) {
    $self->_eat_kw('else');
    $else = $self->parse_block;
  }
  $self->_eat_p('}');
  return node('Case', span($t0, $t0), expr => $scrut, whens => \@whens, else => $else);
}

sub parse_when ($self) {
  my $t0 = $self->_eat_kw('when');
  my $pat = $self->parse_pattern;
  my $blk = $self->parse_block;
  return node('When', span($t0, $t0), pat => $pat, body => $blk);
}

sub parse_pattern ($self) {
  my $t0 = $self->{cur};
  my $variant = $self->_eat('IDENT')->{value};

  my $bind;
  if ($self->_peek_p('(')) {
    $self->_eat_p('(');
    my $type;
    if (!$self->_peek_p('$') && !$self->_peek_p('@') && !$self->_peek_p('%') && !$self->_peek_p('^')) {
      $type = $self->parse_type;
    }
    my ($sigil, $name) = $self->parse_var_name;
    $self->_eat_p(')');
    $bind = node('PatBind', span($t0, $t0), type => $type, sigil => $sigil, name => $name);
  }

  return node('PatternVariant', span($t0, $t0), name => $variant, bind => $bind);
}

sub parse_return ($self) {
  my $t0 = $self->_eat_kw('return');
  my $expr;
  if (!$self->_peek_p(';')) {
    $expr = $self->parse_expr;
  }
  $self->_eat_p(';');
  return node('Return', span($t0, $t0), expr => $expr);
}

# ---- Expressions ----

my %PREC = (
  'or'  => 1,
  'and' => 2,
  '=='  => 3, '!=' => 3, '<' => 3, '<=' => 3, '>' => 3, '>=' => 3,
  '+'   => 4, '-'  => 4,
  '*'   => 5, '/'  => 5, '%'  => 5,
);

sub parse_expr ($self) {
  return $self->parse_binop(1);
}

sub parse_binop ($self, $min_prec) {
  my $t0 = $self->{cur};
  my $lhs = $self->parse_unary;

  while (1) {
    my $op;
    if ($self->_peek_kw('and') || $self->_peek_kw('or')) {
      $op = $self->{cur}{value};
    } elsif ($self->_peek('OP') && ($self->{cur}{value} eq '==' || $self->{cur}{value} eq '!=' || $self->{cur}{value} eq '<=' || $self->{cur}{value} eq '>=')) {
      $op = $self->{cur}{value};
    } elsif ($self->_peek_p('<') || $self->_peek_p('>') || $self->_peek_p('+') || $self->_peek_p('-') || $self->_peek_p('*') || $self->_peek_p('/') || $self->_peek_p('%')) {
      $op = $self->{cur}{value};
    } else {
      last;
    }

    my $prec = $PREC{$op};
    last if !defined($prec) || $prec < $min_prec;

    if ($op eq 'and' || $op eq 'or') {
      $self->_eat_kw($op);
    } elsif ($op =~ /^(==|!=|<=|>=)$/) {
      $self->_eat_op($op);
    } else {
      $self->_eat_p($op);
    }

    my $rhs = $self->parse_binop($prec + 1);
    $lhs = node('BinOp', span($t0, $t0), op => $op, lhs => $lhs, rhs => $rhs);
  }

  return $lhs;
}

sub parse_unary ($self) {
  my $t0 = $self->{cur};

  if ($self->_peek_kw('not')) {
    $self->_eat_kw('not');
    my $e = $self->parse_unary;
    return node('Unary', span($t0, $t0), op => 'not', expr => $e);
  }

  if ($self->_peek_p('-')) {
    $self->_eat_p('-');
    my $e = $self->parse_unary;
    return node('Unary', span($t0, $t0), op => '-', expr => $e);
  }

  return $self->parse_postfix;
}

sub parse_postfix ($self) {
  my $t0 = $self->{cur};
  my $expr = $self->parse_primary;

  while ($self->_peek_p('(')) {
    my @args = $self->parse_arg_list;
    $expr = node('Call', span($t0, $t0), callee => $expr, args => \@args);
  }

  return $expr;
}

sub parse_arg_list ($self) {
  $self->_eat_p('(');
  my @args;
  if (!$self->_peek_p(')')) {
    push @args, $self->parse_expr;
    while ($self->_peek_p(',')) {
      $self->_eat_p(',');
      push @args, $self->parse_expr;
    }
  }
  $self->_eat_p(')');
  return @args;
}

sub parse_primary ($self) {
  my $t0 = $self->{cur};

  if ($self->_peek('INT')) {
    return node('LitInt', span($t0,$t0), value => 0 + $self->_eat('INT')->{value});
  }
  if ($self->_peek('NUM')) {
    return node('LitNum', span($t0,$t0), value => 0.0 + $self->_eat('NUM')->{value});
  }
  if ($self->_peek('STR')) {
    return node('LitStr', span($t0,$t0), value => $self->_eat('STR')->{value});
  }
  if ($self->_peek('RAWSTR')) {
    return node('LitRawStr', span($t0,$t0), value => $self->_eat('RAWSTR')->{value});
  }
  if ($self->_peek_kw('true')) {
    $self->_eat_kw('true');
    return node('LitBool', span($t0,$t0), value => 1);
  }
  if ($self->_peek_kw('false')) {
    $self->_eat_kw('false');
    return node('LitBool', span($t0,$t0), value => 0);
  }

  if ($self->_peek_p('(')) {
    $self->_eat_p('(');
    my $e = $self->parse_expr;
    $self->_eat_p(')');
    return $e;
  }

  if ($self->_peek_p('$') || $self->_peek_p('@') || $self->_peek_p('%') || $self->_peek_p('^')) {
    my ($sigil, $name) = $self->parse_var_name;
    return node('Var', span($t0,$t0), sigil => $sigil, name => $name);
  }

  if ($self->_peek('IDENT') || $self->_peek('KW')) {
    # allow qualified names to start with IDENT; KW is accepted for type-like names in expression too
    my $name;
    if ($self->_peek('IDENT')) {
      $name = $self->parse_qual_name;
    } else {
      $name = $self->_eat('KW')->{value};
    }
    my $expr = node('Name', span($t0,$t0), name => $name);

    if ($self->_peek_p('(')) {
      my @args = $self->parse_arg_list;
      return node('Call', span($t0,$t0), callee => $expr, args => \@args);
    }
    return $expr;
  }

  $self->_err("Expected expression");
}

1;
