#!/usr/bin/env bash
# Deploy Prometheus for the smoke test (scripts/smoke-test.sh).
#
# Prometheus keeps its time series in a data directory, so it cannot use the
# generic smoke pod, which has no writable path. This runs it as one pod named
# "prometheus" under restricted pod security: non-root, a read-only root
# filesystem, no capabilities, and an emptyDir for the data directory. It uses
# the configuration file in the image, which makes it scrape itself.
#
# Passes when the pod is Ready, which means Prometheus answers /-/ready, and
# has not restarted.
set -euo pipefail

NS=${TEST_NAMESPACE:?TEST_NAMESPACE must be set}
IMAGE=${TEST_IMAGE:?TEST_IMAGE must be set}
TIMEOUT=${TEST_TIMEOUT:-90}
uid=${TEST_RUN_AS_USER:-}

jq -n --arg image "$IMAGE" --arg uid "$uid" '{
  apiVersion: "v1", kind: "Pod",
  metadata: { name: "prometheus", labels: { "app.kubernetes.io/name": "prometheus" } },
  spec: {
    restartPolicy: "Never",
    automountServiceAccountToken: false,
    securityContext: ({ runAsNonRoot: true, runAsGroup: 0, fsGroup: 0, seccompProfile: { type: "RuntimeDefault" } }
      + (if $uid == "" then {} else { runAsUser: ($uid | tonumber) } end)),
    containers: [ {
      name: "prometheus", image: $image, imagePullPolicy: "IfNotPresent",
      ports: [ { containerPort: 9090 } ],
      securityContext: { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: ["ALL"] } },
      readinessProbe: { httpGet: { path: "/-/ready", port: 9090 }, periodSeconds: 3, failureThreshold: 60 },
      volumeMounts: [ { name: "data", mountPath: "/prometheus" } ]
    } ],
    volumes: [ { name: "data", emptyDir: {} } ]
  }
}' | kubectl -n "$NS" apply -f - >/dev/null
echo "ok   - pod admitted under restricted pod security"

# Poll, so a container that exits is reported at once and not after the timeout.
deadline=$(($(date +%s) + TIMEOUT * 2))
while :; do
  ready=$(kubectl -n "$NS" get pod prometheus -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  phase=$(kubectl -n "$NS" get pod prometheus -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [ "$ready" = "True" ] && break
  case "$phase" in Failed | Succeeded)
    echo "deploy: Prometheus exited before becoming ready (phase $phase)" >&2
    exit 1
    ;;
  esac
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "deploy: Prometheus did not answer /-/ready within $((TIMEOUT * 2))s" >&2
    exit 1
  fi
  sleep 3
done
echo "ok   - Prometheus answers /-/ready (UID ${uid:-assigned by the cluster}, read-only root filesystem, no capabilities)"

restarts=$(kubectl -n "$NS" get pod prometheus -o jsonpath='{.status.containerStatuses[0].restartCount}')
[ "$restarts" = "0" ] || {
  echo "deploy: Prometheus restarted ($restarts)" >&2
  exit 1
}
echo "ok   - no restarts"
