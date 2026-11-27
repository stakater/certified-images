#!/usr/bin/env bash
# Newest published release tag of an upstream version:
#   <list of tags> | scripts/latest-release.sh <upstream-version>
# Prints <version>-<highest release>, or nothing if none is published.
# The counterpart of next-release.sh.
set -euo pipefail

VERSION=${1:?usage: latest-release.sh <upstream-version> < tags}
max=0
while IFS= read -r tag; do
  [ "${tag#"$VERSION"-}" != "$tag" ] || continue
  n=${tag#"$VERSION"-}
  [[ "$n" =~ ^[0-9]+$ ]] || continue
  n=$((10#$n))
  [ "$n" -gt "$max" ] && max=$n
done
[ "$max" -eq 0 ] || echo "$VERSION-$max"
