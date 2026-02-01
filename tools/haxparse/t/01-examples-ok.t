use v5.36;
use strict;
use warnings;
use Test::More;

use FindBin qw($Bin);
use Cwd qw(abs_path);

# Repo root is two levels above this test file: tools/haxparse/t
my $repo = abs_path("$Bin/../../..");

die "Cannot locate repo root" if !$repo || !-d $repo;

my $haxc = "$repo/tools/haxparse/bin/haxc";
my $std  = "$repo/std";
my $dir  = "$repo/examples/ok";

plan skip_all => "Missing $haxc" if !-x $haxc;
plan skip_all => "Missing examples directory: $dir" if !-d $dir;
plan skip_all => "Missing stdlib directory: $std" if !-d $std;

opendir(my $dh, $dir) or die "Cannot open $dir: $!";
my @files = sort grep { /\.hax\z/ } readdir($dh);
closedir($dh);

for my $f (@files) {
    my $path = "$dir/$f";
    my $cmd = "$haxc check --lib --std \"$std\" \"$path\" 2>&1";
    my $out = `$cmd`;
    ok($? == 0, "OK parse/check: $f") or diag($out);
}

done_testing;
