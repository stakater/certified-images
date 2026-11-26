#!/usr/bin/env bash
# Fail if a staging package can be pulled by anyone:
#   scripts/assert-not-public.sh ghcr.io/<owner>/<path>
#
# Staging images are for Stakater teams only (ADR-002 rev 5). A package pushed
# from a public repository is created PUBLIC unless the organisation forbids it,
# and visibility cannot be set from a workflow. So the pipeline asks the
# registry the way a stranger would, with no credentials:
#   401 / 403  refused                      -> not public, pass
#   404        the package does not exist   -> nothing is public yet, pass
#   200        tags listed anonymously      -> PUBLIC, fail
#   anything else, or no answer             -> fail: never assume private
set -euo pipefail

REPO=${1:?usage: assert-not-public.sh ghcr.io/<owner>/<path>}
case "$REPO" in
  ghcr.io/*) path=${REPO#ghcr.io/} ;;
  *)
    echo "assert-not-public: only ghcr.io repositories are supported, got '$REPO'" >&2
    exit 1
    ;;
esac

# Deliberately no credentials: this must see what an outsider sees.
token=$(curl -s --max-time 30 "https://ghcr.io/token?scope=repository:$path:pull" | jq -r '.token // empty' 2>/dev/null || true)
code=$(curl -s --max-time 30 -o /dev/null -w '%{http_code}' ${token:+-H "Authorization: Bearer $token"} \
  "https://ghcr.io/v2/$path/tags/list" || true)

case "$code" in
  401 | 403)
    echo "assert-not-public: $REPO refuses anonymous access" >&2
    ;;
  404)
    echo "assert-not-public: $REPO does not exist yet, so nothing is public" >&2
    ;;
  200)
    cat >&2 <<MSG
assert-not-public: $REPO is PUBLIC. Anyone can pull it without credentials.
Staging images must be visible to the organisation only (ADR-002 rev 5).
Fix, as an organisation admin:
  1. Packages -> $(basename "$path") -> Package settings -> Change visibility -> Private or Internal.
  2. Organisation settings -> Packages -> Package creation -> untick Public,
     so new images are not created public.
MSG
    exit 1
    ;;
  *)
    echo "assert-not-public: could not tell whether $REPO is public (HTTP '$code'). Not assuming it is private." >&2
    exit 1
    ;;
esac
