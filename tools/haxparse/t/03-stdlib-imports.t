use strict;
use warnings;

use Test::More;
use FindBin qw($Bin);
use File::Spec;
use Cwd qw(abs_path);

my $ROOT = abs_path(File::Spec->catdir($Bin, File::Spec->updir, File::Spec->updir, File::Spec->updir));

my $haxc = File::Spec->catfile($ROOT, 'tools', 'haxparse', 'bin', 'haxc');
my $file = File::Spec->catfile($ROOT, 'examples', 'ok', 'import_std_sys_io_ok.hax');

plan tests => 1;

my $ok = system($haxc, 'check', '--std', File::Spec->catdir($ROOT, 'std'), $file) == 0;
ok($ok, "stdlib import resolves: examples/ok/import_std_sys_io_ok.hax");
