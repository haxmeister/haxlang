use v5.36;
use strict;
use warnings;
use Test::More;

my $bin = 'tools/haxparse/bin/haxpp';
my $dir = 'examples/ok';

opendir(my $dh, $dir) or die "Cannot open $dir: $!";
my @files = grep { /\.hax$/ } readdir($dh);
closedir($dh);

for my $f (@files) {
    my $path = "$dir/$f";
    my $out = `$bin $path 2>&1`;
    ok($? == 0, "OK parse: $f") or diag($out);
}

done_testing;
