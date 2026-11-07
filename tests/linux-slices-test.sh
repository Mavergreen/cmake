#!/bin/sh
# platform: host-agnostic
#   usage: linux-slices-test.sh     build.sh on Linux builds both slices as a modern Mac does: arm64 for
#          arm64-apple-macos11.0, linked by ld64.lld, against the 11.3 SDK's libc++ headers, with clang22's
#          Mach-O install_name_tool; merges them; and records the tools that built them
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $1"; exit 1; }
t="$(mktemp -d "${TMPDIR:-/tmp}/cmake-linux-slices.XXXXXX")"; trap 'rm -rf "$t"' EXIT INT TERM
mkdir -p "$t/repo/components" "$t/cl/bin" "$t/sy"
cp -R "$ROOT/build" "$ROOT/components" "$t/repo/"; cp "$ROOT/UPSTREAM_VERSION" "$t/repo/"
. "$ROOT/build/msc.sh"; cp -R "$SHIPYARD_SCRIPTS"/. "$t/sy/"
printf '#!/bin/sh\nprintf "/sdk-%%s\\n" "${2:-x86_64}"\n' > "$t/sy/fetch_sdk.sh"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "$MERGE"; a="$2"; while [ "$1" != --out ]; do shift; done; cp -R "$a" "$2"\n' > "$t/sy/lipo-merge-tree.sh"
printf '#!/bin/sh\necho %s\n' "$t/cl" > "$t/repo/build/fetch-clang22.sh"
printf '#!/bin/sh\nexit 0\n' > "$t/repo/build/compat-gate.sh"
cat > "$t/repo/build/build-cmake.sh" <<'SH'
#!/bin/sh
a=""; p=""; o=""; m=""; all="$*"
while [ $# -gt 0 ]; do case "$1" in --arch) a="$2"; shift 2 ;; --prefix) p="$2"; shift 2 ;; --tools-out) o="$2"; shift 2 ;; --min-os) m="$2"; shift 2 ;; *) shift ;; esac; done
{ echo "args=$all"; echo "CFLAGS=${CFLAGS:-}"; echo "CXXFLAGS=${CXXFLAGS:-}"; echo "LDFLAGS=${LDFLAGS:-}"; } > "$CALLS/$a"
mkdir -p "$p/bin"; for b in cmake ctest cpack; do printf '#!/bin/sh\n' > "$p/bin/$b"; chmod +x "$p/bin/$b"; done
printf 'build-cmake=cmake version 9\nbuild-build-tool=make:GNU Make 9\n' > "$o"
SH
mkdir "$t/calls"
run() { MAVERICKS_MODE="$1" CALLS="$t/calls" MERGE="$t/merge" SHIPYARD_SCRIPTS="$t/sy" MAVERICKS_BUILD_ROOT="$t/root" sh "$t/repo/build/build.sh"; }
out="$(run linux)" || fail "build.sh failed on Linux"
[ -f "$t/calls/x86_64" ] && [ -f "$t/calls/arm64" ] || fail "Linux must build both slices (built: $(ls "$t/calls" | xargs))"
grep -q -- '--min-os 10.9 .*--sysroot /sdk-x86_64' "$t/calls/x86_64" || fail "the x86_64 slice targets 10.9 on the 10.9 SDK: $(cat "$t/calls/x86_64")"
grep -q -- '--min-os 11.0 .*--sysroot /sdk-arm64' "$t/calls/arm64" || fail "the arm64 slice targets 11.0 on the 11.3 SDK: $(cat "$t/calls/arm64")"
grep -q -- '-DCMAKE_C_COMPILER_TARGET=arm64-apple-macos11.0' "$t/calls/arm64" && grep -q -- '-DCMAKE_CXX_COMPILER_TARGET=arm64-apple-macos11.0' "$t/calls/arm64" \
  || fail "the arm64 slice must name its target: --no-default-config leaves clang on the host's triple, which on Linux is not Darwin"
grep -q "^LDFLAGS=.*--ld-path=$t/cl/bin/ld64.lld" "$t/calls/arm64" || fail "the arm64 slice must link with clang22's ld64.lld, never the host's ld"
grep -q '^CXXFLAGS=.*-isystem /sdk-arm64/usr/include/c++/v1' "$t/calls/arm64" || fail "the arm64 slice compiles against the 11.3 SDK's libc++ headers"
for a in x86_64 arm64; do
  grep -q -- "-DCMAKE_INSTALL_NAME_TOOL=$t/cl/bin/llvm-install-name-tool" "$t/calls/$a" \
    || fail "on Linux the $a slice must install with clang22's llvm-install-name-tool, which writes Mach-O"
done
grep -q -- '--require-archs x86_64 arm64' "$t/merge" || fail "Linux must merge both slices: $(cat "$t/merge" 2>/dev/null)"
[ "$out" = "$t/root/mavergreen-cmake/tree" ] || fail "build.sh must print the merged tree (got '$out')"
[ "$(cat "$t/root/mavergreen-cmake/build-tools.txt")" = "build-arm64-build-tool=make:GNU Make 9
build-arm64-cmake=cmake version 9
build-x86_64-build-tool=make:GNU Make 9
build-x86_64-cmake=cmake version 9" ] || fail "build.sh must record the tools that built each slice: $(cat "$t/root/mavergreen-cmake/build-tools.txt")"
mkdir -p "$t/given/bin"; printf '#!/bin/sh\n' > "$t/given/bin/cmake"; chmod +x "$t/given/bin/cmake"; printf 'build-cmake=cmake version 3.31\nbuild-build-tool=make:GNU Make 3.81\n' > "$t/given.build-tools.txt"
rm -f "$t/calls"/*
( SLICE_X86_64="$t/given"; export SLICE_X86_64; run linux >/dev/null ) || fail "build.sh must merge an x86_64 slice another host built with tools of its own"
[ "$(ls "$t/calls" | xargs)" = arm64 ] || fail "a given x86_64 slice must not be rebuilt (built: $(ls "$t/calls" | xargs))"
[ "$(cat "$t/root/mavergreen-cmake/build-tools.txt")" = "build-arm64-build-tool=make:GNU Make 9
build-arm64-cmake=cmake version 9
build-x86_64-build-tool=make:GNU Make 3.81
build-x86_64-cmake=cmake version 3.31" ] || fail "build.sh must record each slice's own tools: $(cat "$t/root/mavergreen-cmake/build-tools.txt")"
rm -f "$t/calls"/* "$t/merge"
run native >/dev/null || fail "build.sh failed in native mode"
[ "$(ls "$t/calls" | xargs)" = x86_64 ] || fail "a 10.9 build makes x86_64 alone (built: $(ls "$t/calls" | xargs))"
if grep -q INSTALL_NAME_TOOL "$t/calls/x86_64"; then fail "only Linux names clang22's install_name_tool"; fi
echo "PASS: linux-slices"
