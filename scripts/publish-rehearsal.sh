#!/usr/bin/env bash
# Rehearse the registry half of a publish, with no credentials:
#   scripts/publish-rehearsal.sh <local-ref> images/<name>
#
# Against a throwaway local registry it runs the real scripts twice: list tags,
# compute the release, push, read back the digest. The first push must be
# release 1 and the second release 2. Signing, attestations and submission to
# Red Hat are NOT rehearsed: they need real credentials and write to public
# services.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)

REF=${1:?usage: publish-rehearsal.sh <local-ref> images/<name>}
DIR=${2:?usage: publish-rehearsal.sh <local-ref> images/<name>}
PORT=${REHEARSAL_REGISTRY_PORT:-5056}
REG=publish-rehearsal-registry
NET=publish-rehearsal
NAME=$(basename "${DIR%/}")
REPO="localhost:$PORT/rehearsal/$NAME"

VERSION=$("$ROOT/scripts/publish-plan.sh" "$DIR" | sed -n 's/^version=//p')
[ -n "$VERSION" ] || {
  echo "publish-rehearsal: no upstream version for $DIR" >&2
  exit 1
}

cleanup() {
  "$ENGINE" rm -f "$REG" >/dev/null 2>&1 || true
  "$ENGINE" network rm "$NET" >/dev/null 2>&1 || true
  "$ENGINE" rmi "$REPO:$VERSION-1" "$REPO:$VERSION-2" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup
"$ENGINE" network create "$NET" >/dev/null
"$ENGINE" run -d --name "$REG" --network "$NET" -p "127.0.0.1:$PORT:5000" "$REGISTRY_IMAGE" >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -fsS "http://localhost:$PORT/v2/" >/dev/null 2>&1 && break
  sleep 1
done

# The engine pushes to the published port on localhost. skopeo runs in a
# container, so it reaches the same repository by the registry's network name.
tags() {
  REGISTRY_INSECURE=1 SKOPEO_NETWORK=$NET REGISTRY_AUTH_FILE=/nonexistent \
    "$ROOT/scripts/list-tags.sh" "$REG:5000/rehearsal/$NAME"
}

for expected in 1 2; do
  existing=$(tags)
  release=$(printf '%s\n' "$existing" | "$ROOT/scripts/next-release.sh" "$VERSION")
  [ "$release" = "$expected" ] || {
    echo "FAIL - expected release $expected, got $release. Tags the registry listed: '$(echo "$existing" | tr '\n' ' ')'" >&2
    exit 1
  }
  REGISTRY_INSECURE=1 SKOPEO_NETWORK=$NET REGISTRY_AUTH_FILE=/nonexistent \
    "$ROOT/scripts/assert-tag-free.sh" "$REG:5000/rehearsal/$NAME" "$VERSION-$release" 2>/dev/null
  digest=$("$ROOT/scripts/push-image.sh" "$REF" "$REPO" "$VERSION-$release" 2>/dev/null)
  "$ENGINE" pull -q "$digest" >/dev/null
  echo "ok   - release $release pushed as $VERSION-$release and pulled back by digest"
done
# The tag just pushed must now be refused.
if REGISTRY_INSECURE=1 SKOPEO_NETWORK=$NET REGISTRY_AUTH_FILE=/nonexistent \
  "$ROOT/scripts/assert-tag-free.sh" "$REG:5000/rehearsal/$NAME" "$VERSION-2" 2>/dev/null; then
  echo "FAIL - an existing tag was reported as free" >&2
  exit 1
fi
echo "ok   - an existing tag is refused"
echo "publish-rehearsal: release numbering and push work (signing and submission not rehearsed)"
