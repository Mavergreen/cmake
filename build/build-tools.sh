#!/bin/sh
# platform: host-agnostic
#   usage: build-tools.sh <build dir> <prefix>     prints the cmake and build tool that configured and built
#          <build dir>, as build-info key=value lines: <prefix>-cmake=<its --version>, and
#          <prefix>-build-tool=<name>:<its --version>
set -eu
D="${1:?usage: build-tools.sh <build dir> <prefix>}"; P="${2:?usage: build-tools.sh <build dir> <prefix>}"
cached() { sed -n "s/^$1:[A-Z]*=//p" "$D/CMakeCache.txt"; }
line() { "$1" --version | sed -n 1p; }
cm="$(cached CMAKE_COMMAND)"; mp="$(cached CMAKE_MAKE_PROGRAM)"
[ -x "$cm" ] && [ -x "$mp" ] || { echo "build-tools: $D/CMakeCache.txt names no runnable cmake and build tool" >&2; exit 1; }
echo "$P-cmake=$(line "$cm")"
echo "$P-build-tool=$(basename "$mp"):$(line "$mp")"
