use v5.36;
use strict;
use warnings;

use Test::More;
use FindBin qw($Bin);

sub slurp ($path) {
  open(my $fh, '<:encoding(UTF-8)', $path) or die "open $path: $!";
  return do { local $/; <$fh> };
}

my $repo = "$Bin/../../..";           # repo root
my $haxc = "$repo/tools/haxparse/bin/haxc";

sub run_lower ($file) {
  my $cmd = "$haxc lower --std $repo/std $repo/$file";
  my $out = `$cmd`;
  my $rc = $? >> 8;
  return ($rc, $out);
}

my @cases = (
  {
    file   => 'examples/ok/lower_min_ok.hax',
    golden => "$Bin/data/lower_min_ok.txt",
  },
  {
    file   => 'examples/ok/lower_never_ok.hax',
    golden => "$Bin/data/lower_never_ok.txt",
  },
);

for my $c (@cases) {
  my ($rc, $out) = run_lower($c->{file});
  is($rc, 0, "lower ok: $c->{file}");
  my $exp = slurp($c->{golden});
  is($out, $exp, "snapshot: $c->{file}");
}

done_testing;
