#!/usr/bin/env bash
# Which Go modules to bump, and to which version:
#   scripts/fix-targets.sh <findings.jsonl>
# Prints one "module@vX.Y.Z" per module with a finding of class gomod: the
# highest fixed version in the same major version as the one installed, so
# that one bump clears every finding for that module without a major upgrade.
set -euo pipefail

FINDINGS=${1:?usage: fix-targets.sh <findings.jsonl>}
jq -rs '
  def parts: ltrimstr("v") | split("-")[0] | split(".") | map(tonumber? // 0);
  map(select(.class == "gomod" and .fixed != ""))
  | group_by(.pkg)[]
  | .[0].pkg as $pkg
  | (.[0].installed | parts | .[0]) as $major
  | [ .[].fixed | split(",")[] | gsub("^\\s+|\\s+$"; "") | select(length > 0)
      | select((parts | .[0]) == $major) ]
  | select(length > 0)
  | max_by(parts)
  | "\($pkg)@v\(ltrimstr("v"))"
' "$FINDINGS" | sort
