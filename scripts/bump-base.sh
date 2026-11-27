#!/usr/bin/env bash
# Point an image's Containerfile at the current digest of its UBI base:
#   scripts/bump-base.sh images/<name>
# Prints changed=true or changed=false. This is the fix for a vulnerability in
# a UBI package: Red Hat ships the fixed package in a newer base image
# (ADR-003 §5, ADR-004).
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

DIR=${1:?usage: bump-base.sh images/<name>}
CF="${DIR%/}/Containerfile"
arg() { sed -n "s/^ARG $1=//p" "$CF" | head -n1; }
registry=$(arg BASE_REGISTRY)
image=$(arg BASE_IMAGE)
current=$(arg BASE_TAG)
tag=${current%%@*}
[ -n "$registry" ] && [ -n "$image" ] && [ -n "$tag" ] || {
  echo "bump-base: $CF does not declare BASE_REGISTRY, BASE_IMAGE and BASE_TAG" >&2
  exit 1
}

digest=$(crane digest "$registry/$image:$tag" | tr -d '[:space:]')
[[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || {
  echo "bump-base: the registry did not return a digest for $registry/$image:$tag (got '$digest')" >&2
  exit 1
}

if [ "$current" = "$tag@$digest" ]; then
  echo "changed=false"
  exit 0
fi
sed -i.bak "s|^ARG BASE_TAG=.*|ARG BASE_TAG=$tag@$digest|" "$CF" && rm -f "$CF.bak"
echo "changed=true"
echo "bump-base: $registry/$image ${current#*@} -> $digest" >&2
