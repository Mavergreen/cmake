#!/bin/sh
# platform: host-agnostic
#   usage: build.sh [OUT]     builds each slice this host can (Linux and a modern Mac: x86_64 and arm64; 10.9:
#          x86_64) into $WORK/slice-<arch>, takes a slice another host built from SLICE_X86_64 or
#          SLICE_ARM64 (a slice directory build.sh made there), gates each thin slice, merges the slices
#          into OUT (default $TREE) with clang22's llvm-lipo and gates OUT; writes the build tools that
#          built each slice (its <slice>.build-tools.txt) to $WORK/build-tools.txt, keyed build-<arch>-;
#          prints OUT
set -eu
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/build/versions.sh"
. "$REPO_ROOT/build/msc.sh"
OUT="${1:-$TREE}"
if [ -e "$OUT" ] && [ ! -x "$OUT/bin/cmake" ]; then
  echo "build: $OUT exists and is not a CMake tree; refusing to replace it" >&2; exit 2
fi
mode="$(sh "$REPO_ROOT/build/mode.sh")"
# platform: clang22-cross runs only on arm64 Macs and clang22's 10.9 compiler has no AArch64 backend, so 10.9
#           builds x86_64 alone and another host supplies arm64
case "$mode" in cross|linux) mine="x86_64 arm64" ;; native) mine=x86_64 ;; *) echo "build: mode '$mode'" >&2; exit 2 ;; esac
CL="$(sh "$REPO_ROOT/build/fetch-clang22.sh")"
LIPO="$CL/bin/llvm-lipo"; OTOOL="$CL/bin/llvm-otool"; export LIPO OTOOL

slice() {  # $1 = arch, $2 = prefix
  sdk="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch "$1")"
  # platform: CMake runs `strip` and asks `xcrun --find tapi` in every configure unless told which, and on
  #           10.9 both, like ar and ranlib, are Command Line Tools names
  set -- "$1" "$2" -DCMAKE_AR="$CL/bin/llvm-ar" -DCMAKE_RANLIB="$CL/bin/llvm-ranlib" \
    -DCMAKE_STRIP="$CL/bin/llvm-strip" -DCMAKE_TAPI=/usr/bin/false
  sa="$1"; p="$2"; shift 2
  if [ "$mode" = linux ]; then set -- "$@" -DCMAKE_INSTALL_NAME_TOOL="$CL/bin/llvm-install-name-tool" -DCMAKE_NM="$CL/bin/llvm-nm"; fi
  if [ "$sa" = arm64 ]; then
    # spec: INGREDIENTS.md "Conformance deviations" -- clang22-cross's clang.cfg targets x86_64 10.9 and its
    #       runtimes are x86_64 only, so arm64 runs without it, against the 11.3 SDK's own libc++ headers
    CC="$CL/bin/clang" CXX="$CL/bin/clang++" CFLAGS=--no-default-config \
      CXXFLAGS="--no-default-config -nostdinc++ -isystem $sdk/usr/include/c++/v1" \
      LDFLAGS="-fuse-ld=lld --ld-path=$CL/bin/ld64.lld -Wl,-dead_strip_dylibs" \
      sh "$REPO_ROOT/build/build-cmake.sh" --arch arm64 --min-os 11.0 --sysroot "$sdk" --prefix "$p" \
        --tools-out "$p.build-tools.txt" -- "$@" \
        -DCMAKE_C_COMPILER_TARGET=arm64-apple-macos11.0 -DCMAKE_CXX_COMPILER_TARGET=arm64-apple-macos11.0
  else
    CC="$CL/bin/clang" CXX="$CL/bin/clang++" \
      sh "$REPO_ROOT/build/build-cmake.sh" --arch x86_64 --min-os 10.9 --sysroot "$sdk" --prefix "$p" \
        --tools-out "$p.build-tools.txt" -- "$@"
  fi
}

have=""; d_x86_64=""; d_arm64=""
for a in x86_64 arm64; do
  if [ "$a" = x86_64 ]; then given="${SLICE_X86_64:-}"; else given="${SLICE_ARM64:-}"; fi
  if [ -n "$given" ]; then
    d="$given"; echo "build: $a slice from $d" >&2
  else
    case " $mine " in *" $a "*) : ;; *) echo "build: no $a slice -- this host cannot build it and none was given" >&2; continue ;; esac
    d="$WORK/slice-$a"; rm -rf "$d" "$d.build-tools.txt"; slice "$a" "$d" >&2
  fi
  [ -s "$d.build-tools.txt" ] || { echo "build: no $d.build-tools.txt names the tools that built the $a slice" >&2; exit 1; }
  sh "$REPO_ROOT/build/compat-gate.sh" "$d" "$a" >&2
  have="${have:+$have }$a"; if [ "$a" = x86_64 ]; then d_x86_64="$d"; else d_arm64="$d"; fi
done
[ -n "$have" ] || { echo "build: no slice built or given" >&2; exit 1; }
rm -rf "$OUT"; mkdir -p "$(dirname "$OUT")"
if [ "$have" = "x86_64 arm64" ]; then
  sh "$SHIPYARD_SCRIPTS/lipo-merge-tree.sh" --a "$d_x86_64" --b "$d_arm64" --out "$OUT" --require-archs "x86_64 arm64" >&2
else
  cp -R "$d_x86_64$d_arm64" "$OUT"
fi
sh "$REPO_ROOT/build/compat-gate.sh" "$OUT" "$have" >&2
{ [ -z "$d_x86_64" ] || sed 's/^build-/build-x86_64-/' "$d_x86_64.build-tools.txt"
  [ -z "$d_arm64" ] || sed 's/^build-/build-arm64-/' "$d_arm64.build-tools.txt"; } | sort > "$WORK/build-tools.txt"
echo "build: $OUT holds $have" >&2
echo "$OUT"
