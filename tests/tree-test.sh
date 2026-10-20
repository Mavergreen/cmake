#!/bin/sh
# platform: macOS-only -- the tree's cmake runs here, and pkgutil expands clang22 for its Mach-O readers
#   usage: tree-test.sh [TREE]     checks a built tree (default: build.sh's) as the product promises it
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/build/versions.sh"; . "$ROOT/build/msc.sh"; . "$ROOT/tests/lib/stock-cases.sh"
fail() { echo "FAIL: $1"; exit 1; }
T="${1:-$TREE}"
C="$T/bin/cmake"
[ -x "$C" ] || { echo "not built (no $C) -- run build/build.sh; skipping"; exit 77; }
# platform: 10.9's otool cannot read LC_BUILD_VERSION and its lipo is a Command Line Tools stub without them;
#           clang22's readers work on every host, and llvm-otool -arch reads the wrong slice of a universal file
CL="$(sh "$ROOT/build/fetch-clang22.sh")"
LIPO="$CL/bin/llvm-lipo"; OBJDUMP="$CL/bin/llvm-objdump"
t="$(mktemp -d "${TMPDIR:-/tmp}/cmake-tree-test.XXXXXX")"; trap 'rm -rf "$t"' EXIT INT TERM

archs="$("$LIPO" -info "$C" | sed -n 's/.*: //p' | xargs)"
case "$archs" in
  "x86_64 arm64") ;;
  x86_64) [ "${MAVERICKS_MODE:-$(sh "$SHIPYARD_SCRIPTS/mavericks_mode.sh")}" = native ] \
            || fail "bin/cmake is x86_64 alone, but this host builds both slices"
          echo "SKIP: $T has no arm64 slice (a 10.9 build makes x86_64 alone), so the universal and arm64 checks did not run" ;;
  *) fail "bin/cmake must be x86_64 and arm64 (got '$archs')" ;;
esac
for b in ctest cpack; do
  [ "$("$LIPO" -info "$T/bin/$b" | sed -n 's/.*: //p' | xargs)" = "$archs" ] || fail "bin/$b must carry the same slices as bin/cmake ($archs)"
done

minos() {  # $1 = arch, $2 = file: the slice's minimum macOS, from either load command
  "$OBJDUMP" --macho --arch="$1" --private-headers "$2" | awk '
    /cmd LC_VERSION_MIN_MACOSX/ { v = 1 } v && $1 == "version" { print $2; exit }
    /cmd LC_BUILD_VERSION/ { b = 1 } b && $1 == "minos" { print $2; exit }'
}
[ "$(minos x86_64 "$C")" = 10.9 ] || fail "the x86_64 slice's minimum must be 10.9 (got '$(minos x86_64 "$C")')"
case "$archs" in *arm64*) [ "$(minos arm64 "$C")" = 11.0 ] || fail "the arm64 slice's minimum must be 11.0 (got '$(minos arm64 "$C")')" ;; esac

n=0
for f in $(find "$T" -type f \( -perm -u+x -o -name "*.dylib" -o -name "*.so" \)); do
  "$LIPO" -info "$f" >/dev/null 2>&1 || continue
  n=$((n + 1))
  for a in $archs; do
    bad="$("$OBJDUMP" --macho --arch="$a" --dylibs-used "$f" | sed 1d | awk '{print $1}' | grep -v -e '^/usr/lib/' -e '^/System/' || true)"
    [ -z "$bad" ] || fail "${f#"$T"/} ($a) links outside /usr/lib and /System: $bad"
  done
done
[ "$n" -ge 3 ] || fail "found $n Mach-O files under $T; cmake, ctest and cpack at least"

stock_cases "$C" "$KITWARE_VERSION" "$t"
echo "PASS: tree ($archs)"
