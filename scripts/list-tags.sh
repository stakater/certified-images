#!/usr/bin/env bash
# List the tags of a registry repository, one per line:
#   scripts/list-tags.sh <repository>
#
# Uses crane (pinned in tools.env) and the credentials of the current container-engine login
# (~/.docker/config.json, or the file named by REGISTRY_AUTH_FILE), if any. A repository that does not exist yet has no
# tags; any other failure is an error.
# REGISTRY_INSECURE=1 allows a plain-HTTP registry (the local rehearsal).
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

REPO=${1:?usage: list-tags.sh <repository>}

# crane reads credentials from $DOCKER_CONFIG/config.json inside the container.
args=()
auth=${REGISTRY_AUTH_FILE:-${DOCKER_CONFIG:-$HOME/.docker}/config.json}
[ -f "$auth" ] && args+=(-v "$auth:/auth/config.json:ro" -e DOCKER_CONFIG=/auth)
cmd=(ls)
[ -n "${REGISTRY_INSECURE:-}" ] && cmd+=(--insecure)

set +e
out=$("$ENGINE" run --rm ${TOOL_NETWORK:+--network "$TOOL_NETWORK"} ${args[@]+"${args[@]}"} \
  "$CRANE_IMAGE" "${cmd[@]}" "$REPO" 2>&1)
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  # Only the registry saying "this repository does not exist" means "no tags".
  # Every other failure (network, auth, a tool image that would not pull) is an
  # error. Treating one as "no tags" would hand out a release number that is
  # already taken.
  case "$out" in
    *"NAME_UNKNOWN"* | *"repository name not known"*)
      echo "list-tags: $REPO does not exist yet, so it has no tags" >&2
      exit 0
      ;;
  esac
  printf '%s\n' "$out" >&2
  echo "list-tags: could not list tags of $REPO" >&2
  exit 1
fi

# Success: one tag per line. Anything that is not a valid tag means the output
# is not what we think it is; refuse to guess.
while IFS= read -r tag; do
  [ -z "$tag" ] && continue
  [[ "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$ ]] || {
    printf '%s\n' "$out" >&2
    echo "list-tags: could not list tags of $REPO: unexpected output" >&2
    exit 1
  }
done <<<"$out"
printf '%s\n' "$out" | sed '/^$/d'
