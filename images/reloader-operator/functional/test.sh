#!/usr/bin/env bash
# Functional test for Reloader (docs/planning/f1-functional-tests.md).
# Run by scripts/smoke-test.sh once Reloader is up, in the same namespace.
#
# Proves the one thing Reloader exists to do:
#   - a workload annotated for Reloader IS rolled when a ConfigMap it uses changes;
#   - it is NOT rolled when a ConfigMap it does not use changes.
# A Reloader that restarts nothing is broken. So is one that restarts everything.
set -euo pipefail

NS=${TEST_NAMESPACE:?TEST_NAMESPACE must be set}
TIMEOUT=${TEST_TIMEOUT:-90}
SETTLE=${TEST_SETTLE:-15} # how long "nothing happened" is watched for
# The workload only has to exist and read a ConfigMap. pause does nothing, as a
# non-root user, which is all that is needed.
WORKLOAD_IMAGE=registry.k8s.io/pause:3.10@sha256:ee6521f290b2168b6e0935a181d4cff9be1ac3f505666ef0e3c98fae8199917a

k() { kubectl -n "$NS" "$@"; }
generation() { k get deployment ft-workload -o jsonpath='{.metadata.generation}'; }

k apply -f - >/dev/null <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: ft-used
data:
  value: "1"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ft-unused
data:
  value: "1"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ft-workload
  annotations:
    reloader.stakater.com/auto: "true"
spec:
  replicas: 1
  selector:
    matchLabels: { app: ft-workload }
  template:
    metadata:
      labels: { app: ft-workload }
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        seccompProfile: { type: RuntimeDefault }
      containers:
        - name: workload
          image: $WORKLOAD_IMAGE
          envFrom:
            - configMapRef: { name: ft-used }
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: { drop: [ALL] }
YAML
k rollout status deployment/ft-workload --timeout="${TIMEOUT}s" >/dev/null
before=$(generation)
echo "ok   - workload is running (generation $before), annotated for Reloader"

# Control: a ConfigMap the workload does not use. Nothing may roll.
k patch configmap ft-unused --type merge -p '{"data":{"value":"2"}}' >/dev/null
sleep "$SETTLE"
now=$(generation)
if [ "$now" != "$before" ]; then
  echo "FAIL - the workload was rolled (generation $before -> $now) by a ConfigMap it does not use" >&2
  exit 1
fi
echo "ok   - an unrelated ConfigMap change did not roll the workload"

# The real thing: a ConfigMap the workload uses. It must roll.
k patch configmap ft-used --type merge -p '{"data":{"value":"2"}}' >/dev/null
deadline=$(($(date +%s) + TIMEOUT))
while [ "$(generation)" = "$before" ]; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "FAIL - the workload was not rolled within ${TIMEOUT}s of its ConfigMap changing (generation still $before)" >&2
    exit 1
  fi
  sleep 2
done
k rollout status deployment/ft-workload --timeout="${TIMEOUT}s" >/dev/null
echo "ok   - changing its ConfigMap rolled the workload (generation $before -> $(generation)), and it came back up"
