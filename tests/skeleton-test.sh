#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $1"; exit 1; }
cd "$ROOT"
grep -Eqx '[0-9]+\.[0-9]+\.[0-9]+' UPSTREAM_VERSION || fail "UPSTREAM_VERSION must be a bare x.y.z"
grep -Eqx '[0-9]+\.[0-9]+\.[0-9]+-mavericks\.[0-9]+' components/clang22/version || fail "components/clang22/version: x.y.z-mavericks.N"
[ "$(ls patches/cmake)" = 0001-libuv-darwin-mmsg-needs-10.10.patch ] || fail "the libuv patch is the product's only source change"
for l in /VERSION /dist/ .superpowers/ .idea/; do grep -qxF "$l" .gitignore || fail ".gitignore must list $l"; done
[ "$(cat comment-reasons)" = "platform
spec" ] || fail "comment-reasons must opt into platform and spec"
. "$ROOT/build/versions.sh"
[ "$KITWARE_VERSION" = "$(cat UPSTREAM_VERSION)" ] && [ "$SHORT" = cmake ] && [ "$IDENTIFIER" = dev.mavergreen.cmake ] \
  && [ "$PREFIX" = /usr/local/mavergreen/cmake ] && [ "$TREE" = "$WORK/tree" ] || fail "build/versions.sh values"
[ "$(sh build/upstream-release-notes-url.sh 4.4.4)" = https://cmake.org/cmake/help/v4.4/release/4.4.html ] || fail "upstream notes URL"
. "$ROOT/build/msc.sh"
cmp -s build/msc.sh "$SHIPYARD_SCRIPTS/templates/msc.sh" || fail "build/msc.sh must equal shipyard's scripts/templates/msc.sh byte for byte (check 17)"
echo "PASS: skeleton"
