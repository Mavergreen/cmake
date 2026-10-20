#!/bin/sh
# platform: host-agnostic
#   usage: upstream-release-notes-url.sh <upstream-version>     prints CMake's notes URL for it
# spec: README.md "Releases" -- Kitware writes one notes page per minor release, which covers its patch releases
set -eu
v="${1:?usage: upstream-release-notes-url.sh <upstream-version>}"
m="$(printf '%s\n' "$v" | cut -d. -f1,2)"
printf 'https://cmake.org/cmake/help/v%s/release/%s.html\n' "$m" "$m"
