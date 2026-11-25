#!/usr/bin/env bash
# Next release number for an upstream version (ADR-002 rule 3):
#   <list of tags> | scripts/next-release.sh <upstream-version>
#
# Tags are <upstream-version>-<release>. Reads one tag per line on stdin and
# prints the highest existing release plus one, or 1 if there is none. Tags for
# other versions, and anything that is not <version>-<number>, are ignored.
set -euo pipefail

VERSION=${1:?usage: next-release.sh <upstream-version> < tags}

max=0
while IFS= read -r tag; do
  # Exact prefix match on "<version>-", then digits only.
  [ "${tag#"$VERSION"-}" != "$tag" ] || continue
  n=${tag#"$VERSION"-}
  [[ "$n" =~ ^[0-9]+$ ]] || continue
  n=$((10#$n))
  [ "$n" -gt "$max" ] && max=$n
done
echo $((max + 1))
