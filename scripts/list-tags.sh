#!/usr/bin/env bash
# List the tags of a registry repository, one per line:
#   scripts/list-tags.sh <repository>
#
# Uses the credentials of the current container-engine login
# (~/.docker/config.json, or the file named by REGISTRY_AUTH_FILE), if any. A repository that does not exist yet has no
# tags; any other failure is an error.
# REGISTRY_INSECURE=1 allows a plain-HTTP registry (the local rehearsal).
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

REPO=${1:?usage: list-tags.sh <repository>}

args=()
auth=${REGISTRY_AUTH_FILE:-${DOCKER_CONFIG:-$HOME/.docker}/config.json}
[ -f "$auth" ] && args+=(-v "$auth:/auth.json:ro")
cmd=(list-tags)
[ -f "$auth" ] && cmd+=(--authfile /auth.json)
[ -n "${REGISTRY_INSECURE:-}" ] && cmd+=(--tls-verify=false)

set +e
out=$("$ENGINE" run --rm ${SKOPEO_NETWORK:+--network "$SKOPEO_NETWORK"} ${args[@]+"${args[@]}"} \
  "$SKOPEO_IMAGE" "${cmd[@]}" "docker://$REPO" 2>&1)
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  case "$out" in
    *"name unknown"* | *"NAME_UNKNOWN"* | *"repository name not known"* | *"not found"*)
      exit 0 # no such repository yet: no tags
      ;;
  esac
  printf '%s\n' "$out" >&2
  echo "list-tags: could not list tags of $REPO" >&2
  exit 1
fi
printf '%s' "$out" | jq -r '.Tags // [] | .[]'
