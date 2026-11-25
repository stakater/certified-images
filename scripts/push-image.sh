#!/usr/bin/env bash
# Push a locally built image and print the digest reference it got:
#   scripts/push-image.sh <local-ref> <repository> <tag>
# stdout: <repository>@sha256:<digest>   (everything else goes to stderr)
#
# Everything after the push (signature, attestations, submission, consumers)
# uses the digest, never the tag (ADR-002, ADR-008 §2).
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

REF=${1:?usage: push-image.sh <local-ref> <repository> <tag>}
REPO=${2:?usage: push-image.sh <local-ref> <repository> <tag>}
TAG=${3:?usage: push-image.sh <local-ref> <repository> <tag>}

"$ENGINE" tag "$REF" "$REPO:$TAG"
"$ENGINE" push "$REPO:$TAG" >&2

digest=$("$ENGINE" image inspect "$REPO:$TAG" --format '{{range .RepoDigests}}{{println .}}{{end}}' |
  grep -F "$REPO@sha256:" | head -n1)
[[ "$digest" =~ @sha256:[a-f0-9]{64}$ ]] || {
  echo "push-image: pushed $REPO:$TAG but could not read its digest" >&2
  exit 1
}
echo "$digest"
