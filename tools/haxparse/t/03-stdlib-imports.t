use v5.36;
use strict;
use warnings;

use Test::More;

# This test ensures that stdlib imports resolve cleanly through the
# front-end pipeline (ResolveImports + from-import symbol checking).

my $bin = 'tools/haxparse/bin/haxparse-ok';

my @files = qw(
  examples/ok/import_std_sys_io_ok.hax
);

for my $path (@files) {
  my $out = `$bin $path 2>&1`;
  ok($? == 0, "stdlib import resolves: $path") or diag($out);
}

done_testing;