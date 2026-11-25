#!/usr/bin/env bash
# Prefetch an image's dependencies with Hermeto (ADR-003 §2):
#   scripts/prefetch.sh images/<name> <context-dir>
#
# Expects <context-dir>/src from scripts/fetch-source.sh. Leaves, next to it:
#   hermeto-output/   the dependencies and bom.json (the dependency SBOM)
#   hermeto.env       environment the Containerfile sources before building
# This is the only step of the build that uses the network.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
# Where the Containerfile copies hermeto-output/ to inside the build stage.
IN_BUILD_DIR=/tmp/hermeto-output

DIR=${1:?usage: prefetch.sh images/<name> <context-dir>}
CTX=${2:?usage: prefetch.sh images/<name> <context-dir>}
DIR=${DIR%/}

die() {
  echo "prefetch: $*" >&2
  exit 1
}

[ -d "$CTX/src/.git" ] || die "$CTX/src is not a git checkout; run scripts/fetch-source.sh first (Hermeto needs .git)"
CTX=$(cd "$CTX" && pwd)

PREFETCH=$("$ENGINE" run --rm -i "$YQ_IMAGE" '.build.prefetch // ""' <"$DIR/image.yaml") || die "could not read $DIR/image.yaml"
[ -n "$PREFETCH" ] || die "$DIR/image.yaml has no build.prefetch"

hermeto() { "$ENGINE" run --rm -v "$CTX:$CTX" -w "$CTX" "$HERMETO_IMAGE" "$@"; }

# SPDX, to match the image SBOM (ADR-008 §1). Hermeto's default is CycloneDX.
hermeto fetch-deps --source ./src --output ./hermeto-output --sbom-output-type spdx "$PREFETCH"
hermeto generate-env ./hermeto-output -o ./hermeto.env --for-output-dir "$IN_BUILD_DIR"
hermeto inject-files ./hermeto-output --for-output-dir "$IN_BUILD_DIR"

[ -s "$CTX/hermeto-output/bom.json" ] || die "Hermeto produced no dependency SBOM (hermeto-output/bom.json)"

# The build context must not carry git history.
rm -rf "$CTX/src/.git"
echo "prefetch: dependencies and SBOM in $CTX/hermeto-output" >&2
