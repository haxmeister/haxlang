use v5.36;
use strict;
use warnings;
use Test::More;

my $bin_ok = 'tools/haxparse/bin/haxc';

# Program OKs
{
  my $dir = 'examples/prog_ok';
  opendir(my $dh, $dir) or die "Cannot open $dir: $!";
  my @files = sort grep { /\.hax\z/ } readdir($dh);
  closedir($dh);

  for my $f (@files) {
    my $path = "$dir/$f";
    my $out  = `$bin_ok check $path 2>&1`;
    ok($? == 0, "OK program: $f") or diag($out);
  }
}

# Program FAILs
{
  my $dir = 'examples/prog_fail';
  opendir(my $dh, $dir) or die "Cannot open $dir: $!";
  my @files = sort grep { /\.hax\z/ } readdir($dh);
  closedir($dh);

  for my $f (@files) {
    my $path = "$dir/$f";
    my $out  = `$bin_ok check $path 2>&1`;
    ok($? != 0, "FAIL program (as expected): $f") or diag($out);
  }
}

done_testing;
