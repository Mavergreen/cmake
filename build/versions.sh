# platform: host-agnostic
#   usage: . build/versions.sh     names, paths and pins every build script uses
: "${REPO_ROOT:=$(cd "$(dirname "$0")/.." && pwd)}"
export REPO_ROOT
KITWARE_VERSION="$(tr -d ' \t\n' < "$REPO_ROOT/UPSTREAM_VERSION")"
CLANG22_VERSION="$(tr -d ' \t\n' < "$REPO_ROOT/components/clang22/version")"
# spec: SKILL.md "Build OUT of the source tree" -- a checkout may live on NFS
WORK="${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}/mavergreen-cmake"
TREE="$WORK/tree"
PREFIX=/usr/local/mavergreen/cmake
SHORT=cmake
IDENTIFIER=dev.mavergreen.cmake
export KITWARE_VERSION CLANG22_VERSION WORK TREE PREFIX SHORT IDENTIFIER
