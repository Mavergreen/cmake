# Build ingredients

Everything baked into the shipped `cmake` `.pkg`, where it is pinned, and how a change reaches a release.
The *own upstream* is Kitware's CMake; an ingredient is anything else the artifact is built with.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| CMake source (own upstream), with the libraries it bundles (curl, libarchive, libuv, zlib and others; their licences install under `doc/cmake-4.4`) | `UPSTREAM_VERSION` | ✅ `github-releases` on `Kitware/CMake` | cuts `<ver>-mavericks.1` |
| clang22 N−1 (compiler, linker; the x86_64 slice's static libc++) | `components/clang22/version` | ✅ `github-releases` on `Mavergreen/clang-22`, `-mavericks.N` versioning | repackage → `-mavericks.(N+1)` |
| Recaulk (`librecaulk.a`, linked by clang22 N−1's `clang.cfg`; x86_64 only: `clock_gettime` and kin for libc++'s chrono) | `components/clang22/version` (moves with clang22) | ✅ via the clang22 pin | repackage → `-mavericks.(N+1)` |
| MacOSX10.9 and MacOSX11.3 SDKs | shipyard `fetch_sdk.sh` (pinned by hash) | ✅ moves with shipyard `@v1` | moving tag |
| Sparkle 1.27.3 (embedded in `cmake-updater.app`) | shipyard `fetch_sparkle_framework.sh` (pinned by hash) | ✅ moves with shipyard `@v1` | moving tag |
| shipyard-cmake (configures the build; not shipped) | shipyard `@v1` | ✅ moves with shipyard `@v1` | moving tag |

## CMake source verification

Kitware's release tarball, `cmake-<UPSTREAM_VERSION>.tar.gz`, verified against the same release's
`cmake-<UPSTREAM_VERSION>-SHA-256.txt` by `build/build-cmake.sh`. No hash is pinned here: Kitware's
own file vouches for a version nobody here has seen yet, so a Renovate bump needs no hand-written hash.

## Source changes

One, `patches/cmake/0001-libuv-darwin-mmsg-needs-10.10.patch`: CMake's bundled libuv gates its batched
UDP path on 10.7, but `recvmsg_x`/`sendmsg_x` arrived in 10.10. It is filed upstream. Delete it when
a CMake release carries the fix.

## Build

Each slice is configured by `shipyard-cmake` against CMake's own `CMakeLists.txt`, as a cross build
(`CMAKE_SYSTEM_NAME=Darwin`), so nothing the build makes is run on the build host. Both slices are
compiled by clang22 N−1: x86_64 against MacOSX10.9.sdk (10.9), arm64 against MacOSX11.3.sdk (11.0).
CMake links nothing from the build host (`CMAKE_USE_SYSTEM_LIBRARIES=0`), and `build-cmake.sh` refuses a
binary that links anything outside `/usr/lib` and `/System`. That is also why it has no TLS: see the
README.

On a modern Mac the slices are merged into one tree. On 10.9 the build makes x86_64 alone, named
`-x86_64-dev`, never published: clang22-cross runs only on arm64, and the clang22 that runs on 10.9
has no AArch64 backend. The merge uses the host's `lipo` (Xcode's, via shipyard's `lipo-merge-tree.sh`).

## Declared state

- upstream: UPSTREAM_VERSION
- clang22: components/clang22/version

## Conformance deviations

- arm64:build/build.sh: developers and CI on Apple Silicon run this CMake to build Mavericks artifacts, so the pkg carries an arm64 (11.0) slice beside the x86_64 (10.9) one. Revisit when nothing that produces Mavericks artifacts runs on arm64.
- static-cxx-runtime:build/build.sh: the x86_64 slice links LLVM 22's libc++ statically and uses Mavericks' system libc++abi and unwinder, clang22 N−1's own clang++.cfg default, until clang22 links the family's shared libc++.
- system-cxx-runtime:build/build.sh: the arm64 slice links macOS's /usr/lib/libc++.1.dylib, compiled against the MacOSX11.3 SDK's libc++ headers: no arm64 libcxx exists, and clang22-cross's runtimes are x86_64 only; revisit when an arm64 libcxx exists.
