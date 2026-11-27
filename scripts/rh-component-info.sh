#!/usr/bin/env bash
# Ask Red Hat how a component is distributed:
#   RH_PYXIS_TOKEN=... scripts/rh-component-info.sh <component-id>
#
# Prints key=value lines (also valid for $GITHUB_OUTPUT):
#   hosted            true   Red Hat stores the image: we push it to Red Hat's
#                            registry, with the component's registry key (setup A)
#                     false  we store it on GHCR and Red Hat lists it under its
#                            own address: we only submit results (setup B)
#   pull_repository   the address customers pull from
#
# Red Hat's record is the single source of truth for this, so it is read from
# there and not declared in image.yaml. If it cannot be read, this fails: the
# pipeline must never guess which registry to publish to.
# See docs/red-hat-distribution.md.
set -euo pipefail

BASE=${PYXIS_URL:-https://catalog.redhat.com/api/containers/v1}
ID=${1:?usage: rh-component-info.sh <component-id>}
[[ "$ID" =~ ^[a-f0-9]{24}$ ]] || {
  echo "rh-component-info: '$ID' is not a Partner Connect component ID (24 hex characters)" >&2
  exit 1
}
: "${RH_PYXIS_TOKEN:?RH_PYXIS_TOKEN must be set (from a repository secret)}"
KEY=$(printf '%s' "$RH_PYXIS_TOKEN" | tr -d '[:space:]')

body=$(mktemp)
trap 'rm -f "$body"' EXIT
code=$(printf 'header = "X-API-KEY: %s"\n' "$KEY" |
  curl --config - -s --max-time 30 -o "$body" -w '%{http_code}' "$BASE/projects/certification/id/$ID" || true)

if [ "$code" != "200" ]; then
  detail=$(jq -r '"\(.title // "?"): \(.detail // "")"' "$body" 2>/dev/null | awk -v k="$KEY" '{ gsub(k, "<key>"); print }' | cut -c1-200 || true)
  echo "rh-component-info: Red Hat answered HTTP ${code:-none} for component $ID. $detail" >&2
  exit 1
fi

hosted=$(jq -r '.container.hosted_registry | if type == "boolean" then tostring else "" end' "$body" 2>/dev/null || true)
[ -n "$hosted" ] || {
  echo "rh-component-info: Red Hat's record for $ID has no container.hosted_registry flag. Not guessing how it is distributed." >&2
  exit 1
}
method=$(jq -r '.container.distribution_method // ""' "$body")
# "rhcc" is Red Hat's catalog: customers pull from registry.connect.redhat.com.
# Anything else (our own registry as the distribution) is a model this pipeline
# does not publish to yet.
[ "$method" = "rhcc" ] || {
  echo "rh-component-info: component $ID has distribution method '$method'. Only Red Hat's catalog ('rhcc') is supported (docs/red-hat-distribution.md)." >&2
  exit 1
}
ns=$(jq -r '.container.repository_namespace // ""' "$body")
name=$(jq -r '.container.repository_name // ""' "$body")

echo "hosted=$hosted"
echo "pull_repository=registry.connect.redhat.com/$ns/$name"
