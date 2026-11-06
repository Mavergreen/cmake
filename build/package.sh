#!/bin/sh
# platform: host-agnostic
#   usage: package.sh TREE VERSION OUT     wraps a build.sh tree and its updater into OUT/cmake-VERSION.pkg,
#          rooted at /usr/local/mavergreen/cmake (an x86_64-only tree: OUT/cmake-VERSION-x86_64-dev.pkg,
#          never published); prints the pkg. CMAKE_UPDATER_APP names a built cmake-updater.app to package
#          instead of building one. build-info records the build tools that $WORK/build-tools.txt and the
#          updater's build-tools.txt name.
set -eu
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/build/versions.sh"
. "$REPO_ROOT/build/msc.sh"
T="${1:?usage: package.sh TREE VERSION OUT}"; VER="${2:?usage: package.sh TREE VERSION OUT}"; OUT="${3:?usage: package.sh TREE VERSION OUT}"
for b in cmake ctest cpack; do
  [ -x "$T/bin/$b" ] || { echo "package: no $T/bin/$b -- run build/build.sh first" >&2; exit 1; }
done
case "$VER" in "$KITWARE_VERSION"-mavericks.[0-9]*) ;; *) echo "package: version '$VER' is not $KITWARE_VERSION-mavericks.N" >&2; exit 2 ;; esac
# platform: without it, cp on a Mac carries AppleDouble ._ files and extended attributes into the payload
COPYFILE_DISABLE=1; export COPYFILE_DISABLE
CL="$(sh "$REPO_ROOT/build/fetch-clang22.sh")"
archs="$("$CL/bin/llvm-lipo" -info "$T/bin/cmake" | sed -n 's/.*: //p' | xargs)"
case "$archs" in
  "x86_64 arm64") host=x86_64,arm64; suffix=; variant=release ;;
  x86_64) host=x86_64; suffix=-x86_64-dev; variant=dev ;;
  *) echo "package: $T/bin/cmake is '$archs'; a pkg needs x86_64, with or without arm64" >&2; exit 1 ;;
esac
sh "$REPO_ROOT/build/compat-gate.sh" "$T" "$archs" >&2
pr="$WORK/pkgroot"; scr="$WORK/pkg-scripts"; comp="$WORK/$SHORT-component.pkg"
rm -rf "$pr" "$scr" "$comp"; mkdir -p "$pr$(dirname "$PREFIX")" "$OUT"
rm -f "$OUT"/"$SHORT"-*.pkg
cp -R "$T" "$pr$PREFIX"
app="${CMAKE_UPDATER_APP:-$(sh "$REPO_ROOT/build/build-updater.sh" "$VER")}"
uarchs="$("$CL/bin/llvm-lipo" -info "$app/Contents/MacOS/$SHORT-updater" | sed -n 's/.*: //p' | xargs)"
[ "$uarchs" = "$archs" ] || {
  echo "package: the updater is '$uarchs' but bin/cmake is '$archs'; a pkg for Apple Silicon with an x86_64-only updater asks for Rosetta -- build the updater on macOS 11 or later" >&2; exit 1; }
find "$pr" -name '._*' -delete
# spec: README.md "Commands" -- no bare cmake, ctest or cpack in the family's link farm, where they would
#       shadow a cmake the user already has
sh "$SHIPYARD_SCRIPTS/stage_product.sh" --stage "$pr" --product "$SHORT" --name "CMake for Mavericks" \
  --version "$VER" --scripts-out "$scr" --exclude bin/cmake --exclude bin/ctest --exclude bin/cpack \
  --updater-app "$app"
sh "$SHIPYARD_SCRIPTS/build_component_pkg.sh" --root "$pr" --identifier "$IDENTIFIER" --version "$VER" \
  --install-location / --scripts "$scr" --out "$comp" >/dev/null
pkg="$(cd "$OUT" && pwd)/$SHORT-$VER$suffix.pkg"
sh "$SHIPYARD_SCRIPTS/set_install_floor.sh" --identifier "$IDENTIFIER" --title "CMake for Mavericks $VER" \
  --component "$comp" --out "$pkg" --min-os 10.9.5 --host-arch "$host" --require-scripts >/dev/null
rm -f "$comp"
set -- variant="$variant" arch="$host" prefix="$PREFIX" pkg="$(basename "$pkg")" identifier="$IDENTIFIER" \
  cmake="$KITWARE_VERSION" clang22="$CLANG22_VERSION"
for f in "$WORK/build-tools.txt" "$(dirname "$app")/build-tools.txt"; do
  [ -s "$f" ] || { echo "package: no $f -- the build tools that built what ships must be recorded" >&2; rm -f "$pkg"; exit 1; }
  while IFS= read -r l; do set -- "$@" "$l"; done < "$f"
done
rm -f "$OUT"/build-info-*.txt
sh "$SHIPYARD_SCRIPTS/build-info.sh" "$OUT/build-info-$variant.txt" "$@"
echo "$pkg"
