#!/usr/bin/env bash
# Check that a staging package is not more open than its image declares:
#   scripts/assert-visibility.sh ghcr.io/<owner>/<path> <public|private>
#
# image.yaml declares each image's staging visibility; private is the default
# (ADR-002 rev 6). A package pushed from a public repository is created PUBLIC
# unless the organisation forbids it, and a workflow cannot set visibility. So
# the pipeline asks the registry the way a stranger would, with no credentials:
#
#   declared private:  401/403 refused, or 404 no such package  -> pass
#                      200 tags listed anonymously              -> FAIL
#   declared public:   200, or 404 before the first push        -> pass
#                      401/403 (actually private)               -> pass, with a
#                      warning: safer than declared, but not what was intended
#   anything else, or no answer -> fail. "Could not tell" is never assumed
#   to mean private.
set -euo pipefail

REPO=${1:?usage: assert-visibility.sh ghcr.io/<owner>/<path> <public|private>}
DECLARED=${2:?usage: assert-visibility.sh ghcr.io/<owner>/<path> <public|private>}
case "$DECLARED" in
  public | private) ;;
  *)
    echo "assert-visibility: visibility must be public or private, got '$DECLARED'" >&2
    exit 1
    ;;
esac
case "$REPO" in
  ghcr.io/*) path=${REPO#ghcr.io/} ;;
  *)
    echo "assert-visibility: only ghcr.io repositories are supported, got '$REPO'" >&2
    exit 1
    ;;
esac

# Deliberately no credentials: this must see what an outsider sees.
token=$(curl -s --max-time 30 "https://ghcr.io/token?scope=repository:$path:pull" | jq -r '.token // empty' 2>/dev/null || true)
code=$(curl -s --max-time 30 -o /dev/null -w '%{http_code}' ${token:+-H "Authorization: Bearer $token"} \
  "https://ghcr.io/v2/$path/tags/list" || true)

case "$code" in
  401 | 403) actual=private ;;
  404) actual=absent ;;
  200) actual=public ;;
  *)
    echo "assert-visibility: could not tell whether $REPO is public (HTTP '$code'). Not assuming it is private." >&2
    exit 1
    ;;
esac

if [ "$actual" = "absent" ]; then
  echo "assert-visibility: $REPO does not exist yet, so nothing is public" >&2
elif [ "$actual" = "$DECLARED" ]; then
  echo "assert-visibility: $REPO is $actual, as declared" >&2
elif [ "$DECLARED" = "public" ]; then
  echo "::warning title=Staging package is private::$REPO is declared public in image.yaml but refuses anonymous access." >&2
  echo "assert-visibility: $REPO is declared public but is private. That is safe; change the package's visibility if public was intended." >&2
else
  cat >&2 <<MSG
assert-visibility: $REPO is PUBLIC, but its image.yaml does not declare it public.
Anyone can pull it without credentials (ADR-002 rev 6).
Either, as an organisation admin:
  1. Packages -> $(basename "$path") -> Package settings -> Change visibility -> Private or Internal.
  2. Organisation settings -> Packages -> Package creation -> untick Public,
     so new images are not created public.
Or, if this image is meant to be public, declare it in image.yaml, in a reviewed PR:
  staging:
    visibility: public
MSG
  exit 1
fi
