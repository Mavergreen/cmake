#!/bin/sh
# platform: host-agnostic
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "no python3 -- skipping"; exit 77; }
python3 - "$ROOT/.github/renovate.json" <<'PY' || { echo "FAIL: renovate.json"; exit 1; }
import json, sys
c = json.load(open(sys.argv[1]))
assert c["extends"] == ["github>Mavergreen/shipyard"], "extends"
m = {x["depNameTemplate"]: x for x in c["customManagers"]}
assert set(m) == {"Kitware/CMake", "Mavergreen/clang-22"}, "exactly the CMake and clang22 managers"
n = m["Kitware/CMake"]
assert n["managerFilePatterns"] == ["/^UPSTREAM_VERSION$/"] and n["datasourceTemplate"] == "github-releases", "CMake manager"
assert n["extractVersionTemplate"] == "^v(?<version>.+)$", "CMake's tags are v-prefixed"
k = m["Mavergreen/clang-22"]
assert k["managerFilePatterns"] == ["/^components/clang22/version$/"] and k["datasourceTemplate"] == "github-releases", "clang22 manager"
assert k["versioningTemplate"].startswith("regex:") and "mavericks" in k["versioningTemplate"], "clang22 -mavericks.N versioning (check 13)"
assert not any("automerge" in r for r in c.get("packageRules", [])), "no packageRule may set automerge: the shipyard preset decides"
PY
echo "PASS: renovate"
