#!/usr/bin/env bash
# Check an image's CVE exceptions (ADR-008 §6):
#   scripts/check-vex.sh images/<name>
#
# images/<name>/vex.openvex.json is optional. If present, every statement needs
# an owner, and:
#   not_affected         needs a justification, and must name the current
#                        upstream version: it is re-validated on every bump
#   under_investigation  } temporary: needs x-stakater-expires, at most 30 days
#   affected             } after the document timestamp, and not yet passed
#   fixed                nothing more
# NOW (epoch seconds) overrides the current time; tests use it.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
MAX_DAYS=30

DIR=${1:?usage: check-vex.sh images/<name>}
DIR=${DIR%/}
VEX="$DIR/vex.openvex.json"

[ -f "$VEX" ] || {
  echo "$DIR: no VEX file, nothing to check"
  exit 0
}
jq -e . "$VEX" >/dev/null 2>&1 || {
  echo "$DIR: $VEX is not valid JSON" >&2
  exit 1
}
VERSION=$("$ENGINE" run --rm -i "$YQ_IMAGE" '.upstream.version // ""' <"$DIR/image.yaml") || {
  echo "$DIR: could not read $DIR/image.yaml (is $ENGINE running?)" >&2
  exit 1
}
[ -n "$VERSION" ] || {
  echo "$DIR: image.yaml has no upstream.version" >&2
  exit 1
}

# One line per problem; empty output means the file is fine.
problems=$(jq -r --arg version "$VERSION" --argjson now "${NOW:-$(date +%s)}" --argjson max "$MAX_DAYS" '
  def ts: try fromdateiso8601 catch null;
  (.timestamp | ts) as $doc
  | .statements // []
  | to_entries[]
  | .value as $s
  | ($s.vulnerability.name // "statement \(.key + 1)") as $id
  | ( if ($s["x-stakater-owner"] // "") == "" then "\($id): needs an x-stakater-owner" else empty end ),
    ( if $s.status == "not_affected" then
        ( if ($s.justification // "") == "" then "\($id): not_affected needs a justification" else empty end ),
        ( if ([$s.products[]?["@id"] | select(contains($version))] | length) == 0
          then "\($id): not_affected does not name upstream \($version). Re-validate it for this version and update its products."
          else empty end )
      elif $s.status == "under_investigation" or $s.status == "affected" then
        ( ($s["x-stakater-expires"] // "") as $e
          | if $e == "" then "\($id): \($s.status) is temporary and needs x-stakater-expires"
            elif ($e | ts) == null then "\($id): x-stakater-expires \($e) is not an ISO 8601 UTC timestamp"
            elif ($e | ts) <= $now then "\($id): expired on \($e)"
            elif $doc != null and (($e | ts) - $doc) > ($max * 86400) then "\($id): expires \($e), more than \($max) days after the document timestamp"
            else empty end )
      elif $s.status == "fixed" then empty
      else "\($id): unknown status \($s.status // "(none)")"
      end )
' "$VEX")

if [ -n "$problems" ]; then
  printf '%s\n' "$problems" | sed "s|^|$DIR: vex: |" >&2
  exit 1
fi
echo "$DIR: vex ok"
