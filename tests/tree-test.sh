#!/bin/sh
# platform: macOS-only -- the tree's cmake runs here, and pkgutil expands clang22 for its Mach-O readers
#   usage: tree-test.sh [TREE]     checks a built tree (default: build.sh's) as the product promises it
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/build/versions.sh"; . "$ROOT/build/msc.sh"
fail() { echo "FAIL: $1"; exit 1; }
T="${1:-$TREE}"
C="$T/bin/cmake"
[ -x "$C" ] || { echo "not built (no $C) -- run build/build.sh; skipping"; exit 77; }
# platform: 10.9's otool cannot read LC_BUILD_VERSION and its lipo is a Command Line Tools stub without them;
#           clang22's readers work on every host, and llvm-otool -arch reads the wrong slice of a universal file
CL="$(sh "$ROOT/build/fetch-clang22.sh")"
LIPO="$CL/bin/llvm-lipo"; OBJDUMP="$CL/bin/llvm-objdump"
t="$(mktemp -d "${TMPDIR:-/tmp}/cmake-tree-test.XXXXXX")"; trap 'rm -rf "$t"' EXIT INT TERM
# spec: README.md "Stock behaviour" -- stock CMake searches the prefix above every PATH entry, so the checks
#       below run with no family directory on PATH and no CMAKE_PREFIX_PATH from the caller's shell
run() { env -i HOME="$HOME" PATH=/usr/bin:/bin "$C" "$@"; }

[ "$(run --version | sed -n 1p)" = "cmake version $KITWARE_VERSION" ] \
  || fail "bin/cmake --version must print 'cmake version $KITWARE_VERSION' (got '$(run --version | sed -n 1p)')"

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

printf '%s\n' 'file(DOWNLOAD https://example.invalid/x "${CMAKE_CURRENT_LIST_DIR}/x" STATUS st)' \
  'message("STATUS=${st}")' > "$t/https.cmake"
out="$(run -P "$t/https.cmake" 2>&1)"
case "$out" in *'STATUS=1;"Unsupported protocol"'*) ;; *) fail "file(DOWNLOAD https://...) must report Unsupported protocol, the documented limit (got: $out)" ;; esac

mkdir "$t/dep" "$t/proj"
printf '%s\n' 'cmake_minimum_required(VERSION 3.16)' 'project(dep NONE)' 'message(STATUS "dep-configured")' > "$t/dep/CMakeLists.txt"
printf '%s\n' 'cmake_minimum_required(VERSION 3.24)' 'project(fc NONE)' 'include(FetchContent)' \
  'FetchContent_Declare(dep URL https://example.invalid/dep.tar.gz)' 'FetchContent_MakeAvailable(dep)' > "$t/proj/CMakeLists.txt"
run -S "$t/proj" -B "$t/b-online" > "$t/online.out" 2>&1 && fail "a FetchContent download over HTTPS must fail, or the README's limit is wrong"
grep -q 'Unsupported protocol' "$t/online.out" || fail "the failed FetchContent download must say Unsupported protocol: $(cat "$t/online.out")"
out="$(run -S "$t/proj" -B "$t/b-srcdir" -DFETCHCONTENT_SOURCE_DIR_DEP="$t/dep" 2>&1)" \
  || fail "FetchContent must configure with FETCHCONTENT_SOURCE_DIR_DEP set: $out"
case "$out" in *dep-configured*) ;; *) fail "FETCHCONTENT_SOURCE_DIR_DEP must reach the dependency: $out" ;; esac
mkdir -p "$t/b-disc/_deps"; cp -R "$t/dep" "$t/b-disc/_deps/dep-src"
out="$(run -S "$t/proj" -B "$t/b-disc" -DFETCHCONTENT_FULLY_DISCONNECTED=ON 2>&1)" \
  || fail "FetchContent must configure with FETCHCONTENT_FULLY_DISCONNECTED=ON over sources placed in _deps: $out"
case "$out" in *dep-configured*) ;; *) fail "FETCHCONTENT_FULLY_DISCONNECTED=ON must use the placed sources: $out" ;; esac

fake="$t/root/usr/local/mavergreen/fake/share/cmake/Fake"; mkdir -p "$fake" "$t/stock"
echo 'set(Fake_FOUND TRUE)' > "$fake/FakeConfig.cmake"
printf '%s\n' 'cmake_minimum_required(VERSION 3.16)' 'project(stock NONE)' 'find_package(Fake CONFIG QUIET)' \
  'message(STATUS "FAKE=${Fake_FOUND}")' > "$t/stock/CMakeLists.txt"
found() { l="$1"; shift; run -S "$t/stock" -B "$t/b-$l" -DCMAKE_FIND_ROOT_PATH="$t/root" "$@" 2>&1 | sed -n 's/^-- FAKE=//p'; }
[ "$(found plain)" = 0 ] || fail "plain find_package(Fake) must not find a package under /usr/local/mavergreen/fake: the product carries no family search paths"
[ "$(found asked -DCMAKE_PREFIX_PATH=/usr/local/mavergreen/fake)" = 1 ] \
  || fail "find_package(Fake) must find it when asked with CMAKE_PREFIX_PATH, or the check above proves nothing"
echo "PASS: tree ($archs)"
