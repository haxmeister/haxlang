use strict;
use warnings;

use Test::More;
use FindBin qw($Bin);
use File::Spec;
use Cwd qw(abs_path);

my $ROOT = abs_path(File::Spec->catdir($Bin, File::Spec->updir, File::Spec->updir, File::Spec->updir));
my $haxc  = File::Spec->catfile($ROOT, 'tools', 'haxparse', 'bin', 'haxc');
my $std   = File::Spec->catdir($ROOT, 'std');

my $OK_DIR   = File::Spec->catdir($ROOT, 'examples', 'prog_ok');
my $FAIL_DIR = File::Spec->catdir($ROOT, 'examples', 'prog_fail');

plan tests => 3;

ok(system($haxc, 'check', '--std', $std, File::Spec->catfile($OK_DIR, 'main_ruleb_ok.hax')) == 0,
   'program ok: main_ruleb_ok.hax');

ok(system($haxc, 'check', '--std', $std, File::Spec->catfile($FAIL_DIR, 'no_main.hax')) != 0,
   'program fail: no_main.hax');

ok(system($haxc, 'check', '--std', $std, File::Spec->catfile($FAIL_DIR, 'main_bad_sig.hax')) != 0,
   'program fail: main_bad_sig.hax');
