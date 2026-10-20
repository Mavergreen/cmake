# CMake for Mavericks

**This README has not been read or edited by a human yet.** Until it has, this project cannot cut
its first release.

Kitware's CMake, built to run on Mac OS X 10.9.5 Mavericks and every macOS since, on Intel and
Apple Silicon. It is an unofficial community build, not affiliated with Kitware.

The pkg installs one universal tree at `/usr/local/mavergreen/cmake`:

- `bin/cmake`, `bin/ctest` and `bin/cpack`, each with an x86_64 slice (macOS 10.9 and later) and an
  arm64 slice (macOS 11 and later);
- `share/cmake-4.4`, CMake's modules;
- `doc/cmake-4.4`, CMake's licence and its bundled libraries' licences.

There is no `ccmake` and no `cmake-gui`.

## Commands

The pkg puts no bare `cmake`, `ctest` or `cpack` into the family's link farm
(`/usr/local/mavergreen/bin`). They would shadow a cmake you already have, so its manifest excludes
them. Run it by its path, `/usr/local/mavergreen/cmake/bin/cmake`, or put that directory on your
`PATH` yourself.

## Stock behaviour

This is CMake as Kitware ships it, with one source change: CMake's bundled libuv asks for
`recvmsg_x`/`sendmsg_x` on 10.7 and later, but they arrived in 10.10
(`patches/cmake/0001-libuv-darwin-mmsg-needs-10.10.patch`). It is filed upstream.

It adds no Mavergreen search paths of its own. Point `find_package` at a Mavergreen package with
`CMAKE_PREFIX_PATH` or `-D<Package>_DIR`. Stock CMake also searches the prefix above every
directory on your `PATH`, as it does everywhere. So with `/usr/local/mavergreen/bin` on your `PATH`,
`find_package(Foo)` looks in `/usr/local/mavergreen/foo*/`, as any CMake would.
To turn that search off, configure with `-DCMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH=OFF`. It stops
every `find_*` command searching `PATH`, `find_program` included, so CMake may then need
`-DCMAKE_MAKE_PROGRAM=<path>` to find its build tool.

## No HTTPS

This CMake has no TLS. `file(DOWNLOAD https://…)`, and `FetchContent` or `ExternalProject` over
HTTPS, fail with **"Unsupported protocol"**, on every macOS version.

CMake's bundled curl has no macOS TLS backend without OpenSSL, and this build links nothing from the
build host (`CMAKE_USE_SYSTEM_LIBRARIES=0`, `CMAKE_USE_OPENSSL=OFF`). The OS's own curl can't stand
in: 10.9's is 7.30, and CMake 4.4 needs 7.34.

Fetch your dependencies yourself, from a pinned URL with a pinned SHA-256, then hand them to
FetchContent. It downloads nothing when the sources are already there:

```sh
curl -fLO https://github.com/fmtlib/fmt/releases/download/12.0.0/fmt-12.0.0.zip
echo "<the SHA-256 you pinned>  fmt-12.0.0.zip" | shasum -a 256 -c -
unzip -q fmt-12.0.0.zip
/usr/local/mavergreen/cmake/bin/cmake -S . -B build -DFETCHCONTENT_SOURCE_DIR_FMT="$PWD/fmt-12.0.0"
```

A project that declares `FetchContent_Declare(fmt URL https://…)` then configures offline. With
several dependencies, unpack each into the build directory's `_deps/<name>-src` and configure with
`-DFETCHCONTENT_FULLY_DISCONNECTED=ON`.

Family builds already fetch this way, with shipyard's `mavericks_fetch.sh` (a tarball, by SHA-256) or
`fetch_pinned_source.sh` (a commit's tarball, by SHA-256). Both verify what `file(DOWNLOAD)` never did.

## Releases

Versions are `<CMake version>-mavericks.N`. A Renovate bump of `UPSTREAM_VERSION` cuts
`-mavericks.1`, and a bump of an ingredient (see `INGREDIENTS.md`) cuts the next `N`. The release
notes link Kitware's notes for the minor release, which cover its patch releases. The pkg installs a
Sparkle updater that keeps it current.

## Building

`sh build/build.sh` builds a tree under `$MAVERICKS_BUILD_ROOT` (default `$TMPDIR/mm-build`),
never in the checkout. `sh build/package.sh TREE VERSION dist` wraps it into
`dist/cmake-VERSION.pkg`. `sh "$SHIPYARD_SCRIPTS/run-repo-tests.sh"` runs the tests against what was
built.

Both slices are compiled by clang22 (`components/clang22/version`) against the pinned SDKs: x86_64
against MacOSX10.9.sdk, arm64 against MacOSX11.3.sdk. A modern Mac builds both. Mac OS X 10.9 builds
x86_64 alone, because no clang22 that runs there targets arm64. That tree packages as
`cmake-VERSION-x86_64-dev.pkg`, which is never published. To finish a 10.9 build into a universal
tree, build arm64 on a modern Mac and pass its slice in: `SLICE_ARM64=<dir> sh build/build.sh`,
where `<dir>` is that Mac's `$MAVERICKS_BUILD_ROOT/mavergreen-cmake/slice-arm64`.

## License

See `LICENSE`.
