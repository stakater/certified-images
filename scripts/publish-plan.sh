#!/usr/bin/env bash
# Decide whether an image can be published, and where to:
#   scripts/publish-plan.sh images/<name>
#
# Prints key=value lines (also valid for $GITHUB_OUTPUT):
#   publishable  true | false   (to Red Hat; staging does not depend on it)
#   reason       why not, when false
#   staging_repository   where every build is staged (always printed)
#   component_id, suffix, version, repository   (repository: Red Hat's, when publishable)
#
# An image whose redhat.componentId is still the placeholder is not publishable.
# That is a normal state while Partner Connect is pending, so it is reported,
# not treated as an error. A malformed ID is an error.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
REGISTRY=${PUBLISH_REGISTRY:-quay.io/redhat-isv-containers}
# Staging (ADR-002 rev 5). "ubi", not "certified": an image here has passed
# our checks, not Red Hat's.
STAGING=${STAGING_REGISTRY:-ghcr.io/stakater/ubi}

DIR=${1:?usage: publish-plan.sh images/<name>}
DIR=${DIR%/}

JSON=$("$ENGINE" run --rm -i "$YQ_IMAGE" -o=json '.' <"$DIR/image.yaml") || {
  echo "publish-plan: could not read $DIR/image.yaml" >&2
  exit 1
}
get() { printf '%s' "$JSON" | jq -r "$1 // \"\""; }

id=$(get .redhat.componentId)
suffix=$(get .redhat.secretSuffix)
version=$(get .upstream.version)

echo "suffix=$suffix"
echo "version=$version"
echo "staging_repository=$STAGING/$(get .name)"
case "$id" in
  "" | TODO*)
    echo "publishable=false"
    echo "reason=redhat.componentId is not set in $DIR/image.yaml (create the Partner Connect component first)"
    ;;
  *)
    [[ "$id" =~ ^[a-f0-9]{24}$ ]] || {
      echo "publish-plan: redhat.componentId '$id' is not a Partner Connect component ID (24 hex characters)" >&2
      exit 1
    }
    echo "publishable=true"
    echo "component_id=$id"
    echo "repository=$REGISTRY/$id"
    ;;
esac
