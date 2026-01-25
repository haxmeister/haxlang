package Hax::AST;

use v5.36;
use strict;
use warnings;

our $VERSION = '0.001';

sub span ($tok0, $tok1=undef) {
  $tok1 //= $tok0;
  return {
    file  => $tok0->{file},
    sline => $tok0->{line},
    scol  => $tok0->{col},
    eline => $tok1->{line},
    ecol  => $tok1->{col},
  };
}

sub node ($kind, $span, %fields) {
  return { kind => $kind, span => $span, %fields };
}

1;
