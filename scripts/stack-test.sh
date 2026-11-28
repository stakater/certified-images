#!/usr/bin/env bash
# Run a stack: several of our images that only work together, built from this
# checkout and run with each other on a throwaway kind cluster.
#   scripts/stack-test.sh stacks/<name>
#
# A stack directory holds:
#   images    one image name per line (a directory under images/); # comments
#   test.sh   executable; deploys the images together and exits 0 if they work
#
# Each image's own smoke test runs it next to upstream's builds of its peers.
# That cannot show that OUR builds work with each other; this does (story E.1).
#
# For every image <name>, test.sh gets, with <NAME> in capitals and "-" as "_":
#   TEST_IMAGE_<NAME>   the locally built image reference
#   TEST_SOURCE_<NAME>  its pinned upstream source, left by the build
# and TEST_ROOT (this repository), TEST_TIMEOUT.
#
# STACK_SKIP_BUILD=1 reuses images already built (localhost/stakater/<name>:build).
# STACK_NO_CLUSTER=1 runs test.sh against the current kubeconfig, with no kind
# cluster and no image loading; the unit tests use it.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)

DIR=${1:?usage: stack-test.sh stacks/<name>}
DIR=${DIR%/}
NAME=$(basename "$DIR")
CLUSTER=${STACK_CLUSTER:-certified-images-stack-$NAME}
die() {
  echo "stack-test: $*" >&2
  exit 1
}

[ -f "$DIR/images" ] || die "$DIR/images is missing: it lists the images of the stack"
[ -f "$DIR/test.sh" ] || die "$DIR/test.sh is missing"
[ -x "$DIR/test.sh" ] || die "$DIR/test.sh is not executable"

images=()
while IFS= read -r line; do
  line=${line%%#*}
  line=$(printf '%s' "$line" | tr -d '[:space:]')
  [ -n "$line" ] || continue
  [[ "$line" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || die "'$line' in $DIR/images is not an image name"
  [ -f "$ROOT/images/$line/image.yaml" ] || die "$DIR/images names '$line', but there is no images/$line"
  images+=("$line")
done <"$DIR/images"
[ "${#images[@]}" -ge 2 ] || die "$DIR/images must list at least two images; one image is what the smoke test is for"

refs=()
for image in "${images[@]}"; do
  ref="localhost/stakater/$image:build"
  if [ -z "${STACK_SKIP_BUILD:-}" ]; then
    echo "--- build: $image" >&2
    "$ROOT/scripts/build-image.sh" "$ROOT/images/$image" >/dev/null
  fi
  var=$(printf '%s' "$image" | tr 'a-z-' 'A-Z_')
  export "TEST_IMAGE_$var=$ref"
  export "TEST_SOURCE_$var=$ROOT/.ctx/$image/src"
  refs+=("$ref")
done
export TEST_ROOT="$ROOT" TEST_TIMEOUT="${TEST_TIMEOUT:-90}"

if [ -z "${STACK_NO_CLUSTER:-}" ]; then
  for tool in kind kubectl; do
    command -v "$tool" >/dev/null || die "$tool is required"
  done
  for ref in "${refs[@]}"; do
    "$ENGINE" image inspect "$ref" >/dev/null 2>&1 || die "$ref is not built (run without STACK_SKIP_BUILD)"
  done
  KUBECONFIG=$(mktemp)
  export KUBECONFIG
  cleanup() {
    kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true
    rm -f "$KUBECONFIG"
  }
  trap cleanup EXIT
  kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true
  kind create cluster --name "$CLUSTER" --image "$KIND_NODE_IMAGE" --wait 120s >&2
  kind load docker-image "${refs[@]}" --name "$CLUSTER" >&2
fi

echo "--- stack test: $DIR/test.sh (${images[*]})"
if "$DIR/test.sh"; then
  echo "stack-test: the images of stack $NAME work together"
else
  echo "FAIL - stack $NAME: the images do not work together" >&2
  exit 1
fi
