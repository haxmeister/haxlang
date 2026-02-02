use v5.36;
use strict;
use warnings;
<<<<<<< HEAD

=======
>>>>>>> 4b558b9 (add Core IR spec, ast + lower tooling, and tests)
use Test::More;

use FindBin qw($Bin);
use Cwd qw(abs_path);

<<<<<<< HEAD
# Repo root is two levels above this test file: tools/haxparse/t
my $repo = abs_path("$Bin/../../..");

die "Cannot locate repo root" if !$repo || !-d $repo;

my $haxc = "$repo/tools/haxparse/bin/haxc";
my $std_dir  = "$repo/std";
my $std_arg  = './std';
my $data = "$repo/tools/haxparse/t/data";

plan skip_all => "Missing $haxc" if !-x $haxc;
plan skip_all => "Missing stdlib directory: $std_dir" if !-d $std_dir;
plan skip_all => "Missing test data directory: $data" if !-d $data;

sub _slurp ($path) {
  open my $fh, '<', $path or die "open($path): $!";
  local $/;
  return <$fh>;
}

chdir $repo or die "chdir($repo): $!";

my @cases = (
  {
    name     => 'case_exhaustive_enum',
    file     => 'examples/ok/case_exhaustive_enum.hax',
    expect   => "$data/ast_case_exhaustive_enum.txt",
    re_check => [
      [ qr/^HAX AST v0\.1/m,           'header present' ],
      [ qr/^phase:\s+checked_ast/m,    'phase present' ],
      [ qr/^mode:\s+library/m,         'mode present' ],
      [ qr/\(Case\b/,                  'has Case node' ],
      [ qr/_exhaustive:/,              'mentions exhaustiveness' ],
      [ qr/_type:/,                    'has type annotations' ],
    ],
  },
  {
    name     => 'never_ok',
    file     => 'examples/ok/never_ok.hax',
    expect   => "$data/ast_never_ok.txt",
    re_check => [
      [ qr/^HAX AST v0\.1/m,           'header present' ],
      [ qr/^phase:\s+checked_ast/m,    'phase present' ],
      [ qr/^mode:\s+library/m,         'mode present' ],
      [ qr/\bNever\b/,                 'mentions Never' ],
      [ qr/_type:/,                    'has type annotations' ],
    ],
  },
);

for my $c (@cases) {
  plan skip_all => "Missing example: $c->{file}" if !-f $c->{file};
  plan skip_all => "Missing expected snapshot: $c->{expect}" if !-f $c->{expect};

  my $cmd = "$haxc ast --lib --std \"$std_arg\" \"$c->{file}\" 2>&1";
  my $out = `$cmd`;
  ok($? == 0, "haxc ast exits 0 ($c->{name})") or diag($out);

  my $exp = _slurp($c->{expect});
  is($out, $exp, "AST snapshot matches ($c->{name})") or diag($out);

  for my $chk (@{ $c->{re_check} }) {
    my ($re, $label) = @$chk;
    like($out, $re, "$label ($c->{name})") or diag($out);
  }
=======
my $repo = abs_path("$Bin/../../..");
die "Cannot locate repo root" if !$repo || !-d $repo;

my $haxc = "$repo/tools/haxparse/bin/haxc";
my $dir  = "$repo/examples/ok";
my $data = "$Bin/data";

plan skip_all => "Missing $haxc" if !-x $haxc;
plan skip_all => "Missing examples directory: $dir" if !-d $dir;
plan skip_all => "Missing stdlib directory: $repo/std" if !-d "$repo/std";
plan skip_all => "Missing data directory: $data" if !-d $data;

my @cases = (
  ["case_exhaustive_enum.hax", "$data/ast_case_exhaustive_enum.txt"],
  ["never_ok.hax", "$data/ast_never_ok.txt"],
);

for my $c (@cases) {
  my ($file, $gold_path) = @$c;
  my $rel = "examples/ok/$file";

  open(my $gh, '<:encoding(UTF-8)', $gold_path) or die "open $gold_path: $!";
  my $gold = do { local $/; <$gh> };
  close $gh;

  my $cmd = "(cd \"$repo\" && \"$haxc\" ast --lib --std ./std -I examples/ok \"$rel\" ) 2>&1";
  my $out = `$cmd`;
  ok($? == 0, "haxc ast exits 0 ($file)") or diag($out);
  is($out, $gold, "AST snapshot matches ($file)");
>>>>>>> 4b558b9 (add Core IR spec, ast + lower tooling, and tests)
}

done_testing;
