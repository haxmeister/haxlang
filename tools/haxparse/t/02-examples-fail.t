use strict;
use warnings;

use Test::More;
use FindBin qw($Bin);
use File::Spec;
use Cwd qw(abs_path);

my $ROOT = abs_path(File::Spec->catdir($Bin, File::Spec->updir, File::Spec->updir, File::Spec->updir));
my $FAIL_DIR = File::Spec->catdir($ROOT, 'examples', 'fail');

opendir(my $dh, $FAIL_DIR) or die "Cannot open $FAIL_DIR: $!";
my @files = sort grep { /\.hax\z/ } readdir($dh);
closedir($dh);

plan tests => scalar(@files);

my $haxparse_ok = File::Spec->catfile($ROOT, 'tools', 'haxparse', 'bin', 'haxparse-ok');

for my $f (@files) {
  my $path = File::Spec->catfile($FAIL_DIR, $f);
  my $ok = system($haxparse_ok, $path) == 0;
  ok(!$ok, "FAIL parse/check: $f") or diag("unexpected success: $path");
}
