#!/usr/bin/env bash
# Image directories changed between two commits, as a JSON list:
#   scripts/changed-images.sh <before-sha> <after-sha>
#
# Used by the publish workflow so a merge publishes only the images it touched.
# An all-zero <before> (first push of a branch) lists every image. Images that
# no longer exist at <after> are left out.
set -euo pipefail

BEFORE=${1:?usage: changed-images.sh <before-sha> <after-sha>}
AFTER=${2:?usage: changed-images.sh <before-sha> <after-sha>}

if [[ "$BEFORE" =~ ^0+$ ]]; then
  files=$(git ls-tree -r --name-only "$AFTER" -- images/)
else
  files=$(git diff --name-only "$BEFORE" "$AFTER" -- images/)
fi

printf '%s\n' "$files" |
  awk -F/ 'NF >= 3 && $1 == "images" { print $1 "/" $2 }' | sort -u |
  while IFS= read -r dir; do
    # Only images that exist at <after>, with a plain slug name.
    [[ "$dir" =~ ^images/[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || continue
    # `if`, not `&&`: a missing image must not fail the pipeline.
    if git cat-file -e "$AFTER:$dir/image.yaml" 2>/dev/null; then echo "$dir"; fi
  done | jq -R . | jq -cs .
