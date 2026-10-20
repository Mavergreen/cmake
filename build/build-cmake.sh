#!/bin/sh
# platform: macOS-only -- lipo and otool check the slice it builds
#   usage: build-cmake.sh --arch x86_64|arm64 --min-os VER --prefix DIR --sysroot DIR [--jobs N] [-- CMAKE-ARG...]
#          build-cmake.sh --fetch-only --dest DIR          (download + verify only; prints the path)
#          Builds ONE slice of CMake (one arch, one deployment floor) into a prefix, from Kitware's
#          SOURCE tarball for UPSTREAM_VERSION, verified against the release's own
#          cmake-<v>-SHA-256.txt, patched with patches/cmake/*.patch, and configured by shipyard-cmake.
#          build.sh runs it once per slice and merges the slices. The TARGET compiler is the
#          environment's CC/CXX (and CFLAGS/CXXFLAGS/LDFLAGS), which cmake honours; CMAKE-ARGs after
#          -- reach the configure. LIPO and OTOOL name the Mach-O readers (default lipo, otool).
#          KITWARE_URL_BASE overrides the download base (default
#          https://github.com/Kitware/CMake/releases/download). --sysroot DIR is required (the pinned
#          SDK: fetch_sdk.sh --arch <arch>) and is passed through as CMAKE_OSX_SYSROOT.
# platform: CMake is an ordinary CMake project, so another cmake can build it; CMake's own
#           ./bootstrap first compiles a stage-0 cmake that must RUN on this host, which a cross
#           slice cannot without Rosetta, and macOS 28 removes Rosetta.
set -eu
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH=""; MINOS=""; PREFIX=""; JOBS=""; FETCH_ONLY=""; DEST=""; SYSROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --arch) ARCH="$2"; shift 2;;
    --min-os) MINOS="$2"; shift 2;;
    --prefix) PREFIX="$2"; shift 2;;
    --jobs) JOBS="$2"; shift 2;;
    --sysroot) SYSROOT="$2"; shift 2;;
    --fetch-only) FETCH_ONLY=1; shift;;
    --dest) DEST="$2"; shift 2;;
    --) shift; break;;
    *) echo "build-cmake: unknown option $1" >&2; exit 2;;
  esac
done

V="$(tr -d ' \t\n' < "$REPO_ROOT/UPSTREAM_VERSION")"
[ -n "$V" ] || { echo "build-cmake: $REPO_ROOT/UPSTREAM_VERSION is empty" >&2; exit 1; }
BASE="${KITWARE_URL_BASE:-https://github.com/Kitware/CMake/releases/download}"
TARBALL="cmake-$V.tar.gz"
. "$REPO_ROOT/build/msc.sh"
. "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"

fetch_verified() {  # $1 = dir to download into; prints the tarball path
  mkdir -p "$1"
  shipyard_curl "$BASE/v$V/$TARBALL" "$1/$TARBALL" \
    || { echo "build-cmake: could not download $BASE/v$V/$TARBALL" >&2; return 1; }
  shipyard_curl "$BASE/v$V/cmake-$V-SHA-256.txt" "$1/cmake-$V-SHA-256.txt" \
    || { echo "build-cmake: could not download Kitware's checksum file for $V" >&2; return 1; }
  want="$(awk -v f="$TARBALL" '$2 == f { print $1 }' "$1/cmake-$V-SHA-256.txt")"
  [ -n "$want" ] || { echo "build-cmake: checksum file for $V does not list $TARBALL; refusing" >&2; return 1; }
  got="$(shasum -a 256 "$1/$TARBALL" | awk '{ print $1 }')"
  [ "$got" = "$want" ] \
    || { echo "build-cmake: checksum mismatch for $TARBALL (got $got, Kitware published $want); refusing" >&2; return 1; }
  printf '%s\n' "$1/$TARBALL"
}

if [ -n "$FETCH_ONLY" ]; then
  : "${DEST:?build-cmake: --fetch-only needs --dest}"
  fetch_verified "$DEST"; exit 0
fi

[ -n "$ARCH" ] && [ -n "$MINOS" ] && [ -n "$PREFIX" ] && [ -n "$SYSROOT" ] \
  || { echo "build-cmake: need --arch, --min-os, --prefix and --sysroot (the pinned SDK: fetch_sdk.sh --arch <arch>)" >&2; exit 2; }

