#!/usr/bin/env bash
# Log in to Red Hat's partner registry for one component:
#   scripts/rh-registry-login.sh <component-id> [image-name]
#
# No secret is named per image (ADR-002 rev 7). The username is derived from
# the component ID. The registry key comes from:
#   RH_REGISTRY_KEYS: one secret, a JSON object keyed by component ID:
#     {"<component-id>": {"name": "<image name>", "key": "<registry key>"}}
#   "name" is there so a person can read the secret. When it is present and the
#   image name is given, they must match: that catches a key filed under the
#   wrong component. The short form {"<component-id>": "<key>"} also works.
# Fetching the key from Red Hat's API with RH_PYXIS_TOKEN was tried and is not
# possible: the API does not return it (docs/setup.md, step 6c).
#
# Exit status:
#   0  logged in
#   3  no key is available for this component: the caller skips the Red Hat
#      stage and says so. This is a normal state for a new image.
#   1  anything else: a malformed secret, or the registry refused the login
#
# The key is passed to the container engine on stdin and is never printed.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
REGISTRY=${RH_REGISTRY_HOST:-quay.io}

ID=${1:?usage: rh-registry-login.sh <component-id> [image-name]}
IMAGE_NAME=${2:-}
[[ "$ID" =~ ^[a-f0-9]{24}$ ]] || {
  echo "rh-registry-login: '$ID' is not a Partner Connect component ID (24 hex characters)" >&2
  exit 1
}
# ⚠️ From Red Hat's push instructions, as remembered. The first real login confirms it.
USERNAME="redhat-isv-containers+$ID-robot"

key=""
if [ -n "${RH_REGISTRY_KEYS:-}" ]; then
  printf '%s' "$RH_REGISTRY_KEYS" | jq -e 'type == "object"' >/dev/null 2>&1 || {
    echo "rh-registry-login: RH_REGISTRY_KEYS is not a JSON object of {\"<component-id>\": \"<key>\"}" >&2
    exit 1
  }
  entry_type=$(printf '%s' "$RH_REGISTRY_KEYS" | jq -r --arg id "$ID" '.[$id] | type')
  case "$entry_type" in
    string)
      key=$(printf '%s' "$RH_REGISTRY_KEYS" | jq -r --arg id "$ID" '.[$id]')
      ;;
    object)
      key=$(printf '%s' "$RH_REGISTRY_KEYS" | jq -r --arg id "$ID" '.[$id].key // empty')
      entry_name=$(printf '%s' "$RH_REGISTRY_KEYS" | jq -r --arg id "$ID" '.[$id].name // empty')
      [ -n "$key" ] || {
        echo "rh-registry-login: the RH_REGISTRY_KEYS entry for $ID has no \"key\"" >&2
        exit 1
      }
      if [ -n "$IMAGE_NAME" ] && [ -n "$entry_name" ] && [ "$entry_name" != "$IMAGE_NAME" ]; then
        echo "rh-registry-login: the RH_REGISTRY_KEYS entry for $ID is named '$entry_name', but this image is '$IMAGE_NAME'. The key may be filed under the wrong component. Not logging in." >&2
        exit 1
      fi
      ;;
    null) ;;
    *)
      echo "rh-registry-login: the RH_REGISTRY_KEYS entry for $ID must be a key, or {\"name\": ..., \"key\": ...}" >&2
      exit 1
      ;;
  esac
fi

if [ -z "$key" ]; then
  echo "rh-registry-login: no registry key for component $ID. Add it to the RH_REGISTRY_KEYS secret as \"$ID\": {\"name\": \"${IMAGE_NAME:-<image name>}\", \"key\": \"<registry key>\"} (docs/setup.md, step 6)." >&2
  exit 3
fi

# Mask it in GitHub's log, in case anything downstream echoes it.
[ -z "${GITHUB_ACTIONS:-}" ] || echo "::add-mask::$key"

if ! printf '%s' "$key" | "$ENGINE" login "$REGISTRY" -u "$USERNAME" --password-stdin >/dev/null 2>&1; then
  echo "rh-registry-login: $REGISTRY refused the login for $USERNAME. Check the key held for $ID in RH_REGISTRY_KEYS." >&2
  exit 1
fi
echo "rh-registry-login: logged in to $REGISTRY as $USERNAME" >&2
