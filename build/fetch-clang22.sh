#!/bin/sh
# platform: host-agnostic
#   usage: fetch-clang22.sh     prints the prefix of clang22 N-1 (components/clang22/version) for this host,
#          through shipyard's fetch_clang22.sh: the Linux archive on Linux, the cross pkg on a modern Mac, the
#          native pkg on 10.9. On Linux the archive's clang.cfg is then pointed at the pinned 10.9 SDK.
# spec: components/clang22/version -- release N of a product is built by clang22 N-1, pinned as an ingredient
set -eu
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/build/msc.sh"
d="$(sh "$SHIPYARD_SCRIPTS/fetch_clang22.sh" "$REPO_ROOT/components/clang22")"
for b in clang clang++ ld64.lld llvm-lipo llvm-ar llvm-ranlib llvm-otool llvm-nm llvm-strings llvm-strip llvm-objdump; do
  [ -x "$d/bin/$b" ] || { echo "fetch-clang22: $d lacks bin/$b" >&2; exit 1; }
done
host="${CLANG22_HOST:-}"; [ -n "$host" ] || { [ "$(uname -s)" = Linux ] && host=linux; } || :
if [ "$host" = linux ]; then
  "$d/bin/setup-sdk" "$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")" >&2
fi
echo "$d"
