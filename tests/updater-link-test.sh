#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $1"; exit 1; }
t="$(mktemp -d "${TMPDIR:-/tmp}/cmake-updater-link.XXXXXX")"; trap 'rm -rf "$t"' EXIT INT TERM
mkdir -p "$t/repo" "$t/bin" "$t/cl/bin" "$t/sy"
cp -R "$ROOT/build" "$ROOT/components" "$t/repo/"; cp "$ROOT/UPSTREAM_VERSION" "$t/repo/"
. "$ROOT/build/msc.sh"; cp -R "$SHIPYARD_SCRIPTS"/. "$t/sy/"
printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$t/cl" > "$t/repo/build/fetch-clang22.sh"
printf '#!/bin/sh\nwhile [ "$1" != --a ]; do shift; done; a="$2"\nwhile [ "$1" != --out ]; do shift; done; cp -R "$a" "$2"\n' > "$t/sy/lipo-merge-tree.sh"
cat > "$t/bin/cmake" <<'SH'
#!/bin/sh
if [ "$1" = --version ]; then echo "cmake version 9.9.9"; exit 0; fi
if [ "$1" = --build ]; then
  m="$2/$APP/Contents/MacOS"; mkdir -p "$m"; printf '#!/bin/sh\n' > "$m/${APP%.app}"; chmod +x "$m/${APP%.app}"; exit 0
fi
b=; prev=; for x in "$@"; do [ "$prev" = -B ] && b="$x"; prev="$x"; done
mkdir -p "$b"; printf '%s\n' "$@" > "$ARGS-${b##*/}"
printf 'CMAKE_COMMAND:INTERNAL=%s\nCMAKE_MAKE_PROGRAM:FILEPATH=%s\n' "$0" "$(dirname "$0")/make" > "$b/CMakeCache.txt"
SH
printf '#!/bin/sh\necho "GNU Make 9"\n' > "$t/bin/make"
cp "$t/bin/cmake" "$t/bin/shipyard-cmake"; chmod +x "$t/bin"/*
for mode in linux cross native; do
  if [ "$mode" = native ]; then archs=x86_64; else archs="x86_64 arm64"; fi
  PATH="$t/bin:$PATH" APP=cmake-updater.app ARGS="$t/args-$mode" SHIPYARD_SCRIPTS="$t/sy" MAVERICKS_MODE="$mode" \
    MAVERICKS_BUILD_ROOT="$t/w-$mode" sh "$t/repo/build/build-updater.sh" 9.9.9-mavericks.1 >/dev/null || fail "build-updater.sh failed in $mode mode"
  for a in $archs; do
    A="$t/args-$mode-updater-$a"
    [ -f "$A" ] || fail "$mode mode must configure the $a updater"
    grep -Fx -- "-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld --ld-path=$t/cl/bin/ld64.lld" "$A" >/dev/null \
      || fail "the $mode $a updater must link with clang22's ld64.lld, named by --ld-path, never a host ld (got: $(grep LINKER "$A"))"
  done
done
echo "PASS: updater-link"
