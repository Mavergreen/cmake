#!/bin/sh
# platform: host-agnostic
#   usage: build-updater.sh VERSION     prints cmake-updater.app, built with clang22 (build/fetch-clang22.sh): x86_64
#          10.9 and, on Linux or a modern Mac, arm64 11.0, merged with llvm-lipo; writes the build tools that
#          built it to build-tools.txt beside the app
# spec: tests/package-test.sh and tests/updater-slices-test.sh -- Apple Silicon installs this pkg too; an x86_64-only updater prompts for Rosetta there
set -eu
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/build/versions.sh"
. "$REPO_ROOT/build/msc.sh"
VER="${1:?usage: build-updater.sh VERSION}"
mode="$(sh "$REPO_ROOT/build/mode.sh")"
if [ "$mode" = linux ]; then SC="$(command -v cmake)"
else SC="$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"; fi
# spec: build/msc.sh -- the updater's modules come from the same shipyard as $SHIPYARD_SCRIPTS
SY="$(dirname "$SHIPYARD_SCRIPTS")"
CL="$(sh "$REPO_ROOT/build/fetch-clang22.sh")"
LIPO="$CL/bin/llvm-lipo"; OTOOL="$CL/bin/llvm-otool"; NM="$CL/bin/llvm-nm"; STRINGS="$CL/bin/llvm-strings"
export LIPO OTOOL NM STRINGS
slices="x86_64:10.9"; [ "$mode" = native ] || slices="x86_64:10.9 arm64:11.0"
for s in $slices; do
  a="${s%%:*}"; floor="${s#*:}"
  rm -rf "$WORK/updater-$a"
  "$SC" -S "$REPO_ROOT" -B "$WORK/updater-$a" -DCMAKE_TOOLCHAIN_FILE="$SY/MavericksToolchain.cmake" \
    -DMavericksShipyard_DIR="$SY" -DCMAKE_OSX_ARCHITECTURES="$a" \
    -DCMAKE_OBJC_COMPILER="$CL/bin/clang" -DCMAKE_OBJC_COMPILER_TARGET="$a-apple-macos$floor" \
    -DCMAKE_OBJC_FLAGS=--no-default-config -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld -DPKG_VERSION="$VER" >&2
  "$SC" --build "$WORK/updater-$a" >&2
done
out="$WORK/updater/cmake-updater.app"; rm -rf "$WORK/updater"; mkdir -p "$WORK/updater"
if [ "$mode" = native ]; then
  cp -R "$WORK/updater-x86_64/cmake-updater.app" "$out"
else
  sh "$SHIPYARD_SCRIPTS/lipo-merge-tree.sh" --a "$WORK/updater-x86_64/cmake-updater.app" \
    --b "$WORK/updater-arm64/cmake-updater.app" --out "$out" --require-archs "x86_64 arm64" >&2
fi
: > "$WORK/updater/build-tools.all"
for s in $slices; do sh "$REPO_ROOT/build/build-tools.sh" "$WORK/updater-${s%%:*}" updater >> "$WORK/updater/build-tools.all"; done
sort -u "$WORK/updater/build-tools.all" > "$WORK/updater/build-tools.txt"; rm -f "$WORK/updater/build-tools.all"
[ -z "$(cut -d= -f1 "$WORK/updater/build-tools.txt" | sort | uniq -d)" ] || { echo "build-updater: the slices were built by different tools" >&2; exit 1; }
echo "$out"
