#!/usr/bin/env bash
# Remove what smoke/deploy.sh created outside the namespace (scripts/smoke-test.sh
# runs this last): the operator's ClusterRole and ClusterRoleBinding. The
# namespace is deleted by the smoke test itself. The CRDs are left in place: on
# the throwaway cluster used for pull requests they go with the cluster, and
# deleting CRDs on a shared cluster is not something a test does.
set -uo pipefail

NS=${TEST_NAMESPACE:?TEST_NAMESPACE must be set}
CHART="${TEST_SOURCE:-}/charts"
[ -f "$CHART/Chart.yaml" ] || exit 0
helm template etcd-druid "$CHART" --namespace "$NS" 2>/dev/null |
  kubectl -n "$NS" delete -f - --ignore-not-found --wait=false >/dev/null 2>&1 || true
