#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
R="$ROOT/.github/workflows/release.yml"
fail() { echo "FAIL: $1"; exit 1; }
code="$(grep -v '^[[:space:]]*#' "$R")"
line_of() { printf '%s\n' "$code" | grep -n -e "$1" | sed -n '1s/:.*//p'; }
has() { printf '%s\n' "$code" | grep -q -e "$1"; }
job() { printf '%s\n' "$code" | awk -v j="$1" '$0 ~ "^  "j":"{f=1;print;next} /^  [a-z][a-z-]*:$/{f=0} f'; }

printf '%s\n' "$code" | awk '/^  pull_request:/{f=1;next} f&&/branches:/{print;exit}' | grep -q '\[main\]' \
  || fail "release.yml must build pull requests to main: Renovate's automerge waits on that check"
printf '%s\n' "$code" | awk '/^  push:/{f=1;next} f&&/branches/{print;exit}' | grep -q "branches-ignore: \['renovate/\*\*'\]" \
  || fail "release.yml must build every branch push but Renovate's: a branch goes green before main does"
ver="$(job ver)"
printf '%s\n' "$ver" | grep -q 'runs-on: ubuntu-latest' || fail "the ver job must run on Linux: macOS runners are scarce"
printf '%s\n' "$ver" | grep -q 'release-needed.sh' || fail "a dispatch that is not a repackage must publish only a declared state no release carries (release-needed.sh)"
printf '%s\n' "$code" | awk '/^  workflow_dispatch:/{f=1;next} /^  [a-z_]+:/{f=0} f' | grep -q '^      reconcile:' \
  || fail "release.yml must accept reconcile.yml's dispatch-field, reconcile=true"
grep -q 'dispatch-field: reconcile=true' "$ROOT/.github/workflows/reconcile.yml" \
  || fail "reconcile.yml must dispatch with reconcile=true, so ver re-asks release-needed.sh and publishes a never-released upstream as N; its default, local_release=true, would cut N+1"

build="$(job build)"
printf '%s\n' "$build" | grep -q 'runs-on: macos-' || fail "the build job must run on a macOS runner: it builds both slices"
want="cmake-slices-\${{ hashFiles('UPSTREAM_VERSION', 'components/clang22/version', 'patches/**', 'build/*.sh') }}"
keys="$(printf '%s\n' "$build" | sed -n 's/^ *key: //p' | sort -u)"
[ "$keys" = "$want" ] && [ "$(printf '%s\n' "$build" | grep -c '^ *key: ')" = 2 ] \
  || fail "the slice cache's restore and save keys must both hash exactly this repo's CMake inputs (UPSTREAM_VERSION, components/clang22/version, patches/**, build/*.sh), so only they rebuild CMake (got '$keys')"
if printf '%s\n' "$build" | grep -q 'uses: actions/cache@'; then fail "the slice cache must be split into actions/cache/restore and actions/cache/save, so a publishing run can skip the restore"; fi
printf '%s\n' "$build" | awk '/^      - /{c=0} /if: needs\.ver\.outputs\.publish != .yes./{c=1} c&&/uses: actions\/cache\/restore@/{ok=1} END{exit !ok}' \
  || fail "the slice restore must be skipped when publish is yes: a release builds fresh, never from slices an older shipyard@v1 (and its SDK pins) built"
printf '%s\n' "$build" | grep -q 'uses: actions/cache/save@' || fail "the slice cache must be saved after the build, or no run ever restores it"
printf '%s\n' "$build" | grep -q 'SLICE_X86_64=' && printf '%s\n' "$build" | grep -q 'SLICE_ARM64=' \
  || fail "a cache hit must reach build.sh as SLICE_X86_64 and SLICE_ARM64, so the restored slices are gated and merged like built ones"
has 'sh build/build.sh' || fail "release.yml must build cmake"
grep -q 'compat-gate.sh' "$ROOT/build/build.sh" || fail "build.sh must gate cmake as 10.9-safe before merging it"
has 'sh build/package.sh' || fail "release.yml must package cmake"
has 'run-repo-tests.sh' || fail "release.yml must run the repo's tests"
if has 'rosetta'; then fail "release.yml must not use Rosetta: the shipped x86_64 cmake runs on 10.9, in the vm-test job"; fi
if grep -q '^- rosetta:' "$ROOT/INGREDIENTS.md"; then fail "nothing uses Rosetta, so INGREDIENTS.md declares no Rosetta use"; fi
b="$(line_of 'sh build/build.sh')"; p="$(line_of 'sh build/package.sh')"; t="$(line_of 'run-repo-tests.sh')"
[ -n "$b" ] && [ -n "$p" ] && [ -n "$t" ] && [ "$b" -lt "$p" ] && [ "$p" -lt "$t" ] \
  || fail "build, then package, then run-repo-tests.sh: tree-test and package-test check what the build made"
has 'check-artifact-conformance.sh' || fail "release.yml must check artifact conformance"

vm="$(job vm-test)"
printf '%s\n' "$vm" | grep -q 'uses: Mavergreen/mavericks-vm@v1' || fail "a vm-test job must boot Mac OS X 10.9 with Mavergreen/mavericks-vm"
printf '%s\n' "$vm" | grep -q 'needs: \[ver, build\]' || fail "vm-test must test the pkg the build job made"
printf '%s\n' "$vm" | grep -q 'installer -pkg "dist/cmake-$CMAKE_FULL_VERSION.pkg"' || fail "vm-test must install this run's pkg in the guest"
printf '%s\n' "$vm" | grep -q 'sh tests/on-target.sh "$CMAKE_FULL_VERSION"' || fail "vm-test must run tests/on-target.sh against the installed version: it is the only run of the x86_64 cmake"
printf '%s\n' "$vm" | grep -q 'packages: write' || fail "vm-test needs packages: write for mavericks-vm's shared guest cache"
printf '%s\n' "$code" | awk '/^  publish:/{f=1;next} /^  [a-z][a-z-]*:$/{f=0} f&&/needs:/' | grep -q 'vm-test' \
  || fail "publish must wait for vm-test: a cmake that did not run on 10.9 must not ship"

notes="$(line_of 'release-notes.sh')"; state="$(line_of 'release-state-record.sh')"
sign="$(line_of 'sign_and_appcast.sh')"; publish="$(line_of 'publish-release.yml')"
[ -n "$notes" ] && [ -n "$state" ] && [ -n "$sign" ] && [ -n "$publish" ] \
  || fail "release.yml must generate notes, record the state, sign the appcast and publish"
[ "$notes" -lt "$state" ] && [ "$state" -lt "$sign" ] && [ "$sign" -lt "$publish" ] \
  || fail "notes, then the state marker, then signing, then publishing: the appcast and the Release must carry the same notes"
has 'sign_and_appcast.sh" --product cmake --feed-dir dist' || fail "the appcast must be cmake.xml, signed by sign_and_appcast.sh"
has 'scan-for-key.yml' || fail "a signing run must scan its logs for the key before publishing"
for j in scan publish; do
  job "$j" | grep -q 'artifact: mavergreen-cmake' || fail "$j must use only the mavergreen-cmake artifact"
done
echo "PASS: workflow invariants"
