#!/usr/bin/env bash
# Deploy etcd-druid for the smoke test (scripts/smoke-test.sh).
#
# Renders upstream's own Helm chart, taken from the pinned source, with the
# image under test, and applies it to the test namespace: the CRDs, RBAC, the
# operator's configuration and its Deployment. The chart sets only
# allowPrivilegeEscalation on the container, which restricted pod security
# (and OpenShift's restricted SCC) does not accept, so the remaining settings
# are patched onto the Deployment here. A product deploying this image has to
# do the same.
#
# Passes when the operator's Deployment is available and runs the image under
# test, and the Etcd CRD is installed.
set -euo pipefail

NS=${TEST_NAMESPACE:?TEST_NAMESPACE must be set}
IMAGE=${TEST_IMAGE:?TEST_IMAGE must be set}
TIMEOUT=${TEST_TIMEOUT:-90}
CHART="${TEST_SOURCE:?TEST_SOURCE must point at the pinned upstream source}/charts"

command -v helm >/dev/null || {
  echo "deploy: helm is required" >&2
  exit 1
}
[ -f "$CHART/Chart.yaml" ] || {
  echo "deploy: no chart at $CHART (was the image built here, so that its source is in .ctx/?)" >&2
  exit 1
}
case "$IMAGE" in
  *@*)
    echo "deploy: a digest reference is not supported yet, got $IMAGE" >&2
    exit 1
    ;;
esac
repository=${IMAGE%:*}
tag=${IMAGE##*:}

# Restricted pod security: non-root, no privilege escalation, no capabilities,
# the default seccomp profile, a read-only root filesystem. With a UID given,
# run as that arbitrary UID in group 0, as OpenShift does.
uid=${TEST_RUN_AS_USER:-}
patch=$(jq -cn --arg uid "$uid" '
  { runAsNonRoot: true, allowPrivilegeEscalation: false, readOnlyRootFilesystem: true,
    capabilities: { drop: ["ALL"] }, seccompProfile: { type: "RuntimeDefault" } }
  + (if $uid == "" then {} else { runAsUser: ($uid | tonumber), runAsGroup: 0 } end)
  | { spec: { template: { spec: { containers: [ { name: "etcd-druid", securityContext: . } ] } } } }')

# The Deployment is applied first and patched at once: until the patch, the
# namespace refuses its pods, which is the point of the namespace.
helm template etcd-druid "$CHART" --namespace "$NS" --include-crds \
  --set "image.repository=$repository" --set "image.tag=$tag" --set image.imagePullPolicy=IfNotPresent |
  kubectl -n "$NS" apply -f - >/dev/null 2>&1 || {
  echo "deploy: could not apply upstream's chart" >&2
  exit 1
}
kubectl -n "$NS" patch deployment etcd-druid --type strategic -p "$patch" >/dev/null

kubectl -n "$NS" rollout status deployment/etcd-druid --timeout="${TIMEOUT}s" >/dev/null
image=$(kubectl -n "$NS" get deployment etcd-druid -o jsonpath='{.spec.template.spec.containers[0].image}')
[ "$image" = "$IMAGE" ] || {
  echo "deploy: the operator runs $image, not the image under test ($IMAGE)" >&2
  exit 1
}
echo "ok   - deployment.apps/etcd-druid is available, running the image under test"
restarts=$(kubectl -n "$NS" get pods -l gardener.cloud/role=etcd-druid -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}')
[ "$restarts" = "0" ] || {
  echo "deploy: the operator restarted ($restarts)" >&2
  exit 1
}
echo "ok   - no restarts"
kubectl get crd etcds.druid.gardener.cloud >/dev/null || {
  echo "deploy: the Etcd CRD is not installed" >&2
  exit 1
}
echo "ok   - the Etcd CRD is installed"
