#!/usr/bin/env bash
# Submit a pushed image to Red Hat for certification:
#   scripts/preflight-submit.sh <repository:tag> <component-id>
#
# OUTWARD-FACING: this sends results to Red Hat Partner Connect. Only the
# publish workflow runs it. The Pyxis API token is read from the environment
# variable PFLT_PYXIS_API_TOKEN and is never printed or passed on a command line.
# Registry credentials come from the current container-engine login.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

REF=${1:?usage: preflight-submit.sh <repository:tag> <component-id>}
COMPONENT=${2:?usage: preflight-submit.sh <repository:tag> <component-id>}
: "${PFLT_PYXIS_API_TOKEN:?PFLT_PYXIS_API_TOKEN must be set (from a repository secret)}"

auth=${REGISTRY_AUTH_FILE:-${DOCKER_CONFIG:-$HOME/.docker}/config.json}
[ -f "$auth" ] || {
  echo "preflight-submit: no registry login found at $auth" >&2
  exit 1
}
OUT=${PREFLIGHT_OUT:-$PWD/.ctx/preflight-submit}
mkdir -p "$OUT"

"$ENGINE" run --rm --platform linux/amd64 \
  -e PFLT_PYXIS_API_TOKEN -e PFLT_ARTIFACTS=/artifacts -e PFLT_LOGFILE=/artifacts/preflight.log \
  -v "$OUT:/artifacts" -v "$auth:/auth.json:ro" \
  "$PREFLIGHT_IMAGE" check container "$REF" --platform amd64 \
  --submit --certification-component-id "$COMPONENT" --docker-config /auth.json >"$OUT/results.json"

if [ "$(jq -r '.passed' "$OUT/results.json")" != "true" ]; then
  jq -r '((.results.failed // []) + (.results.errors // []))[] | "FAIL - \(.name)"' "$OUT/results.json" >&2
  echo "preflight-submit: submitted, but the image did not pass certification" >&2
  exit 1
fi
echo "preflight-submit: $REF submitted to component $COMPONENT and passed" >&2
