#!/usr/bin/env bash
# Scan the newest published release of an image for vulnerabilities:
#   scripts/rescan-image.sh images/<name> <output-dir>
#
# Looks up the newest release of the image's current upstream version on GHCR
# and scans it with the build's own gate: fixable CRITICAL and HIGH, with the
# image's VEX file applied. The GHCR digest is the digest Red Hat has.
#
# Writes <output-dir>/trivy.json and <output-dir>/findings.jsonl, and prints
# key=value lines: published, tag, ref, findings. Exits 0 whether or not there
# are findings; it fails only if it could not look.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)

DIR=${1:?usage: rescan-image.sh images/<name> <output-dir>}
OUT=${2:?usage: rescan-image.sh images/<name> <output-dir>}
DIR=$(cd "${DIR%/}" && pwd)
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

plan=$("$ROOT/scripts/publish-plan.sh" "$DIR")
repo=$(printf '%s\n' "$plan" | sed -n 's/^staging_repository=//p')
version=$(printf '%s\n' "$plan" | sed -n 's/^version=//p')

tags=$("$ROOT/scripts/list-tags.sh" "$repo")
tag=$(printf '%s\n' "$tags" | "$ROOT/scripts/latest-release.sh" "$version")
if [ -z "$tag" ]; then
  echo "published=false"
  echo "rescan-image: no release of $version is published at $repo" >&2
  exit 0
fi
ref="$repo:$tag"

mounts=(-v "$OUT:/out")
flags=()
if [ -f "$DIR/vex.openvex.json" ]; then
  mounts+=(-v "$DIR/vex.openvex.json:/vex.openvex.json:ro")
  flags+=(--vex /vex.openvex.json)
fi
auth=${REGISTRY_AUTH_FILE:-${DOCKER_CONFIG:-$HOME/.docker}/config.json}
[ -f "$auth" ] && mounts+=(-v "$auth:/root/.docker/config.json:ro")

"$ENGINE" run --rm "${mounts[@]}" "$TRIVY_IMAGE" image --scanners vuln --ignore-unfixed \
  --severity CRITICAL,HIGH --no-progress --format json -o /out/trivy.json \
  ${flags[@]+"${flags[@]}"} "$ref" >&2

"$ROOT/scripts/scan-findings.sh" "$OUT/trivy.json" >"$OUT/findings.jsonl"
echo "published=true"
echo "tag=$tag"
echo "ref=$ref"
echo "findings=$(grep -c . "$OUT/findings.jsonl" || true)"
