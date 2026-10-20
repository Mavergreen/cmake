#!/bin/sh
# platform: macOS-only -- package.sh reads the fixtures' slices with clang22's llvm-lipo, which pkgutil expands
#   usage: updater-slices-test.sh     package.sh refuses a universal cmake beside an x86_64-only updater
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/build/versions.sh"; . "$ROOT/build/msc.sh"
fail() { echo "FAIL: $1"; exit 1; }
t="$(mktemp -d "${TMPDIR:-/tmp}/cmake-updater-slices-test.XXXXXX")"; trap 'rm -rf "$t"' EXIT INT TERM
CL="$(sh "$ROOT/build/fetch-clang22.sh")"
SP="$(sh "$SHIPYARD_SCRIPTS/fetch_sparkle_framework.sh")/Versions/A/Sparkle"
[ "$("$CL/bin/llvm-lipo" -info "$SP" | sed -n 's/.*: //p' | xargs)" = "x86_64 arm64" ] \
  || fail "the fixture needs a two-slice Mach-O, and the pinned Sparkle is no longer one"
mkdir -p "$t/repo/build" "$t/repo/components/clang22" "$t/tree/bin" "$t/app/Contents/MacOS"
cp "$ROOT"/build/*.sh "$t/repo/build/"; cp "$ROOT/UPSTREAM_VERSION" "$t/repo/"
cp "$ROOT/components/clang22/version" "$t/repo/components/clang22/"
for b in cmake ctest cpack; do cp "$SP" "$t/tree/bin/$b"; done
"$CL/bin/llvm-lipo" -thin x86_64 "$SP" -output "$t/app/Contents/MacOS/cmake-updater"
printf '#!/bin/sh\necho %s\n' "$CL" > "$t/repo/build/fetch-clang22.sh"
printf '#!/bin/sh\n:\n' > "$t/repo/build/compat-gate.sh"
printf '#!/bin/sh\necho %s\n' "$t/app" > "$t/repo/build/build-updater.sh"
V="$KITWARE_VERSION-mavericks.1"
if out="$(MAVERICKS_BUILD_ROOT="$t/work" sh "$t/repo/build/package.sh" "$t/tree" "$V" "$t/out" 2>&1)"; then
  fail "package.sh must refuse a universal cmake beside an x86_64-only updater"
fi
case "$out" in *"updater is 'x86_64' but bin/cmake is 'x86_64 arm64'"*) ;; *) fail "the refusal must name both slice sets (got: $out)" ;; esac
[ -z "$(ls "$t/out" 2>/dev/null)" ] || fail "a refused package must leave no pkg in OUT"
echo "PASS: updater-slices"
