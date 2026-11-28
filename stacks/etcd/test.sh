#!/usr/bin/env bash
# The etcd stack, end to end (scripts/stack-test.sh): our etcd-druid creates an
# etcd whose two containers are our etcd-wrapper and our etcd-backup-restore,
# and that etcd stores a key.
#
# The etcd pod is the one etcd-druid generates, unchanged. That is the point:
# it runs as UID 65532 with group 65532 and uses the images' own filesystem,
# which the per-image smoke tests (their own pod, an arbitrary UID, volumes
# over the writable paths) do not exercise. This test was added after exactly
# that difference let a defect through (2026-11-28): the sidecar could not
# write into the image's home directory, and etcd never started.
#
# Control: the key does not exist before it is written.
set -euo pipefail

DRUID=${TEST_IMAGE_ETCD_DRUID:?} WRAPPER=${TEST_IMAGE_ETCD_WRAPPER:?} BR=${TEST_IMAGE_ETCD_BACKUP_RESTORE:?}
ROOT=${TEST_ROOT:?} TIMEOUT=${TEST_TIMEOUT:-90}
# A client with etcdctl, to write and read a key the way a user of etcd does.
# etcd-druid's etcd has no HTTP API. Upstream etcd, pinned by digest.
CLIENT=registry.k8s.io/etcd:3.6.8-0@sha256:397189418d1a00e500c0605ad18d1baf3b541a1004d768448c367e48071622e5
OPERATOR_NS=stack-etcd-druid NS=stack-etcd NAME=stack

# The operator, deployed the way its own smoke test deploys it.
kubectl create namespace "$OPERATOR_NS" >/dev/null
kubectl label namespace "$OPERATOR_NS" pod-security.kubernetes.io/enforce=restricted >/dev/null
TEST_NAMESPACE=$OPERATOR_NS TEST_IMAGE=$DRUID TEST_RUN_AS_USER=1000680000 TEST_SOURCE=${TEST_SOURCE_ETCD_DRUID:?} \
  "$ROOT/images/etcd-druid/smoke/deploy.sh"

kubectl create namespace "$NS" >/dev/null
kubectl -n "$NS" apply -f - >/dev/null <<YAML
apiVersion: druid.gardener.cloud/v1alpha1
kind: Etcd
metadata:
  name: $NAME
spec:
  replicas: 1
  labels:
    app: $NAME
  etcd:
    image: $WRAPPER
  backup:
    image: $BR
YAML

fail() {
  echo "FAIL - $1" >&2
  {
    kubectl -n "$NS" get etcd,statefulset,pods -o wide || true
    echo "--- events"
    kubectl -n "$NS" get events --sort-by=.lastTimestamp | tail -n 12 || true
    for c in etcd backup-restore; do
      echo "--- container $c"
      kubectl -n "$NS" logs "$NAME-0" -c "$c" --tail=12 | cut -c1-400 || true
    done
  } >&2 2>&1
  exit 1
}

deadline=$(($(date +%s) + TIMEOUT * 3))
until [ "$(kubectl -n "$NS" get etcd "$NAME" -o jsonpath='{.status.ready}' 2>/dev/null)" = "true" ]; do
  [ "$(date +%s)" -lt "$deadline" ] || fail "our etcd-druid did not report the Etcd ready within $((TIMEOUT * 3))s"
  sleep 5
done
echo "ok   - our etcd-druid created an etcd and reports it ready"

images=$(kubectl -n "$NS" get pod "$NAME-0" -o jsonpath='{.spec.containers[*].image}')
[ "$images" = "$WRAPPER $BR" ] || fail "the etcd pod runs '$images', expected our wrapper and our sidecar"
echo "ok   - its pod runs our etcd-wrapper and our etcd-backup-restore, and nothing else"
uid=$(kubectl -n "$NS" get pod "$NAME-0" -o jsonpath='{.spec.securityContext.runAsUser}:{.spec.securityContext.runAsGroup}')
echo "ok   - as etcd-druid runs it (user:group $uid), with no volume over the images' own directories"
restarts=$(kubectl -n "$NS" get pod "$NAME-0" -o jsonpath='{.status.containerStatuses[*].restartCount}')
[ "$restarts" = "0 0" ] || fail "a container of the etcd pod restarted ($restarts)"
echo "ok   - no restarts"

health=$(kubectl get --raw "/api/v1/namespaces/$NS/pods/$NAME-0:8080/proxy/healthz") || fail "the sidecar does not answer /healthz"
[ "$(printf '%s' "$health" | jq -r '.health')" = "true" ] || fail "the sidecar reports etcd unhealthy: $health"
echo "ok   - our sidecar reports etcd healthy"

ctl() { # ctl <pod suffix> <etcdctl arguments...>: run etcdctl in a pod and print its output
  local pod="ctl-$1"
  shift
  kubectl -n "$NS" run "$pod" --image="$CLIENT" --restart=Never \
    --command -- etcdctl --endpoints="http://$NAME-client:2379" "$@" >/dev/null
  kubectl -n "$NS" wait pod "$pod" --for=jsonpath='{.status.phase}'=Succeeded --timeout="${TIMEOUT}s" >/dev/null ||
    fail "etcdctl $* did not succeed: $(kubectl -n "$NS" logs "$pod" 2>&1 | tail -n 3)"
  kubectl -n "$NS" logs "$pod"
}
before=$(ctl before get stack-key --print-value-only)
[ -z "$before" ] || fail "the key exists before it is written: $before"
echo "ok   - control: the key does not exist yet"
ctl put put stack-key stack-value >/dev/null
got=$(ctl after get stack-key --print-value-only)
[ "$got" = "stack-value" ] || fail "read back '$got', expected 'stack-value'"
echo "ok   - a key written through the etcd client service is read back"
