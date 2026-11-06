#!/bin/sh
# platform: host-agnostic
#   usage: mode.sh -- build host mode, with the conventional explicit override
set -eu
if [ -n "${MAVERICKS_MODE:-}" ]; then
  case "$MAVERICKS_MODE" in native|cross|linux) printf '%s\n' "$MAVERICKS_MODE" ;; *) exit 2 ;; esac
elif [ "$(uname -s)" = Linux ]; then
  echo linux
else
  exec sh "${SHIPYARD_SCRIPTS:?}/mavericks_mode.sh"
fi
