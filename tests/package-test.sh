#!/bin/sh
# platform: host-agnostic
#   usage: package-test.sh [PKG]     checks a package.sh pkg (default: the one dist/cmake-*.pkg)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/build/versions.sh"; . "$ROOT/build/msc.sh"
fail() { echo "FAIL: $1"; exit 1; }
if [ $# -ge 1 ]; then PKG="$1"; else
  set -- "$ROOT"/dist/cmake-*.pkg
  [ -f "$1" ] || { echo "not packaged (no dist/cmake-*.pkg) -- run build/build.sh, then build/package.sh TREE VERSION dist; skipping"; exit 77; }
  [ "$#" -eq 1 ] || fail "dist/ holds $# cmake pkgs; one build makes one"
  PKG="$1"
fi
mode="$(sh "$ROOT/build/mode.sh")"
# platform: 10.9's lipo and otool are Command Line Tools stubs; clang22's readers work on every host
CL="$(sh "$ROOT/build/fetch-clang22.sh")"
SD="$(sh "$SHIPYARD_SCRIPTS/fetch_stevedore.sh")"
pget() { "$SD" plist get "$2" "$1"; }
slices() { "$CL/bin/llvm-lipo" -info "$1" | sed -n 's/.*: //p' | xargs; }
t="$(mktemp -d "${TMPDIR:-/tmp}/cmake-package-test.XXXXXX")"; trap 'rm -rf "$t"' EXIT INT TERM
"$SD" expand "$PKG" "$t/x" >/dev/null
comp="$(grep -l "identifier=\"$IDENTIFIER\"" "$t"/x/*/PackageInfo | sed 1q)"
[ -n "$comp" ] || fail "$PKG holds no $IDENTIFIER component"
comp="$(dirname "$comp")"
mkdir "$t/root"; ( cd "$t/root" && gzip -dc "$comp/Payload" | cpio -id --quiet 2>/dev/null )
P="$t/root$PREFIX"
for f in bin/cmake bin/ctest bin/cpack mavergreen.plist; do [ -s "$P/$f" ] || fail "the pkg must install $PREFIX/$f"; done
[ -d "$P/share/cmake-$(echo "$KITWARE_VERSION" | cut -d. -f1,2)/Modules" ] || fail "the pkg must install CMake's modules (CMAKE_ROOT) beside bin/"
stray="$(cd "$t/root" && find . -type f | sed 's|^\./||' | grep -v -e "^${PREFIX#/}/" \
  -e '^Library/Application Support/Mavergreen/cmake-updater\.app/' \
  -e "^Library/LaunchAgents/$IDENTIFIER-updatecheck\.plist$" || true)"
[ -z "$stray" ] || fail "the payload must be rooted at $PREFIX (plus the updater and its agent): $(printf '%s\n' "$stray" | head -3)"

M="$P/mavergreen.plist"
[ "$(pget identifier "$M")" = "$IDENTIFIER" ] || fail "the manifest's identifier must be $IDENTIFIER"
[ "$(pget product "$M")" = "$SHORT" ] || fail "the manifest's product must be $SHORT"
ex=""; i=0
while e="$(pget "exports-exclude:$i" "$M" 2>/dev/null)"; do ex="$ex$e
"; i=$((i + 1)); done
ex="$(printf '%s' "$ex" | sed -n 's/^\(bin\/[a-z]*\)$/\1/p' | sort | xargs)"
[ "$ex" = "bin/cmake bin/cpack bin/ctest" ] || fail "exports-exclude must hold bin/cmake, bin/ctest and bin/cpack, so no bare name reaches the link farm (got '$ex')"

archs="$(slices "$P/bin/cmake")"
case "$archs:$(basename "$PKG")" in
  "x86_64 arm64:cmake-$KITWARE_VERSION"-mavericks.*-x86_64-dev.pkg) fail "a universal pkg must not be named -x86_64-dev" ;;
  "x86_64 arm64:"*) want=x86_64,arm64 ;;
  x86_64:*-x86_64-dev.pkg) want=x86_64
    [ "$mode" = native ] || fail "this host builds both slices, so its pkg must be the universal release pkg"
    echo "SKIP: $PKG is an x86_64-only dev pkg (a 10.9 build), so the release's x86_64,arm64 host check did not run" ;;
  *) fail "$(basename "$PKG") carries '$archs': a release pkg is x86_64 and arm64, and an x86_64-only one is named -x86_64-dev" ;;
esac

app="$t/root/Library/Application Support/Mavergreen/cmake-updater.app"
[ -d "$app" ] || fail "the pkg must install cmake-updater.app"
feed="$(pget SUFeedURL "$app/Contents/Info.plist")"
[ "$feed" = https://github.com/Mavergreen/cmake/releases/latest/download/cmake.xml ] || fail "the updater must poll cmake's feed (got $feed)"
ub="$app/Contents/MacOS/cmake-updater"
[ "$(slices "$ub")" = "$archs" ] || fail "the updater must carry bin/cmake's slices '$archs' (got '$(slices "$ub")'): an x86_64-only one prompts for Rosetta on Apple Silicon"
case "$archs" in *arm64*) uwant='x86_64 EXECUTE 10.9 10.9
arm64 EXECUTE 11.0 11.3' ;; *) uwant='x86_64 EXECUTE 10.9 10.9' ;; esac
ugot="$(LIPO="$CL/bin/llvm-lipo" OTOOL="$CL/bin/llvm-otool" sh "$SHIPYARD_SCRIPTS/macho-slices.sh" "$ub")"
[ "$ugot" = "$uwant" ] || fail "the updater's slices must be
$uwant
(x86_64 at 10.9 on the 10.9 SDK; arm64 at 11.0 on the 11.3 SDK), got
$ugot"
links="$("$CL/bin/llvm-objdump" --macho --arch=x86_64 --dylibs-used "$ub")" || fail "llvm-objdump could not read the updater"
links="$(printf '%s\n' "$links" | sed 1d)"
[ -n "$links" ] || fail "llvm-objdump read no linked libraries from the updater"
case "$links" in *"$PREFIX"*) fail "the updater must not link the product it updates" ;; esac
[ -f "$t/root/Library/LaunchAgents/$IDENTIFIER-updatecheck.plist" ] || fail "the pkg must install the update-check LaunchAgent"
sh "$SHIPYARD_SCRIPTS/assert_sparkle_pristine.sh" "$app/Contents/Frameworks/Sparkle.framework" \
  "$(sh "$SHIPYARD_SCRIPTS/fetch_sparkle_framework.sh")" || fail "the embedded Sparkle.framework must be the pinned one"
sh "$SHIPYARD_SCRIPTS/assert_pkg_installs_in_place.sh" "$PKG" || fail "the pkg must neither relocate nor version-skip a bundle"

d="$t/x/Distribution"
grep -q '<os-version min="10.9.5"' "$d" || fail "the Distribution must declare the 10.9.5 install floor"
[ "$(sed -n 's/.*<pkg-ref id="\([^"]*\)".*/\1/p' "$d" | sed -n 1p)" = dev.mavergreen.base ] || fail "dev.mavergreen.base must be first"
grep -q "id=\"$IDENTIFIER\"" "$d" || fail "the pkg must carry $IDENTIFIER"
declared="$(sed -n 's/.*hostArchitectures="\([^"]*\)".*/\1/p' "$d")"
[ "$declared" = "$want" ] || fail "the pkg must declare hostArchitectures $want, matching its cmake's slices (declares '$declared')"
info="$(dirname "$PKG")/build-info-$([ "$want" = x86_64 ] && echo dev || echo release).txt"
[ -f "$info" ] || fail "packaging must write $info"
key() { sed -n "s/^$1=//p" "$info"; }
tool_line() { "$1" --version 2>/dev/null | sed -n 1p | tr -d '\n' | tr -s '[:space:]' '_'; }
for k in build-cmake build-build-tool updater-cmake updater-build-tool; do
  [ -n "$(key "$k")" ] || fail "build-info must name $k, the tool that built what ships"
done
for d in "$WORK"/updater-*; do
  [ -f "$d/CMakeCache.txt" ] || continue
  cached() { sed -n "s/^$1:[A-Z]*=//p" "$d/CMakeCache.txt"; }
  [ "$(key updater-cmake)" = "$(tool_line "$(cached CMAKE_COMMAND)")" ] || fail "build-info must name the cmake that configured $d"
  mp="$(cached CMAKE_MAKE_PROGRAM)"
  [ "$(key updater-build-tool)" = "$(basename "$mp"):$(tool_line "$mp")" ] || fail "build-info must name the build tool that built $d ($mp)"
done
echo "PASS: package ($declared)"
