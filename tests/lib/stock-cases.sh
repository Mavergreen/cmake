# platform: macOS-only -- runs a Mac cmake
#   usage: . tests/lib/stock-cases.sh; stock_cases CMAKE VERSION SCRATCH
#          checks what the product promises of any one cmake binary: it reports VERSION, refuses HTTPS
#          downloads, configures FetchContent from local sources, and searches no family paths. Writes
#          only under SCRATCH; reports through the caller's fail().
stock_cases() {
  _sc_c="$1"; _sc_v="$2"; _sc_t="$3"
  # spec: README.md "Stock behaviour" -- stock CMake searches the prefix above every PATH entry, so the checks
  #       below run with no family directory on PATH and no CMAKE_PREFIX_PATH from the caller's shell
  _sc_run() { env -i HOME="$HOME" PATH=/usr/bin:/bin "$_sc_c" "$@"; }

  _sc_got="$(_sc_run --version | sed -n 1p)"
  [ "$_sc_got" = "cmake version $_sc_v" ] || fail "$_sc_c --version must print 'cmake version $_sc_v' (got '$_sc_got')"

  printf '%s\n' 'file(DOWNLOAD https://example.invalid/x "${CMAKE_CURRENT_LIST_DIR}/x" STATUS st)' \
    'message("STATUS=${st}")' > "$_sc_t/https.cmake"
  _sc_out="$(_sc_run -P "$_sc_t/https.cmake" 2>&1)"
  case "$_sc_out" in *'STATUS=1;"Unsupported protocol"'*) ;; *) fail "file(DOWNLOAD https://...) must report Unsupported protocol, the documented limit (got: $_sc_out)" ;; esac

  mkdir "$_sc_t/dep" "$_sc_t/proj"
  printf '%s\n' 'cmake_minimum_required(VERSION 3.16)' 'project(dep NONE)' 'message(STATUS "dep-configured")' > "$_sc_t/dep/CMakeLists.txt"
  # platform: 10.9 without the Command Line Tools has only a make stub; at 3.30 (CMP0168) FetchContent downloads
  #           directly, with no sub-build to run it (vm-test run 39431982834)
  printf '%s\n' 'cmake_minimum_required(VERSION 3.30)' 'project(fc NONE)' 'include(FetchContent)' \
    'FetchContent_Declare(dep URL https://example.invalid/dep.tar.gz)' 'FetchContent_MakeAvailable(dep)' > "$_sc_t/proj/CMakeLists.txt"
  _sc_run -S "$_sc_t/proj" -B "$_sc_t/b-online" -DCMAKE_MAKE_PROGRAM=/usr/bin/false > "$_sc_t/online.out" 2>&1 && fail "a FetchContent download over HTTPS must fail, or the README's limit is wrong"
  grep -q 'Unsupported protocol' "$_sc_t/online.out" || fail "the failed FetchContent download must say Unsupported protocol: $(cat "$_sc_t/online.out")"
  _sc_out="$(_sc_run -S "$_sc_t/proj" -B "$_sc_t/b-srcdir" -DFETCHCONTENT_SOURCE_DIR_DEP="$_sc_t/dep" 2>&1)" \
    || fail "FetchContent must configure with FETCHCONTENT_SOURCE_DIR_DEP set: $_sc_out"
  case "$_sc_out" in *dep-configured*) ;; *) fail "FETCHCONTENT_SOURCE_DIR_DEP must reach the dependency: $_sc_out" ;; esac
  mkdir -p "$_sc_t/b-disc/_deps"; cp -R "$_sc_t/dep" "$_sc_t/b-disc/_deps/dep-src"
  _sc_out="$(_sc_run -S "$_sc_t/proj" -B "$_sc_t/b-disc" -DFETCHCONTENT_FULLY_DISCONNECTED=ON 2>&1)" \
    || fail "FetchContent must configure with FETCHCONTENT_FULLY_DISCONNECTED=ON over sources placed in _deps: $_sc_out"
  case "$_sc_out" in *dep-configured*) ;; *) fail "FETCHCONTENT_FULLY_DISCONNECTED=ON must use the placed sources: $_sc_out" ;; esac

  _sc_fake="$_sc_t/root/usr/local/mavergreen/fake/share/cmake/Fake"; mkdir -p "$_sc_fake" "$_sc_t/stock"
  echo 'set(Fake_FOUND TRUE)' > "$_sc_fake/FakeConfig.cmake"
  printf '%s\n' 'cmake_minimum_required(VERSION 3.16)' 'project(stock NONE)' 'find_package(Fake CONFIG QUIET)' \
    'message(STATUS "FAKE=${Fake_FOUND}")' > "$_sc_t/stock/CMakeLists.txt"
  _sc_found() { _sc_l="$1"; shift; _sc_run -S "$_sc_t/stock" -B "$_sc_t/b-$_sc_l" -DCMAKE_FIND_ROOT_PATH="$_sc_t/root" "$@" 2>&1 | sed -n 's/^-- FAKE=//p'; }
  [ "$(_sc_found plain)" = 0 ] || fail "plain find_package(Fake) must not find a package under /usr/local/mavergreen/fake: the product carries no family search paths"
  [ "$(_sc_found asked -DCMAKE_PREFIX_PATH=/usr/local/mavergreen/fake)" = 1 ] \
    || fail "find_package(Fake) must find it when asked with CMAKE_PREFIX_PATH, or the check above proves nothing"
}
