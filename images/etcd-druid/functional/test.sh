#!/usr/bin/env bash
# Functional test for etcd-druid (docs/planning/f1-functional-tests.md).
# Run by scripts/smoke-test.sh once smoke/deploy.sh has the operator up.
#
# Proves the operator does its job: given an Etcd resource, it creates the
# StatefulSet for that etcd cluster, owned by the Etcd.
# Control: the namespace has no StatefulSet before the Etcd exists, so a pass
# cannot come from something left behind.
#
# It does not prove that etcd itself runs. The etcd pods use other images
# (etcd-wrapper, etcd-backup-restore), which this factory does not build yet.
set -euo pipefail

NS=${TEST_NAMESPACE:?TEST_NAMESPACE must be set}
TIMEOUT=${TEST_TIMEOUT:-90}
NAME=etcd-smoke

existing=$(kubectl -n "$NS" get statefulsets -o name)
if [ -n "$existing" ]; then
  echo "FAIL - the namespace already has a StatefulSet before any Etcd exists: $existing" >&2
  exit 1
fi
echo "ok   - control: no StatefulSet exists before the Etcd is created"

kubectl -n "$NS" apply -f - >/dev/null <<YAML
apiVersion: druid.gardener.cloud/v1alpha1
kind: Etcd
metadata:
  name: $NAME
spec:
  replicas: 1
  labels:
    app: $NAME
  etcd: {}
  backup: {}
YAML

deadline=$(($(date +%s) + TIMEOUT))
until kubectl -n "$NS" get statefulset "$NAME" >/dev/null 2>&1; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "FAIL - the operator did not create StatefulSet $NAME within ${TIMEOUT}s" >&2
    kubectl -n "$NS" get etcd "$NAME" -o jsonpath='{.status.lastOperation}{"\n"}{.status.lastErrors}{"\n"}' >&2 || true
    exit 1
  fi
  sleep 2
done
owner=$(kubectl -n "$NS" get statefulset "$NAME" -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}')
if [ "$owner" != "Etcd/$NAME" ]; then
  echo "FAIL - StatefulSet $NAME is owned by '$owner', expected 'Etcd/$NAME'" >&2
  exit 1
fi
echo "ok   - the operator created StatefulSet $NAME, owned by the Etcd"
kubectl -n "$NS" delete etcd "$NAME" --wait=false >/dev/null 2>&1 || true
