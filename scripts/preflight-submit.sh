#!/usr/bin/env bash
# Submit an image to Red Hat for certification:
#   scripts/preflight-submit.sh <repository:tag> <component-id>
#
# OUTWARD-FACING: this sends results to Red Hat Partner Connect. Only a
# publishing workflow runs it. The Pyxis API token is read from the environment
# variable PFLT_PYXIS_API_TOKEN and is never printed or passed on a command line.
#
# The image may sit on any registry preflight can pull from. If the current
# container-engine login exists (~/.docker/config.json, or REGISTRY_AUTH_FILE)
# it is passed on; a public image needs none.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

REF=${1:?usage: preflight-submit.sh <repository:tag> <component-id>}
COMPONENT=${2:?usage: preflight-submit.sh <repository:tag> <component-id>}
[[ "$COMPONENT" =~ ^[a-f0-9]{24}$ ]] || {
  echo "preflight-submit: '$COMPONENT' is not a Partner Connect component ID (24 hex characters)" >&2
  exit 1
}
: "${PFLT_PYXIS_API_TOKEN:?PFLT_PYXIS_API_TOKEN must be set (from a repository secret)}"

OUT=${PREFLIGHT_OUT:-$PWD/.ctx/preflight-submit}
mkdir -p "$OUT"

auth=${REGISTRY_AUTH_FILE:-${DOCKER_CONFIG:-$HOME/.docker}/config.json}
mounts=()
flags=()
if [ -f "$auth" ]; then
  mounts=(-v "$auth:/auth.json:ro")
  flags=(--docker-config /auth.json)
fi

set +e
"$ENGINE" run --rm --platform linux/amd64 \
  -e PFLT_PYXIS_API_TOKEN -e PFLT_ARTIFACTS=/artifacts -e PFLT_LOGFILE=/artifacts/preflight.log \
  -v "$OUT:/artifacts" ${mounts[@]+"${mounts[@]}"} \
  "$PREFLIGHT_IMAGE" check container "$REF" --platform amd64 \
  --submit --certification-component-id "$COMPONENT" ${flags[@]+"${flags[@]}"} >"$OUT/results.json"
rc=$?
set -e

if ! jq -e . "$OUT/results.json" >/dev/null 2>&1; then
  echo "preflight-submit: preflight did not produce results (exit $rc). See $OUT/preflight.log" >&2
  exit 1
fi
jq -r '(.results.passed // [])[] | "ok   - \(.name)"' "$OUT/results.json"
jq -r '((.results.failed // []) + (.results.errors // []))[] | "FAIL - \(.name)"' "$OUT/results.json" >&2

if [ "$(jq -r '.passed' "$OUT/results.json")" != "true" ]; then
  echo "preflight-submit: the image did not pass certification (submitted results, if any, say so)" >&2
  exit 1
fi
if [ "$rc" -ne 0 ]; then
  echo "preflight-submit: the checks passed but preflight exited $rc; the submission may not have reached Red Hat. See $OUT/preflight.log" >&2
  exit 1
fi
echo "preflight-submit: $REF passed and was submitted to component $COMPONENT" >&2