# platform: CMAKE_SYSTEM_NAME is what makes CMAKE_CROSSCOMPILING true, so CMake REFUSES to run a
#           binary it just built for the target instead of running it and silently depending on
#           Rosetta. It wants the kernel's version, not the product's: Darwin 13 is macOS 10.9
#           (10.x -> x+4), Darwin 20 is macOS 11.0 (N -> N+9).
case "$MINOS" in
  10.[0-9]|10.[0-9][0-9]) DARWIN_V="$(( ${MINOS#10.} + 4 ))";;
  1[1-9].[0-9]*|[2-9][0-9].[0-9]*) DARWIN_V="$(( ${MINOS%%.*} + 9 ))";;
  *) echo "build-cmake: --min-os '$MINOS' is not a macOS version with a known Darwin release" >&2; exit 2;;
esac

HOSTCMAKE="$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"
"$HOSTCMAKE" --version >/dev/null 2>&1 || {
  echo "build-cmake: no usable shipyard-cmake (tried $HOSTCMAKE), and this recipe configures CMake with it" >&2
  echo "    install the shipyard pkg (https://github.com/Mavergreen/shipyard/releases), or in GitHub Actions" >&2
  echo "    use Mavergreen/shipyard/.github/actions/install@v1" >&2
  exit 1
}

[ -n "$JOBS" ] || JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"
[ -d "$SYSROOT" ] || { echo "build-cmake: --sysroot $SYSROOT is not a directory" >&2; exit 2; }

W="$(mktemp -d "${TMPDIR:-/tmp}/build-cmake.XXXXXX")"; trap 'rm -rf "$W"' EXIT
tb="$(fetch_verified "$W")"
tar -xzf "$tb" -C "$W"
cd "$W/cmake-$V"
for p in "$REPO_ROOT"/patches/cmake/*.patch; do
  [ -f "$p" ] || continue
  patch -p1 < "$p" || { echo "build-cmake: $p does not apply to CMake $V" >&2; exit 1; }
done
# platform: without CMAKE_USE_SYSTEM_LIBRARIES=0 (what ./bootstrap spelled --no-system-libs),
#           CMake's own configure finds and links whatever curl/zlib/etc. the build host has
#           installed (pkgsrc, Homebrew, MacPorts), which a user's Mac lacks. CMAKE_IGNORE_PREFIX_PATH
#           and the FIND_ROOT_PATH modes back it up: libraries, headers and packages come only from
#           the target SDK, while PROGRAM stays NEVER because the tools the build RUNS are the host's.
#           ccmake needs curses and is not shipped, so BUILD_CursesDialog=OFF.
# spec: README.md "No HTTPS" -- no OpenSSL means CMake's bundled curl has no macOS TLS backend, and
#       the OS's own curl (10.9's SDK: 7.30) is too old for CMake 4.4's cmCurl.cxx, which needs 7.34+
"$HOSTCMAKE" -S . -B "$W/build" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=Darwin \
  -DCMAKE_SYSTEM_VERSION="$DARWIN_V.0.0" \
  -DCMAKE_SYSTEM_PROCESSOR="$ARCH" \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MINOS" \
  -DCMAKE_OSX_SYSROOT="$SYSROOT" \
  -DCMAKE_FIND_ROOT_PATH="$SYSROOT" \
  -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
  -DCMAKE_USE_SYSTEM_LIBRARIES=0 \
  -DCMAKE_USE_OPENSSL=OFF \
  -DBUILD_CursesDialog=OFF \
  "-DCMAKE_IGNORE_PREFIX_PATH=/opt/pkg;/opt/local;/opt/homebrew;/usr/local;/sw" \
  -DBUILD_TESTING=OFF \
  "$@"
"$HOSTCMAKE" --build "$W/build" --parallel "$JOBS"
"$HOSTCMAKE" --install "$W/build"

# platform: a build-host package manager (pkgsrc, Homebrew, MacPorts) leaking into bin/* runs fine
#           here and fails to even launch on a box lacking that exact library at that exact path
for f in "$PREFIX"/bin/*; do
  "${LIPO:-lipo}" -info "$f" >/dev/null 2>&1 || continue
  bad="$("${OTOOL:-otool}" -L "$f" | sed 1d | awk '{print $1}' | grep -v -e '^/usr/lib/' -e '^/System/' || true)"
  [ -z "$bad" ] || { echo "build-cmake: $f links outside the OS: $bad" >&2; exit 1; }
  # platform: the arch reaches the compiler three ways (the -D above, CMake's Darwin defaults and
  #           clang22's clang.cfg --target=), so a dropped -D would still look green while the output
  #           became the host's arch; 10.9's lipo has no -archs, so this reads -info
  got="$("${LIPO:-lipo}" -info "$f" 2>/dev/null | sed -n 's/.*: //p' | xargs)"
  [ "$got" = "$ARCH" ] \
    || { echo "build-cmake: $f is '$got', not the requested $ARCH" >&2; exit 1; }
done

echo "build-cmake: CMake $V ($ARCH, min $MINOS) -> $PREFIX" >&2
