#!/bin/sh
# platform: macOS-only -- launches the installed Cocoa updater
#   usage: launch-updater.sh [APP]     launches cmake's updater (default: the installed one) check-only
#          (--background: a silent probe of its feed, no UI, no install) and gives it 180 seconds to exit by
#          itself. Exit 0 when it started, reached its check and exited 0; 1 otherwise, printing its output.
set -eu
APP="${1:-/Library/Application Support/Mavergreen/cmake-updater.app}"
exe="$APP/Contents/MacOS/cmake-updater"
[ -x "$exe" ] || { echo "FAIL: no updater at $exe"; exit 1; }
t="$(mktemp -d "${TMPDIR:-/tmp}/cmake-launch-updater.XXXXXX")"; trap 'rm -rf "$t"' EXIT INT TERM
"$exe" --background > "$t/log" 2>&1 &
pid=$!
waited=0
while kill -0 "$pid" 2>/dev/null; do
  if [ "$waited" -ge 180 ]; then
    kill "$pid" 2>/dev/null || :
    cat "$t/log"; echo "FAIL: the updater was still running after ${waited}s of a check-only launch"; exit 1
  fi
  sleep 1; waited=$((waited + 1))
done
rc=0; wait "$pid" || rc=$?
cat "$t/log"
[ "$rc" -eq 0 ] || { echo "FAIL: the check-only launch exited $rc"; exit 1; }
grep -q 'start: mode=background' "$t/log" || { echo 'FAIL: the updater never logged its start, so it did not run its own code'; exit 1; }
grep -q -E 'silent probe|auto-check disabled' "$t/log" || { echo 'FAIL: the updater started but never reached its check'; exit 1; }
echo "PASS: the updater launched check-only and exited 0 after ${waited}s"
