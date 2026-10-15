#!/usr/bin/env bash
# Classify captured likec4 output. Exit codes miss layout warnings, which print as bare lines,
# so everything that is not a timestamped INFO/DEBUG line or an allowlisted bare line counts as a failure.
#
# Usage:  classify-output.sh <log> --allowlist <json-file>
#         <json-file> (required) holds a JSON array of Perl-compatible regexes for known-harmless bare lines.
# Output: {"errors":[{"file":"<path as printed, or empty>","lines":[...]}],"warnings":[...]}
# Errors: {"error":...,"detail":...} + exit 1 — usage, log_not_found, jq_missing.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq_missing","detail":"jq not installed"}\n'; exit 1; }
fail() { jq -cn --arg e "$1" --arg d "$2" '{error:$e, detail:$d}'; exit 1; }

log=${1:-}; allow=
[ $# -ge 1 ] || fail usage "classify-output.sh <log> --allowlist <json-file>"
shift
while [ $# -gt 0 ]; do
  case "$1" in
    --allowlist) [ $# -ge 2 ] || fail usage "--allowlist needs a <json-file> argument"; allow=$2; shift 2 ;;
    *) fail usage "unknown argument: $1" ;;
  esac
done
[ -f "$log" ] || fail log_not_found "no such file: $log"
[ -n "$allow" ] || fail usage "--allowlist <json-file> is required"
[ -f "$allow" ] || fail usage "no such allowlist file: $allow"

perl -e '
use strict; use warnings; use JSON::PP;
use open qw(:std :utf8);
my ($log, $allowfile) = @ARGV;
my @allow;
{
  open my $a, "<:raw", $allowfile or die; local $/; my $raw = <$a>;
  @allow = @{ JSON::PP->new->utf8->decode($raw) };
}
open my $fh, "<:utf8", $log or die;
my (@errors, @warnings, $cur);
while (my $line = <$fh>) {
  $line =~ s/\e\[[0-9;]*[A-Za-z]//g;
  $line =~ s/[\r\n]+$//;
  next if $line =~ /^\s*$/;
  if ($line =~ /^[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3} +(INFO|DEBUG|WARN|ERROR)\b *(.*)$/) {
    my ($level, $rest) = ($1, $2);
    $cur = undef;
    if ($level eq "WARN") { push @warnings, $rest; }
    elsif ($level eq "ERROR") {
      next if $rest =~ /Invalid \([0-9]+ files?, [0-9]+ errors?\)/;
      if ($rest =~ /^\S+ +Invalid +(\S+)$/) { $cur = { file => $1, lines => [] }; }
      else { $cur = { file => "", lines => [$rest] }; }
      push @errors, $cur;
    }
    next;
  }
  if ($line =~ /^\s+(\S.*)$/ && $cur) { push @{ $cur->{lines} }, $1; next; }
  my $hit = 0;
  for my $re (@allow) { if ($line =~ /$re/) { $hit = 1; last; } }
  push @warnings, $line unless $hit;
}
print JSON::PP->new->canonical->encode({ errors => \@errors, warnings => \@warnings }), "\n";
' "$log" "$allow"
