package Hax::Parser;

use v5.36;
use strict;
use warnings;

use Hax::AST qw(node span);

our $VERSION = '0.001';

sub new ($class, %args) {
  my $lex = $args{lexer} // die "lexer required";
  my $self = bless { lex => $lex, cur => undef }, $class;
  $self->{cur} = $self->{lex}->next_token;
  return $self;
}

sub _eat ($self, $type, $value=undef) {
  my $t = $self->{cur};
  die "Expected $type\n" unless $t->{type} eq $type;
  die "Expected $value\n" if defined $value && $t->{value} ne $value;
  $self->{cur} = $self->{lex}->next_token;
  return $t;
}

sub _peek ($self, $type, $value=undef) {
  my $t = $self->{cur};
  return 0 unless $t->{type} eq $type;
  return 1 if !defined($value);
  return $t->{value} eq $value;
}

sub parse ($self) {
  return $self->parse_module;
}

sub parse_module ($self) {
  my $t0 = $self->_eat('KW','module');
  my $name = $self->parse_qual_name;
  $self->_eat('PUNCT',';');

  my @items;
  while (!$self->_peek('EOF')) {
    push @items, $self->parse_item;
  }

  return node('Module', span($t0, $self->{cur}), name => $name, items => \@items);
}

sub parse_item ($self) {
  if ($self->_peek('KW','import') || $self->_peek('KW','from')) {
    return $self->parse_import;
  }
  die "Unexpected top-level item at $self->{cur}{line}:$self->{cur}{col}\n";
}

sub parse_import ($self) {
  my $t0 = $self->{cur};

  if ($self->_peek('KW','import')) {
    $self->_eat('KW','import');
    my $q = $self->parse_qual_name;
    my $as;
    if ($self->_peek('KW','as')) {
      $self->_eat('KW','as');
      $as = $self->_eat('IDENT')->{value};
    }
    $self->_eat('PUNCT',';');
    return node('Import', span($t0, $t0), module => $q, as => $as);
  }

  $self->_eat('KW','from');
  my $q = $self->parse_qual_name;
  $self->_eat('KW','import');
  my @names;
  push @names, $self->_eat('IDENT')->{value};
  while ($self->_peek('PUNCT',',')) {
    $self->_eat('PUNCT',',');
    push @names, $self->_eat('IDENT')->{value};
  }
  $self->_eat('PUNCT',';');
  return node('FromImport', span($t0, $t0), module => $q, names => \@names);
}

sub parse_qual_name ($self) {
  my $id = $self->_eat('IDENT')->{value};
  my @parts = ($id);
  while ($self->_peek('OP','::')) {
    $self->_eat('OP','::');
    push @parts, $self->_eat('IDENT')->{value};
  }
  return join('::', @parts);
}

1;
