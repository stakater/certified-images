#!/usr/bin/env bash
# Build one image the way CI does (ADR-003):
#   scripts/build-image.sh images/<name>
#
# pinned source -> Hermeto prefetch -> build with the network off.
# Prints the local image reference on stdout; everything else goes to stderr.
# CTX overrides the build context directory (default .ctx/<name>).
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

"$ENGINE" build --network=none --platform "$PLATFORM" -f "$CTX/Containerfile" -t "$REF" "$CTX" >&2
echo "$REF"
