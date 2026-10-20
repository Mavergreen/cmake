#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $1"; exit 1; }
t="$(mktemp -d "${TMPDIR:-/tmp}/cmake-clang22-test.XXXXXX")"; trap 'rm -rf "$t"' EXIT INT TERM
mkdir -p "$t/sy" "$t/bin" "$t/inst/bin"
. "$ROOT/build/msc.sh"; cp -R "$SHIPYARD_SCRIPTS"/. "$t/sy/"
cat > "$t/sy/fetch_product_pkg.sh" <<EOF2
#!/bin/sh
echo "\$*" >> "$t/calls"; d="\$(eval echo "\\\${\$#}")"; mkdir -p "\$d/bin"
for b in clang clang++ ld64.lld llvm-lipo llvm-ar llvm-ranlib llvm-otool llvm-nm llvm-strings llvm-strip llvm-objdump; do printf '#!/bin/sh\n' > "\$d/bin/\$b"; chmod +x "\$d/bin/\$b"; done
EOF2
printf '#!/bin/sh\n[ "$2" = dev.mavergreen.clang.clang22 ] && echo "version: %s"\n' "${RECEIPT:-0}" > "$t/bin/pkgutil"; chmod +x "$t/bin/pkgutil"
run() { PATH="$t/bin:$PATH" SHIPYARD_SCRIPTS="$t/sy" MAVERICKS_BUILD_ROOT="$t/root" CLANG22_INSTALLED="$t/inst" sh "$ROOT/build/fetch-clang22.sh"; }
V="$(cat "$ROOT/components/clang22/version")"

p="$(MAVERICKS_MODE=cross run)" || fail "cross mode failed"
grep -qx -- "--asset mavericks-clang-22-cross-$V.pkg clang22-cross $V $p" "$t/calls" || fail "cross mode must fetch clang22-cross $V (calls: $(cat "$t/calls"))"
: > "$t/calls"; p2="$(MAVERICKS_MODE=cross run)"; [ "$p2" = "$p" ] && [ ! -s "$t/calls" ] || fail "a fetched prefix must be reused"
rm "$p/bin/llvm-ranlib"; : > "$t/calls"; MAVERICKS_MODE=cross run >/dev/null; [ -s "$t/calls" ] || fail "a prefix lacking llvm-ranlib must be fetched again"

for b in clang clang++ ld64.lld llvm-lipo llvm-ar llvm-ranlib llvm-otool llvm-nm llvm-strings llvm-strip llvm-objdump; do printf '#!/bin/sh\n' > "$t/inst/bin/$b"; chmod +x "$t/inst/bin/$b"; done
printf '#!/bin/sh\n[ "$2" = dev.mavergreen.clang.clang22 ] && echo "version: %s"\n' "$V" > "$t/bin/pkgutil"
[ "$(MAVERICKS_MODE=native run)" = "$t/inst" ] || fail "native mode must use the installed clang22 whose receipt is $V"
printf '#!/bin/sh\n[ "$2" = dev.mavergreen.clang.clang22 ] && echo "version: 1.0.0-mavericks.1"\n' > "$t/bin/pkgutil"
: > "$t/calls"; MAVERICKS_MODE=native run >/dev/null || fail "native mode with a wrong receipt must fetch"
grep -q -- "--asset mavericks-clang-22-native-$V.pkg clang22 $V" "$t/calls" || fail "native mode must fetch clang22 $V when the installed one is another version"
echo "PASS: fetch-clang22"
