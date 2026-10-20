#!/bin/sh
# platform: macOS-only -- runs the installed cmake, and PlistBuddy reads its manifest
#   usage: on-target.sh [VERSION]     checks the cmake pkg installed at /usr/local/mavergreen/cmake, which must be
#          VERSION (<upstream>-mavericks.N), as the product promises it: the release's vm-test job installs the
#          run's pkg in a 10.9 guest and runs this. With no VERSION it skips: the build host's cmake is not this build.
#          MAVERGREEN_CMAKE_PREFIX replaces the prefix, to rehearse against a staged tree.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/stock-cases.sh"
fail() { echo "FAIL: $1"; exit 1; }
V="${1:-}"
[ -n "$V" ] || { echo "no VERSION given: on-target.sh checks an installed pkg of a known version; skipping"; exit 77; }
P="${MAVERGREEN_CMAKE_PREFIX:-/usr/local/mavergreen/cmake}"
[ -f "$P/mavergreen.plist" ] || fail "no cmake pkg is installed at $P (no mavergreen.plist)"
got="$(/usr/libexec/PlistBuddy -c 'Print :version' "$P/mavergreen.plist")"
[ "$got" = "$V" ] || fail "$P holds cmake $got, not $V: install this run's pkg first"
for b in cmake ctest cpack; do
  [ ! -e "/usr/local/mavergreen/bin/$b" ] || fail "the link farm must hold no bare $b, which would shadow the user's own"
done
t="$(mktemp -d "${TMPDIR:-/tmp}/cmake-on-target.XXXXXX")"; trap 'rm -rf "$t"' EXIT INT TERM
stock_cases "$P/bin/cmake" "${V%-mavericks.*}" "$t"
echo "PASS: on-target ($(sw_vers -productVersion), $V)"
