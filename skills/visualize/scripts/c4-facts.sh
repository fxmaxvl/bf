#!/usr/bin/env bash
# The only place that parses LikeC4 DSL in shell. Comments and string literals are stripped first,
# so a stamped marker line, a commented-out view or a "#tbd" inside a description never counts.
#
# Usage:  c4-facts.sh <file.c4>
# Output: {"kinds":[...],"has_specification":bool,"views":[...],"element_count":N,"tbd_count":N}
#         kinds: `element <name>` entries in specification blocks; views: unique ids (a dynamic view counts once);
#         element_count: `<name> = <kind>` declarations in model blocks; tbd_count: `#tbd` tags in model blocks.
# Errors: {"error":...,"detail":...} + exit 1 — usage, file_not_found, jq_missing.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq_missing","detail":"jq not installed"}\n'; exit 1; }
fail() { jq -cn --arg e "$1" --arg d "$2" '{error:$e, detail:$d}'; exit 1; }
[ $# -eq 1 ] || fail usage "c4-facts.sh <file.c4>"
[ -f "$1" ] || fail file_not_found "no such file: $1"

perl -e '
use strict; use warnings; use JSON::PP;
use open qw(:std :utf8);
my $src = do { local $/; open my $fh, "<:utf8", $ARGV[0] or die; <$fh> };
$src =~ s{(\x27(?:[^\x27\\]|\\.)*\x27|"(?:[^"\\]|\\.)*")|(//[^\n]*)|(/\*.*?\*/)}{ defined $1 ? "\x27\x27" : " " }gse;

my %blocks;
pos($src) = 0;
while ($src =~ /\G.*?\b(specification|model|views)\s*\{/gcs) {
  my ($name, $start) = ($1, pos($src));
  my ($depth, $i) = (1, $start);
  while ($depth > 0 && $i < length $src) {
    my $c = substr($src, $i, 1);
    $depth++ if $c eq "{";
    $depth-- if $c eq "}";
    $i++;
  }
  $blocks{$name} .= substr($src, $start, $i - $start - 1) . "\n";
  pos($src) = $i;
}

my %seen;
my @kinds = ($blocks{specification} // "") =~ /\belement\s+([A-Za-z_][\w-]*)/g;
my @views = grep { $_ ne "of" && !$seen{$_}++ } ($blocks{views} // "") =~ /\bview\s+([A-Za-z_][\w-]*)/g;
my $model = $blocks{model} // "";
my $elements = () = $model =~ /\b[A-Za-z_][\w-]*\s*=\s*[A-Za-z_][\w-]*/g;
my $tbd = () = $model =~ /#tbd(?![\w-])/g;

print JSON::PP->new->canonical->encode({
  kinds => \@kinds,
  has_specification => (exists $blocks{specification} ? JSON::PP::true : JSON::PP::false),
  views => \@views,
  element_count => $elements + 0,
  tbd_count => $tbd + 0,
}), "\n";
' "$1"
