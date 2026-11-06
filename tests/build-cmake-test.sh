#!/bin/sh
# platform: host-agnostic
#   usage: build-cmake-test.sh
#          build-cmake.sh must refuse bytes Kitware did not publish: the tarball is verified against
#          the release's own cmake-<v>-SHA-256.txt, fetched from the same place, so a tampered or
#          truncated download -- or a release whose checksum file does not list it -- fails BEFORE
#          anything is built.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../build/build-cmake.sh"
. "$here/../build/msc.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/build-cmake-test.XXXXXX")"; trap 'rm -rf "$work"' EXIT
v="$(tr -d ' \t\n' < "$here/../UPSTREAM_VERSION")"
[ -n "$v" ] || { echo "FAIL: UPSTREAM_VERSION is empty"; exit 1; }

rel="$work/rel/v$v"; mkdir -p "$rel"
echo "pretend source" > "$work/payload"; ( cd "$work" && tar -czf "$rel/cmake-$v.tar.gz" payload )
( cd "$rel" && shasum -a 256 "cmake-$v.tar.gz" > "cmake-$v-SHA-256.txt" )
base="file://$work/rel"

out="$(KITWARE_URL_BASE="$base" sh "$S" --fetch-only --dest "$work/d1")" \
  || { echo "FAIL: a tarball matching the published checksum must verify"; exit 1; }
[ -f "$out" ] || { echo "FAIL: --fetch-only must print the verified tarball's path; got '$out'"; exit 1; }

printf 'x' >> "$rel/cmake-$v.tar.gz"
if msg="$(KITWARE_URL_BASE="$base" sh "$S" --fetch-only --dest "$work/d2" 2>&1)"; then
  echo "FAIL: a tarball that does not match the published checksum must be refused"; exit 1
fi
printf '%s' "$msg" | grep -qi 'checksum' || { echo "FAIL: the refusal must say checksum; got: $msg"; exit 1; }

: > "$rel/cmake-$v-SHA-256.txt"
if KITWARE_URL_BASE="$base" sh "$S" --fetch-only --dest "$work/d3" >/dev/null 2>&1; then
  echo "FAIL: a checksum file without the tarball's line must be refused"; exit 1
fi

if sh "$S" --arch x86_64 >/dev/null 2>&1; then echo "FAIL: --arch without --min-os/--prefix must fail"; exit 1; fi

# spec: build/build-cmake.sh -- the configure needs CMAKE_SYSTEM_VERSION as a DARWIN release, and
#       the mapping is arithmetic on --min-os, so a floor it cannot map is refused before any download
if msg="$(sh "$S" --arch x86_64 --min-os banana --prefix "$work/p" --sysroot "$work/sdk" 2>&1)"; then
  echo "FAIL: an unmappable --min-os must be refused"; exit 1
fi
printf '%s' "$msg" | grep -q 'min-os' || { echo "FAIL: the refusal must name --min-os; got: $msg"; exit 1; }

# spec: build/build-cmake.sh -- a box without its host cmake (shipyard-cmake on a Mac, cmake on Linux) must
#       say so, and a Mac must say where to get shipyard-cmake, instead of failing later inside a download or a configure
if [ "$(sh "$here/../build/mode.sh")" = linux ]; then host=cmake; want='no cmake on PATH'; else host=shipyard-cmake; want='install@v1'; fi
if PATH=/usr/bin:/bin command -v "$host" >/dev/null 2>&1 || [ -e "/usr/local/mavergreen/bin/$host" ]; then
  echo "SKIP: $host is reachable from /usr/bin:/bin here, so the missing-host-cmake refusal cannot be exercised"
else
  if msg="$(PATH=/usr/bin:/bin sh "$S" --arch x86_64 --min-os 10.9 --prefix "$work/p" --sysroot "$work/sdk" 2>&1)"; then
    echo "FAIL: no $host must be refused"; exit 1
  fi
  printf '%s' "$msg" | grep -q "$want" \
    || { echo "FAIL: the refusal must say '$want'; got: $msg"; exit 1; }
fi

# spec: build/build-cmake.sh -- a missing --sysroot must be a usage error naming --sysroot (the
#       pinned SDK), not a silent fall-through to xcrun --show-sdk-path (the runner's SDK)
rc=0; out="$(sh "$S" --arch arm64 --min-os 11.0 --prefix "$work/p" 2>&1)" || rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q -- '--sysroot' \
  || { echo "FAIL: no --sysroot must be a usage error naming --sysroot (the pinned SDK), not a silent xcrun fallback; rc=$rc: $out"; exit 1; }

echo "PASS: build-cmake"
