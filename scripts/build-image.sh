#!/usr/bin/env bash
# Build one image the way CI does (ADR-003):
#   scripts/build-image.sh images/<name>
#
# pinned source -> Hermeto prefetch -> build with the network off.
# Prints the local image reference on stdout; everything else goes to stderr.
# CTX overrides the build context directory (default .ctx/<name>).
# RELEASE sets the image's release label (default 0: not a published build).
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
PLATFORM=linux/amd64 # ADR-002 rule 8

DIR=${1:?usage: build-image.sh images/<name>}
DIR=${DIR%/}
NAME=$(basename "$DIR")
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CTX=${CTX:-$ROOT/.ctx/$NAME}
REF="localhost/stakater/$NAME:build"

"$ROOT/scripts/check-image.sh" "$DIR" >&2

rm -rf "$CTX"
mkdir -p "$CTX"
"$ROOT/scripts/fetch-source.sh" "$DIR" "$CTX/src"
"$ROOT/scripts/prefetch.sh" "$DIR" "$CTX"
cp "$DIR/Containerfile" "$CTX/Containerfile"

# What built it, when, and on what base (ADR-009). The commit is this
# repository's; "-dirty" marks a build from uncommitted changes.
VCS_REF=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)
if [ "$VCS_REF" != "unknown" ] && [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then
  VCS_REF="$VCS_REF-dirty"
fi
BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BASE_DIGEST=$(sed -n 's/^ARG BASE_TAG=.*@\(sha256:[a-f0-9]*\)$/\1/p' "$DIR/Containerfile")

"$ENGINE" build --network=none --platform "$PLATFORM" --build-arg "RELEASE=${RELEASE:-0}" \
  --build-arg "VCS_REF=$VCS_REF" --build-arg "BUILD_DATE=$BUILD_DATE" --build-arg "BASE_DIGEST=$BASE_DIGEST" -f "$CTX/Containerfile" -t "$REF" "$CTX" >&2
echo "$REF"
