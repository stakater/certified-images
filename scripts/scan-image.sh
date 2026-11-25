#!/usr/bin/env bash
# SBOM and CVE gate for a built image (ADR-008 §1, §4, §6):
#   scripts/scan-image.sh <image-ref> images/<name> <context-dir>
#
# Writes into <context-dir>/evidence/:
#   sbom.image.spdx.json   syft scan of the final image (OS packages + binary)
#   sbom.deps.spdx.json    Hermeto's SBOM of the build inputs (from prefetch)
#   trivy.txt              the scan report
# Fails on any fixable CRITICAL or HIGH vulnerability that the image's VEX file
# does not cover. The VEX file itself is checked first (scripts/check-vex.sh).
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

REF=${1:?usage: scan-image.sh <image-ref> images/<name> <context-dir>}
DIR=${2:?usage: scan-image.sh <image-ref> images/<name> <context-dir>}
CTX=${3:?usage: scan-image.sh <image-ref> images/<name> <context-dir>}
DIR=$(cd "${DIR%/}" && pwd)
ROOT=$(cd "$(dirname "$0")/.." && pwd)

"$ROOT/scripts/check-vex.sh" "$DIR"

mkdir -p "$CTX/evidence" "$CTX/.trivy-cache"
CTX=$(cd "$CTX" && pwd)
EV="$CTX/evidence"

# Scan a saved archive, so the scanners need no access to the container engine.
"$ENGINE" save "$REF" -o "$EV/image.tar"
trap 'rm -f "$EV/image.tar"' EXIT

"$ENGINE" run --rm -v "$EV:/ev" "$SYFT_IMAGE" scan "docker-archive:/ev/image.tar" -q -o "spdx-json=/ev/sbom.image.spdx.json"
[ -s "$EV/sbom.image.spdx.json" ] || {
  echo "scan-image: syft wrote no SBOM" >&2
  exit 1
}

if [ -s "$CTX/hermeto-output/bom.json" ]; then
  cp "$CTX/hermeto-output/bom.json" "$EV/sbom.deps.spdx.json"
else
  echo "scan-image: no dependency SBOM at $CTX/hermeto-output/bom.json (was the image built by build-image.sh?)" >&2
  exit 1
fi

# ${arr[@]+"${arr[@]}"}: bash 3.2 (macOS) treats an empty array as unset under set -u.
vex=()
if [ -f "$DIR/vex.openvex.json" ]; then
  vex=(-v "$DIR/vex.openvex.json:/vex.openvex.json:ro")
  vex_flag=(--vex /vex.openvex.json)
else
  vex_flag=()
fi

set +e
"$ENGINE" run --rm -v "$EV:/ev" -v "$CTX/.trivy-cache:/root/.cache/trivy" ${vex[@]+"${vex[@]}"} "$TRIVY_IMAGE" \
  image --input /ev/image.tar --scanners vuln --ignore-unfixed --severity CRITICAL,HIGH \
  --exit-code 1 --no-progress ${vex_flag[@]+"${vex_flag[@]}"} | tee "$EV/trivy.txt"
rc=${PIPESTATUS[0]}
set -e

if [ "$rc" -ne 0 ]; then
  echo "scan-image: fixable CRITICAL or HIGH vulnerabilities found (or the scan failed). See $EV/trivy.txt" >&2
  echo "scan-image: fix by bumping the base digest or a dependency (ADR-002 rule 2), or record an OpenVEX exception (ADR-008 §6)." >&2
  exit 1
fi
echo "scan-image: no fixable CRITICAL or HIGH vulnerabilities. Evidence in $EV" >&2
