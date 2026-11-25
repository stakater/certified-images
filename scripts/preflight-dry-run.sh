#!/usr/bin/env bash
# Run Red Hat's certification checks without submitting anything:
#   scripts/preflight-dry-run.sh <image-ref> <context-dir>
#
# preflight reads images from a registry, so this starts a throwaway local
# registry, pushes the image to it, runs `preflight check container`, and
# removes the registry. No credentials, nothing leaves the machine except
# preflight's own lookups against Red Hat's catalog API.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
PORT=${PREFLIGHT_REGISTRY_PORT:-5055}
NET=preflight-dry-run
REG=preflight-dry-run-registry

REF=${1:?usage: preflight-dry-run.sh <image-ref> <context-dir>}
CTX=${2:?usage: preflight-dry-run.sh <image-ref> <context-dir>}
mkdir -p "$CTX/evidence/preflight"
OUT=$(cd "$CTX/evidence/preflight" && pwd)

cleanup() {
  "$ENGINE" rm -f "$REG" >/dev/null 2>&1 || true
  "$ENGINE" network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

"$ENGINE" network create "$NET" >/dev/null
"$ENGINE" run -d --name "$REG" --network "$NET" -p "127.0.0.1:$PORT:5000" "$REGISTRY_IMAGE" >/dev/null

name=${REF##*/}
local_ref="localhost:$PORT/$name"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  "$ENGINE" tag "$REF" "$local_ref" && "$ENGINE" push -q "$local_ref" >/dev/null 2>&1 && pushed=1 && break
  sleep 1
done
[ -n "${pushed:-}" ] || {
  echo "preflight-dry-run: could not push $REF to the local registry" >&2
  exit 1
}

set +e
"$ENGINE" run --rm --platform linux/amd64 --network "$NET" -v "$OUT:/artifacts" \
  -e PFLT_ARTIFACTS=/artifacts -e PFLT_LOGFILE=/artifacts/preflight.log \
  "$PREFLIGHT_IMAGE" check container "$REG:5000/$name" --insecure --platform amd64 >"$OUT/results.json"
rc=$?
set -e
"$ENGINE" rmi "$local_ref" >/dev/null 2>&1 || true

if [ "$rc" -ne 0 ] || ! jq -e . "$OUT/results.json" >/dev/null 2>&1; then
  echo "preflight-dry-run: preflight did not run cleanly (exit $rc). See $OUT/preflight.log" >&2
  exit 1
fi

jq -r '
  (.results.passed // [])[] | "ok   - \(.name)"
  ' "$OUT/results.json"
jq -r '
  ((.results.failed // []) + (.results.errors // []))[] | "FAIL - \(.name): \(.description // .help // "")"
  ' "$OUT/results.json"

if [ "$(jq -r '.passed' "$OUT/results.json")" != "true" ]; then
  echo "preflight-dry-run: the image would not pass certification. Full report: $OUT/results.json" >&2
  exit 1
fi
echo "preflight-dry-run: all certification checks passed (dry run, nothing submitted)" >&2
