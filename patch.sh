#!/usr/bin/env bash
#
# Adds optional RFC password persistence ("Remember me") on top of the native
# RFC logon in SAP's "ABAP Development Tools for VS Code" extension (1.0.1+).
#
# Pure text surgery on two files inside the installed extension:
#   dist/_bundle/extension.js  and  package.json
# It touches NO jar, decompiles nothing, and needs no JDK/Java. The exact
# find/replace payloads live in patch/payloads.json next to this script.
#
# Safety: guard refuses a second run, every anchor must occur EXACTLY once, and
# nothing is written on any mismatch (safe stop). No backups; undo = reinstall
# or update the extension.
#
# Usage:
#   ./patch.sh                         # auto-detect newest sapse.adt-vscode-*
#   ./patch.sh /path/to/extension/root # explicit extension root
#
# Engine: perl, which is preinstalled on macOS and every mainstream Linux, has
# no line-length limits (the bundle has very long minified lines), and matches
# literally so the anchors need no escaping. The Windows path is patch.ps1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERL="$(command -v perl || true)"
if [ -z "$PERL" ]; then
  echo "Error: perl is required (preinstalled on macOS and Linux). On Windows use patch.ps1." >&2
  exit 2
fi

exec "$PERL" - "$SCRIPT_DIR" "${1:-}" <<'PERLEOF'
use strict;
use warnings;
use JSON::PP;

my ($script_dir, $explicit) = @ARGV;
$explicit = '' unless defined $explicit;

sub slurp_raw {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or die "Cannot read $path: $!\n";
    local $/;
    my $data = <$fh>;
    close($fh);
    return $data;
}

sub spit_raw {
    my ($path, $data) = @_;
    open(my $fh, '>:raw', $path) or die "Cannot write $path: $!\n";
    print {$fh} $data;
    close($fh);
}

sub count_occ {
    my ($haystack, $needle) = @_;
    return 0 if !defined $needle || $needle eq '';
    my $count = 0;
    my $i = 0;
    while (($i = index($haystack, $needle, $i)) >= 0) {
        $count++;
        $i += length($needle);
    }
    return $count;
}

# Load payloads.json (next to this script).
my $spec_path = "$script_dir/patch/payloads.json";
my $spec = decode_json(slurp_raw($spec_path));
my $marker = $spec->{guardMarker};

# Resolve the extension root.
my $root;
if ($explicit ne '') {
    die "ExtensionDir not found: $explicit\n" unless -d $explicit;
    $root = $explicit;
} else {
    my $base = "$ENV{HOME}/.vscode/extensions";
    my @cands = sort grep { -d $_ } glob("$base/sapse.adt-vscode-*");
    die "No installed 'sapse.adt-vscode-*' extension found under $base\n" unless @cands;
    $root = $cands[-1];  # newest by name
}

my $extjs = "$root/$spec->{extjsRelPath}";
my $pkg   = "$root/$spec->{pkgRelPath}";

print "Extension root : $root\n";
print "Target (js)    : $extjs\n";
print "Target (json)  : $pkg\n\n";

die "Target file missing: $extjs\n" unless -f $extjs;
die "Target file missing: $pkg\n"   unless -f $pkg;

my $ext_text = slurp_raw($extjs);
my $pkg_text = slurp_raw($pkg);

# Guard: already patched?
if (count_occ($ext_text, $marker) > 0 || count_occ($pkg_text, $marker) > 0) {
    print "Already patched (found marker '$marker'). Nothing to do.\n";
    print "To undo, reinstall or update the extension.\n";
    exit 0;
}

# Verify every anchor occurs exactly once BEFORE writing anything.
my @errors;
for my $pl (@{$spec->{payloads}}) {
    my $target = $pl->{target} eq 'extjs'   ? $ext_text
               : $pl->{target} eq 'pkgjson' ? $pkg_text
               : undef;
    if (!defined $target) {
        push @errors, "payload '$pl->{name}': unknown target '$pl->{target}'";
        next;
    }
    my $n = count_occ($target, $pl->{find});
    if ($n != 1) {
        push @errors, "payload '$pl->{name}' [$pl->{target}]: anchor occurs $n time(s), expected exactly 1";
    }
}
if (@errors) {
    print "Safe stop: anchor verification failed. NOTHING was changed.\n";
    print "  - $_\n" for @errors;
    print "The installed extension version may differ from what this patch targets.\n";
    exit 1;
}

# Apply (in memory). Each anchor occurs exactly once, so a single literal
# substr replacement is unambiguous.
for my $pl (@{$spec->{payloads}}) {
    my $find = $pl->{find};
    my $repl = $pl->{replace};
    if ($pl->{target} eq 'extjs') {
        my $pos = index($ext_text, $find);
        substr($ext_text, $pos, length($find)) = $repl;
    } elsif ($pl->{target} eq 'pkgjson') {
        my $pos = index($pkg_text, $find);
        substr($pkg_text, $pos, length($find)) = $repl;
    }
}

# Sanity: marker must now be present in both files.
if (count_occ($ext_text, $marker) < 1 || count_occ($pkg_text, $marker) < 1) {
    die "Safe stop: post-apply sanity check failed. NOTHING was written.\n";
}

spit_raw($extjs, $ext_text);
spit_raw($pkg,   $pkg_text);

print "Patched successfully.\n";
print "Reload VS Code (Developer: Reload Window) to load the patched extension.\n";
print "Logon once; after it succeeds you will be asked whether to remember the password.\n";
PERLEOF
