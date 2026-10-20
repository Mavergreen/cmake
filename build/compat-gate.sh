#!/bin/sh
# platform: macOS-only -- assert_binary_compatible.sh reads Mach-O
#   usage: compat-gate.sh <tree> "<arch ...>"     the tree's cmake, ctest and cpack are exactly those
#          archs, 10.9-safe in x86_64 and 11.0 in arm64
set -eu
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/build/msc.sh"
T="${1:?usage: compat-gate.sh <tree> \"<arch ...>\"}"; ARCHS="${2:?usage: compat-gate.sh <tree> \"<arch ...>\"}"
# platform: 10.9's lipo, otool, nm and strings are Command Line Tools stubs; clang22's readers are on every host
CL="$(sh "$REPO_ROOT/build/fetch-clang22.sh")"
LIPO="$CL/bin/llvm-lipo"; OTOOL="$CL/bin/llvm-otool"; NM="$CL/bin/llvm-nm"; STRINGS="$CL/bin/llvm-strings"
export LIPO OTOOL NM STRINGS
req=""
# platform: 10.9's libSystem has no clock_gettime, which libc++'s chrono calls; Recaulk (clang22's clang.cfg
#           links librecaulk.a) must define it in the x86_64 slice, the only one the guard reads for this
case " $ARCHS " in *" x86_64 "*) req=_clock_gettime ;; esac
MAVERICKS_DEVIATIONS_ROOT="$REPO_ROOT" MAVERICKS_ALLOW_ARCHS="$ARCHS" MAVERICKS_REQUIRE_DEFINED_SYMBOLS="$req" \
  sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$T/bin/cmake" "$T/bin/ctest" "$T/bin/cpack"
