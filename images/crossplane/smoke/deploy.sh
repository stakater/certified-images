#!/usr/bin/env bash
# Deploy Crossplane for the smoke test (scripts/smoke-test.sh).
#
# Installs upstream's own Helm chart, taken from the pinned source, with the
# image under test, into the test namespace. The namespace enforces restricted
# pod security, so the chart's containers get the settings that requires. That
# is also what OpenShift's restricted SCC needs.
#
# Passes when the init step has installed the CRDs and both deployments
# (crossplane and its RBAC manager) are available.
set -euo pipefail

NS=${TEST_NAMESPACE:?TEST_NAMESPACE must be set}
IMAGE=${TEST_IMAGE:?TEST_IMAGE must be set}
TIMEOUT=${TEST_TIMEOUT:-90}
CHART="${TEST_SOURCE:?TEST_SOURCE must point at the pinned upstream source}/cluster/charts/crossplane"

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
security=$(jq -cn --arg uid "$uid" '
  { runAsNonRoot: true, allowPrivilegeEscalation: false, readOnlyRootFilesystem: true,
    capabilities: { drop: ["ALL"] }, seccompProfile: { type: "RuntimeDefault" } }
  + (if $uid == "" then {} else { runAsUser: ($uid | tonumber), runAsGroup: 0 } end)')

helm upgrade --install crossplane-smoke "$CHART" --namespace "$NS" \
  --set "image.repository=$repository" --set "image.tag=$tag" --set image.pullPolicy=IfNotPresent \
  --set-json "securityContextCrossplane=$security" \
  --set-json "securityContextRBACManager=$security" \
  --wait --timeout "$((TIMEOUT * 2))s" >/dev/null

kubectl -n "$NS" wait --for=condition=Available deployment --all --timeout="${TIMEOUT}s" >/dev/null
for d in $(kubectl -n "$NS" get deployments -o name); do
  image=$(kubectl -n "$NS" get "$d" -o jsonpath='{.spec.template.spec.containers[0].image}')
  [ "$image" = "$IMAGE" ] || {
    echo "deploy: $d runs $image, not the image under test ($IMAGE)" >&2
    exit 1
  }
  echo "ok   - $d is available, running the image under test"
done
kubectl get crd providers.pkg.crossplane.io >/dev/null || {
  echo "deploy: the init step did not install Crossplane's CRDs" >&2
  exit 1
}
echo "ok   - the init step installed Crossplane's CRDs"
