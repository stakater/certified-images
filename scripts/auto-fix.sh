#!/usr/bin/env bash
# Prepare the fix for an image's findings, in the working tree:
#   scripts/auto-fix.sh images/<name> <findings.jsonl>
#
#   os      -> bump the UBI base digest            (scripts/bump-base.sh)
#   gomod   -> regenerate the dependency patch and record the deviation
#              (scripts/fix-go-deps.sh, scripts/update-deviations.sh)
#   stdlib  -> not automated; reported
#
# Changes files only. It commits nothing and opens nothing: the caller decides.
# A person reviews the result (ADR-002 rule 6).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR=${1:?usage: auto-fix.sh images/<name> <findings.jsonl>}
FINDINGS=${2:?usage: auto-fix.sh images/<name> <findings.jsonl>}

has() { jq -e --arg c "$1" 'select(.class == $c)' "$FINDINGS" >/dev/null 2>&1; }

if has os; then
  "$ROOT/scripts/bump-base.sh" "$DIR" | sed 's/^/base: /'
fi

targets=$("$ROOT/scripts/fix-targets.sh" "$FINDINGS")
if [ -n "$targets" ]; then
  # shellcheck disable=SC2086 # targets is a list of arguments
  bumps=$("$ROOT/scripts/fix-go-deps.sh" "$DIR" $targets)
  ids=$(jq -r 'select(.class == "gomod") | .id' "$FINDINGS" | sort -u | tr '\n' ' ' | sed 's/ $//')
  "$ROOT/scripts/update-deviations.sh" "$DIR" "$ids" "$bumps"
  printf '%s\n' "$bumps" | sed 's/^/bumped: /'
fi

if has stdlib; then
  echo "not automated: the Go standard library has a finding; bump GO_TAG by hand (.claude/skills/fix-cve)"
fi
if has other; then
  echo "not automated: a finding of a kind this script does not know"
fi
