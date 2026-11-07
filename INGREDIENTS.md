# Build ingredients

Everything baked into the shipped `cmake` `.pkg`, where it is pinned, and how a change reaches a release.
The *own upstream* is Kitware's CMake; an ingredient is anything else the artifact is built with.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| CMake source (own upstream), with the libraries it bundles (curl, libarchive, libuv, zlib and others; their licences install under `doc/cmake-4.4`) | `UPSTREAM_VERSION` | ✅ `github-releases` on `Kitware/CMake` | cuts `<ver>-mavericks.1` |
| clang22 N−1 (compiler, linker, Mach-O tools; the x86_64 slice's static libc++; builds the updater too) | `components/clang22/version`, plus the Linux archive's digest in `components/clang22/linux-sha256` | ✅ `github-releases` on `Mavergreen/clang-22`, `-mavericks.N` versioning; the pins bot (`.github/workflows/pins-bot.yml`) verifies the new release's Linux archive against its `SHA256SUMS` and writes `linux-sha256` on Renovate's branch | repackage → `-mavericks.(N+1)` |
| Recaulk (`librecaulk.a`, linked by clang22 N−1's `clang.cfg`; x86_64 only: `clock_gettime` and kin for libc++'s chrono) | `components/clang22/version` (moves with clang22) | ✅ via the clang22 pin | repackage → `-mavericks.(N+1)` |
| MacOSX10.9 and MacOSX11.3 SDKs | shipyard `fetch_sdk.sh` (pinned by hash) | ✅ moves with shipyard `@v1` | moving tag |
| Sparkle 1.27.3 (embedded in `cmake-updater.app`) | shipyard `fetch_sparkle_framework.sh` (pinned by hash) | ✅ moves with shipyard `@v1` | moving tag |
| shipyard-cmake (configures a Mac's build; not shipped) | shipyard `@v1` | ✅ moves with shipyard `@v1` | moving tag |
| Linux host CMake and make (configure and build both slices and the updater on Linux; a Mac's builds use the make on `PATH`) | runner-provided, unpinned; build-info records each `--version`, per slice (`build-x86_64-cmake`, `build-x86_64-build-tool`, `build-arm64-cmake`, `build-arm64-build-tool`) and for the updater (`updater-cmake`, `updater-build-tool`) | ❌ untrackable here: the runner image provides them, so no pin exists to track. Exit: a pinned cmake on Linux hosts (shipyard QUEUE) | none; a runner image update can change them |

## CMake source verification

Kitware's release tarball, `cmake-<UPSTREAM_VERSION>.tar.gz`, verified against the same release's
`cmake-<UPSTREAM_VERSION>-SHA-256.txt` by `build/build-cmake.sh`. No hash is pinned here: Kitware's
own file vouches for a version nobody here has seen yet, so a Renovate bump needs no hand-written hash.

## Source changes

One, `patches/cmake/0001-libuv-darwin-mmsg-needs-10.10.patch`: CMake's bundled libuv gates its batched
UDP path on 10.7, but `recvmsg_x`/`sendmsg_x` arrived in 10.10. It is filed upstream. Delete it when
a CMake release carries the fix.

## Build

Each slice is configured against CMake's own `CMakeLists.txt` as a cross build (`CMAKE_SYSTEM_NAME=Darwin`),
so nothing the build makes is run on the build host: by the host's `cmake` on Linux, by `shipyard-cmake` on
a Mac. Both slices are compiled by clang22 N−1 (shipyard's `fetch_clang22.sh`: the Linux archive on Linux,
the cross pkg on a modern Mac, the native pkg on 10.9): x86_64 against MacOSX10.9.sdk (10.9), arm64 against
MacOSX11.3.sdk (11.0), linked by `ld64.lld`. CMake links nothing from the build host
(`CMAKE_USE_SYSTEM_LIBRARIES=0`), and `build-cmake.sh` refuses a binary that links anything outside
`/usr/lib` and `/System`. That is also why it has no TLS: see the README.

Linux and a modern Mac build both slices and merge them into one tree with clang22's `llvm-lipo`
(shipyard's `lipo-merge-tree.sh`). On 10.9 the build makes x86_64 alone, named `-x86_64-dev`, never
published: clang22-cross runs only on arm64, and the clang22 that runs on 10.9 has no AArch64 backend. The
Sparkle updater is built the same way, one configure per arch with clang22, and merged likewise. Packaging
runs on shipyard's stevedore seams, so CI builds, tests, packages and signs on Linux.

## Running the shipped cmake

Neither slice runs on the Linux build host. The `vm-test` job boots Mac OS X 10.9.5 with
`Mavergreen/mavericks-vm`, installs the built pkg, runs `tests/on-target.sh` and launches the updater
check-only. The `modern-smoke` job installs the pkg on an Apple Silicon runner and does the same with the
arm64 slice. Publishing waits for both.

## Declared state

- upstream: UPSTREAM_VERSION
- clang22: components/clang22/version

## Conformance deviations

- arm64:usr/local/mavergreen/cmake/bin/*: developers and CI on Apple Silicon run this CMake to build Mavericks artifacts, so the pkg carries an arm64 (11.0) slice beside the x86_64 (10.9) one. Revisit when nothing that produces Mavericks artifacts runs on arm64.
- macos-runner:release.yml:modern-smoke: the arm64 slice is installed and run on current macOS (spec: modern-slice products); exit: none while the slice ships
- static-cxx-runtime:build/build.sh: the x86_64 slice links LLVM 22's libc++ statically and uses Mavericks' system libc++abi and unwinder, clang22 N−1's own clang++.cfg default, until clang22 links the family's shared libc++.
- system-cxx-runtime:build/build.sh: the arm64 slice links macOS's /usr/lib/libc++.1.dylib, compiled against the MacOSX11.3 SDK's libc++ headers: no arm64 libcxx exists, and clang22-cross's runtimes are x86_64 only; revisit when an arm64 libcxx exists.
