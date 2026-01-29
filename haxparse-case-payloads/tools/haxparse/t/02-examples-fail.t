use v5.36;
use strict;
use warnings;
use Test::More;

# NOTE:
# Most files under examples/fail are *semantic* failures (type checks, exhaustiveness, ref rules)
# which are not all enforced yet. This harness:
#   - runs the full front-end pipeline we have today (parse + current checks)
#   - expects failures where checks exist
#   - marks the rest as TODO until the corresponding checker/type stage lands

my $bin = 'tools/haxparse/bin/haxparse-ok';
my $dir = 'examples/fail';

opendir(my $dh, $dir) or die "Cannot open $dir: $!";
my @files = sort grep { /\.hax$/ } readdir($dh);
closedir($dh);

# Failures we expect the current pipeline to catch *today*.
# Add to this list as new checks land.
my %must_fail_now = map { $_ => 1 } qw(
  import_collision.hax
  import_module_missing.hax
  from_import_module_missing.hax
  from_import_symbol_missing.hax
  from_import_private_symbol.hax
  case_not_exhaustive.hax
  boolop_not_requires_bool.hax
  boolop_and_requires_bool.hax
  boolop_or_requires_bool.hax
  ref_param_rebind.hax
  case_payload_arity_too_few.hax
  case_payload_arity_unit_bind.hax
);

for my $f (@files) {
  my $path = "$dir/$f";
  my $out  = `$bin $path 2>&1`;
  my $ok   = ($? == 0);

  if (!$ok) {
    pass("FAIL parse/check (as expected): $f");
    next;
  }

  if ($must_fail_now{$f}) {
    fail("FAIL parse/check: $f") or diag("unexpected success\n$out");
    next;
  }

  TODO: {
    local $TODO = "semantic checker/type stage not implemented yet for $f";
    ok(!$ok, "FAIL (eventually): $f");
  }
}

done_testing;
