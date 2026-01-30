package Hax::Lexer;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.003';

my %KW = map { $_ => 1 } qw(
  module import from as
  pub priv
  enum struct class
  sub method mut field
  var local static global
  if elsif else
  while for foreach in
  case when
  break continue return
  and or not
  true false
  Void Never Int Bool Str int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64
);

sub new ($class, %args) {
  return bless {
    file => $args{file} // '<input>',
    src  => $args{src}  // '',
    i    => 0,
    line => 1,
    col  => 1,
  }, $class;
}

sub _peek ($self, $n=0) {
  my $i = $self->{i} + $n;
  return '' if $i >= length($self->{src});
  return substr($self->{src}, $i, 1);
}

sub _take ($self) {
  my $ch = $self->_peek(0);
  return '' if $ch eq '';
  $self->{i}++;
  if ($ch eq "\n") { $self->{line}++; $self->{col}=1; }
  else             { $self->{col}++; }
  return $ch;
}

sub _tok ($self, $type, $value, $line, $col) {
  return {
    type  => $type,
    value => $value,
    file  => $self->{file},
    line  => $line,
    col   => $col,
  };
}

sub next_token ($self) {
  # skip whitespace and block comments
  while (1) {
    my $ch = $self->_peek(0);
    return $self->_tok('EOF','', $self->{line}, $self->{col}) if $ch eq '';

    if ($ch =~ /\s/) {
      $self->_take;
      next;
    }

    if ($ch eq '-' && $self->_peek(1) eq '-') {
      my $line = $self->{line};
      my $col  = $self->{col};
      $self->_take; $self->_take;
      while (1) {
        my $c = $self->_peek(0);
        die "Unterminated comment at $line:$col\n" if $c eq '';
        if ($c eq '-' && $self->_peek(1) eq '-') {
          $self->_take; $self->_take;
          last;
        }
        $self->_take;
      }
      next;
    }

    last;
  }

  my $line = $self->{line};
  my $col  = $self->{col};
  my $ch   = $self->_peek(0);

  # identifiers / keywords
  if ($ch =~ /[A-Za-z_]/) {
    my $id = '';
    while (1) {
      my $c = $self->_peek(0);
      last if $c eq '' || $c !~ /[A-Za-z0-9_]/;
      $id .= $self->_take;
    }
    return $self->_tok($KW{$id} ? 'KW' : 'IDENT', $id, $line, $col);
  }

  # numbers
  if ($ch =~ /[0-9]/) {
    my $num = '';
    while (1) {
      my $c = $self->_peek(0);
      last if $c eq '' || $c !~ /[0-9]/;
      $num .= $self->_take;
    }
    if ($self->_peek(0) eq '.' && $self->_peek(1) =~ /[0-9]/) {
      $num .= $self->_take;
      while (1) {
        my $c = $self->_peek(0);
        last if $c eq '' || $c !~ /[0-9]/;
        $num .= $self->_take;
      }
      return $self->_tok('NUM', $num, $line, $col);
    }
    return $self->_tok('INT', $num, $line, $col);
  }

  # strings
  if ($ch eq '"') {
    $self->_take;
    my $out = '';
    while (1) {
      my $c = $self->_peek(0);
      die "Unterminated string at $line:$col\n" if $c eq '';
      last if $c eq '"';
      if ($c eq '\\') {
        $self->_take;
        my $e = $self->_take;
        my %ok = (
          '\\' => '\\', '"' => '"',
          'n' => "\n", 'r' => "\r", 't' => "\t",
        );
        die "Bad escape \\$e at $self->{line}:$self->{col}\n" unless exists $ok{$e};
        $out .= $ok{$e};
      } else {
        $out .= $self->_take;
      }
    }
    $self->_take;
    return $self->_tok('STR', $out, $line, $col);
  }

  # raw strings
  if ($ch eq "'") {
    $self->_take;
    my $out = '';
    while (1) {
      my $c = $self->_peek(0);
      die "Unterminated raw string at $line:$col\n" if $c eq '';
      last if $c eq "'";
      $out .= $self->_take;
    }
    $self->_take;
    return $self->_tok('RAWSTR', $out, $line, $col);
  }

  # multi-char operators
  for my $op (qw(:: := -> == != <= >= =>)) {
    my $len = length($op);
    if (substr($self->{src}, $self->{i}, $len) eq $op) {
      $self->{i} += $len;
      $self->{col} += $len;
      return $self->_tok('OP', $op, $line, $col);
    }
  }

  # single-char punctuation/operators
  my %single = map { $_ => 1 } (
    '(', ')', '{', '}', '[', ']', ',', ';', ':', '.',
    '+', '-', '*', '/', '%', '<', '>', '=', '^', '$', '@',
  );

  if ($single{$ch}) {
    $self->_take;
    return $self->_tok('PUNCT', $ch, $line, $col);
  }

  die "Unexpected character '$ch' at $line:$col\n";
}

1;