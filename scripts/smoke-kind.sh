#!/usr/bin/env bash
# Level 1 smoke test: run scripts/smoke-test.sh on a throwaway kind cluster.
#   scripts/smoke-kind.sh <local-image-ref> images/<name>
#
# Creates a cluster, loads the locally built image into it, runs the smoke
# test, and deletes the cluster. Needs kind and kubectl on the machine; the
# node image is pinned in tools.env.
#
# This approximates OpenShift's restricted security context with Kubernetes'
# restricted pod security. It is NOT a test on OpenShift.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)

REF=${1:?usage: smoke-kind.sh <local-image-ref> images/<name>}
DIR=${2:?usage: smoke-kind.sh <local-image-ref> images/<name>}
CLUSTER=${SMOKE_CLUSTER:-certified-images-smoke}

for tool in kind kubectl; do
  command -v "$tool" >/dev/null || {
    echo "smoke-kind: $tool is required" >&2
    exit 1
  }
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
kind load docker-image "$REF" --name "$CLUSTER" >&2
"$ROOT/scripts/smoke-test.sh" "$REF" "$DIR"
