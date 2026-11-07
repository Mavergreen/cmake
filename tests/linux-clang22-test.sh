#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $1"; exit 1; }
t="$(mktemp -d "${TMPDIR:-/tmp}/linux-host.XXXXXX")"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/repo" "$t/sy"
cp -R "$ROOT/build" "$ROOT/components" "$t/repo/"; cp "$ROOT/UPSTREAM_VERSION" "$t/repo/"
. "$ROOT/build/msc.sh"; cp -R "$SHIPYARD_SCRIPTS"/. "$t/sy/"
cat > "$t/sy/fetch_product_tar.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$@" > "$CALLS"
mkdir -p "$4/bin"
for b in clang clang++ ld64.lld llvm-lipo llvm-ar llvm-ranlib llvm-otool llvm-nm llvm-strings llvm-strip llvm-objdump; do
  printf '#!/bin/sh\nexit 0\n' > "$4/bin/$b"; chmod +x "$4/bin/$b"
done
cat > "$4/bin/setup-sdk" <<'SDK'
#!/bin/sh
printf '%s\n' "$*" >> "$SETUP"; p="$(cd "$(dirname "$0")/.." && pwd)"; mkdir -p "$p/SDKs"; ln -sfn "$1" "$p/SDKs/MacOSX10.9.sdk"
SDK
chmod +x "$4/bin/setup-sdk"
printf '%s\n' "$4"
SH
printf '#!/bin/sh\nprintf "%%s\\n" "$SDK"\n' > "$t/sy/fetch_sdk.sh"
mkdir -p "$t/sdk" "$t/sdk2"
V="$(cat "$ROOT/components/clang22/version")"
SHA=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
printf '%s  clang22-%s-linux-x86_64.tar.gz\n' "$SHA" "$V" > "$t/repo/components/clang22/linux-sha256"
export CALLS="$t/calls" SETUP="$t/setup" SDK="$t/sdk" SHIPYARD_SCRIPTS="$t/sy" MAVERGREEN_CLANG22_CACHE="$t/cache" CLANG22_HOST=linux
prefix="$(sh "$t/repo/build/fetch-clang22.sh")"
[ "$(sed -n 1p "$CALLS")" = clang22 ] && [ "$(sed -n 2p "$CALLS")" = "$V" ] && [ "$(sed -n 3p "$CALLS")" = "$SHA" ] \
  && [ "$(sed -n 4p "$CALLS")" = "$prefix" ] || fail "Linux must fetch clang22 $V's archive by its pinned digest (calls: $(cat "$CALLS"))"
[ "$(cat "$SETUP")" = "$t/sdk" ] || fail "Linux must point the archive's clang.cfg at the pinned 10.9 SDK with setup-sdk"
[ "$(sh "$t/repo/build/fetch-clang22.sh")" = "$prefix" ] || fail "a second fetch must find the same prefix"
[ "$(cat "$SETUP")" = "$t/sdk" ] || fail "setup-sdk must not run again once the archive already points at the pinned SDK: it rewrites the shared cache on every call (calls: $(cat "$SETUP" | xargs))"
SDK="$t/sdk2" sh "$t/repo/build/fetch-clang22.sh" >/dev/null
[ "$(sed -n 2p "$SETUP")" = "$t/sdk2" ] || fail "setup-sdk must run when the archive points at another SDK (calls: $(cat "$SETUP" | xargs))"
rm "$CALLS"
printf '%s  clang22-old-linux-x86_64.tar.gz\n' "$SHA" > "$t/repo/components/clang22/linux-sha256"
if sh "$t/repo/build/fetch-clang22.sh" >/dev/null 2>&1; then fail "a digest for another version must be refused"; fi
[ ! -e "$CALLS" ] || fail "a stale digest must be refused before anything is fetched"
echo 'PASS: Linux clang fetch uses matching version/digest and refuses stale pins'
