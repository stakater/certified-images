#!/usr/bin/env bash
# Functional test for kube-state-metrics (docs/planning/f1-functional-tests.md).
# Run by scripts/smoke-test.sh once the pod is up, in the same namespace.
#
# Proves it does its job: an object created in the cluster shows up in the
# metrics it serves.
# Control: the metric for that object is not there before the object exists,
# so a pass cannot come from something left behind.
set -euo pipefail

NS=${TEST_NAMESPACE:?TEST_NAMESPACE must be set}
POD=${TEST_POD:-smoke}
TIMEOUT=${TEST_TIMEOUT:-90}
NAME=ksm-functional
SERIES="kube_configmap_info{namespace=\"$NS\",configmap=\"$NAME\"}"

metrics() { kubectl get --raw "/api/v1/namespaces/$NS/pods/$POD:8080/proxy/metrics"; }
# The output is captured and handed to grep as a here-string, not through a
# pipe: with pipefail, grep -q closing a pipe early makes a match look like a
# failure.
reports() { # reports <fixed string>: is it in the metrics served now?
  local out
  out=$(metrics) || return 1
  grep -qF -- "$1" <<<"$out"
}
has_series() { reports "$SERIES"; }

metrics >/dev/null || {
  echo "FAIL - no metrics at /metrics on port 8080" >&2
  exit 1
}
# The ConfigMap metrics must already be flowing, or "absent" proves nothing.
deadline=$(($(date +%s) + TIMEOUT))
until reports "kube_configmap_info{namespace=\"$NS\","; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "FAIL - no ConfigMap of this namespace is reported within ${TIMEOUT}s (kube-root-ca.crt should be)" >&2
    echo "--- ConfigMap series served (first 3), and the pod's last lines:" >&2
    metrics | grep '^kube_configmap' | sed -n '1,3p' >&2 || true
    kubectl -n "$NS" logs "$POD" --tail=5 >&2 || true
    exit 1
  fi
  sleep 2
done
if has_series; then
  echo "FAIL - $SERIES is reported before the ConfigMap exists" >&2
  exit 1
fi
echo "ok   - control: ConfigMaps of the namespace are reported, and $NAME is not among them"

kubectl -n "$NS" create configmap "$NAME" --from-literal=k=v >/dev/null
deadline=$(($(date +%s) + TIMEOUT))
until has_series; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "FAIL - the new ConfigMap was not reported within ${TIMEOUT}s" >&2
    exit 1
  fi
  sleep 2
done
echo "ok   - a ConfigMap created just now is reported in the metrics"
kubectl -n "$NS" delete configmap "$NAME" --wait=false >/dev/null 2>&1 || true
