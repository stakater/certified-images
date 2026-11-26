#!/usr/bin/env bash
# Promote an image from one registry to another, by digest:
#   scripts/copy-image.sh <source@sha256:digest> <repository> <tag>
# stdout: <repository>@sha256:<digest>   (everything else goes to stderr)
#
# Copies the manifest and layers as they are, so the image that was staged and
# tested is byte for byte the image that is certified (ADR-002 rev 5). Fails
# unless the destination ends up with exactly the source digest.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

SRC=${1:?usage: copy-image.sh <source@sha256:digest> <repository> <tag>}
REPO=${2:?usage: copy-image.sh <source@sha256:digest> <repository> <tag>}
TAG=${3:?usage: copy-image.sh <source@sha256:digest> <repository> <tag>}

[[ "$SRC" =~ @(sha256:[a-f0-9]{64})$ ]] || {
  echo "copy-image: the source must be a digest reference (name@sha256:...), got '$SRC'" >&2
  exit 1
}
want=${BASH_REMATCH[1]}

crane copy "$SRC" "$REPO:$TAG" >&2 || {
  echo "copy-image: could not copy $SRC to $REPO:$TAG" >&2
  exit 1
}
got=$(crane digest "$REPO:$TAG") || {
  echo "copy-image: copied, but could not read the digest of $REPO:$TAG" >&2
  exit 1
}
[ "$got" = "$want" ] || {
  echo "copy-image: digest changed in transit: source $want, destination $got" >&2
  exit 1
}
echo "$REPO@$got"
