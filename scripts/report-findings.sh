#!/usr/bin/env bash
# Keep one GitHub issue per image for its open vulnerabilities:
#   scripts/report-findings.sh <image-name> <tag> <findings.jsonl>
#
# Findings and no open issue  -> open one. Its creation date starts the patch
#                                SLA clock (ADR-002 rule 4).
# Findings and an open issue  -> update its text.
# No findings, an open issue  -> close it.
# Uses the gh CLI with the token in GH_TOKEN. Needs issues: write.
set -euo pipefail

IMAGE=${1:?usage: report-findings.sh <image-name> <tag> <findings.jsonl>}
TAG=${2:?usage: report-findings.sh <image-name> <tag> <findings.jsonl>}
FINDINGS=${3:?usage: report-findings.sh <image-name> <tag> <findings.jsonl>}
TITLE="Vulnerabilities in $IMAGE"
LABEL=vulnerability

count=$(grep -c . "$FINDINGS" || true)
open=$(gh issue list --state open --label "$LABEL" --search "\"$TITLE\" in:title" --json number --jq '.[0].number // empty' 2>/dev/null || true)

if [ "$count" -eq 0 ]; then
  if [ -n "$open" ]; then
    gh issue close "$open" --comment "The re-scan of \`$IMAGE:$TAG\` finds no fixable CRITICAL or HIGH vulnerability any more."
    echo "report-findings: closed issue #$open"
  else
    echo "report-findings: $IMAGE:$TAG is clean, nothing to report"
  fi
  exit 0
fi

body=$(mktemp)
trap 'rm -f "$body"' EXIT
{
  echo "The daily re-scan found **$count** fixable CRITICAL or HIGH finding(s) in the published image \`$IMAGE:$TAG\`."
  echo
  echo "Patch SLA (ADR-002 rule 4): CRITICAL within 7 days, HIGH within 30 days, counted from when this issue was opened."
  echo
  echo "| ID | Severity | Package | Installed | Fixed in | Kind |"
  echo "|---|---|---|---|---|---|"
  jq -r '"| \(.id) | \(.severity) | `\(.pkg)` | \(.installed) | \(.fixed) | \(.class) |"' "$FINDINGS"
  echo
  echo "Kinds: \`os\` is a UBI package (fix: newer base image); \`gomod\` is a Go module (fix: dependency bump, recorded as a deviation); \`stdlib\` is Go itself (fix: newer toolchain, not automated)."
  echo
  echo "If a fix could be prepared automatically there is a pull request from branch \`auto/fix-$IMAGE\`. Otherwise see \`.claude/skills/fix-cve/SKILL.md\`."
  echo
  echo "_Last updated by the re-scan on $(date -u +%Y-%m-%d)._"
} >"$body"

if [ -n "$open" ]; then
  gh issue edit "$open" --body-file "$body" >/dev/null
  echo "report-findings: updated issue #$open ($count finding(s))"
else
  gh label create "$LABEL" --color B60205 --description "A fixable vulnerability in a published image" --force >/dev/null 2>&1 || true
  url=$(gh issue create --title "$TITLE" --label "$LABEL" --body-file "$body")
  echo "report-findings: opened $url ($count finding(s))"
fi
