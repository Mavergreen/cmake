#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/build/msc.sh"
fail() { echo "FAIL: $1"; exit 1; }

cd "$ROOT"
out="$(sh "$SHIPYARD_SCRIPTS/check-family-conventions.sh" 2>&1)" \
  || { printf '%s\n' "$out"; fail "the family conventions gate must pass"; }
case "$out" in
  *"nothing to check"*) printf '%s\n' "$out"; fail "the gate must actually check this repo, not wave it through as a non-product repo" ;;
esac
echo "PASS: family conventions"
