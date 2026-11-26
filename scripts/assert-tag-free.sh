#!/usr/bin/env bash
# Refuse to publish over an existing tag:
#   scripts/assert-tag-free.sh <repository> <tag>
#
# Run immediately before a push. A release tag is never overwritten
# (ADR-002 rule 3): if it exists, the release number was computed wrongly or
# another publish got there first, and the run must stop.
set -euo pipefail

REPO=${1:?usage: assert-tag-free.sh <repository> <tag>}
TAG=${2:?usage: assert-tag-free.sh <repository> <tag>}

tags=$("$(dirname "$0")/list-tags.sh" "$REPO")
if printf '%s\n' "$tags" | grep -qxF -- "$TAG"; then
  echo "assert-tag-free: $REPO:$TAG already exists. Refusing to overwrite a published release." >&2
  exit 1
fi
echo "assert-tag-free: $REPO:$TAG is free" >&2
