#!/usr/bin/env bash
# Deploy kcp for the smoke test (scripts/smoke-test.sh).
#
# kcp serves HTTPS only and keeps its state (an embedded etcd, its
# certificates, the admin kubeconfig) in a data directory, so it cannot use the
# generic smoke pod. This runs it as one pod named "kcp" under restricted pod
# security: non-root, a read-only root filesystem, no capabilities, and an
# emptyDir for the data directory.
#
# Passes when the pod is Ready, which means kcp answers /readyz over HTTPS, and
# has not restarted.
set -euo pipefail

NS=${TEST_NAMESPACE:?TEST_NAMESPACE must be set}
IMAGE=${TEST_IMAGE:?TEST_IMAGE must be set}
TIMEOUT=${TEST_TIMEOUT:-90}
uid=${TEST_RUN_AS_USER:-}

jq -n --arg image "$IMAGE" --arg uid "$uid" '{
  apiVersion: "v1", kind: "Pod",
  metadata: { name: "kcp", labels: { "app.kubernetes.io/name": "kcp" } },
  spec: {
    restartPolicy: "Never",
    automountServiceAccountToken: false,
    securityContext: ({ runAsNonRoot: true, runAsGroup: 0, fsGroup: 0, seccompProfile: { type: "RuntimeDefault" } }
      + (if $uid == "" then {} else { runAsUser: ($uid | tonumber) } end)),
    containers: [ {
      name: "kcp", image: $image, imagePullPolicy: "IfNotPresent",
      args: [ "start", "--root-directory=/data" ],
      ports: [ { containerPort: 6443 } ],
      securityContext: { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: ["ALL"] } },
      readinessProbe: { httpGet: { path: "/readyz", port: 6443, scheme: "HTTPS" }, periodSeconds: 3, failureThreshold: 100 },
      volumeMounts: [ { name: "data", mountPath: "/data" } ]
    } ],
    volumes: [ { name: "data", emptyDir: {} } ]
  }
}' | kubectl -n "$NS" apply -f - >/dev/null
echo "ok   - pod admitted under restricted pod security"

# Poll, so a container that exits is reported at once and not after the timeout.
deadline=$(($(date +%s) + TIMEOUT * 2))
while :; do
  ready=$(kubectl -n "$NS" get pod kcp -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  phase=$(kubectl -n "$NS" get pod kcp -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [ "$ready" = "True" ] && break
  case "$phase" in Failed | Succeeded)
    echo "deploy: kcp exited before becoming ready (phase $phase)" >&2
    exit 1
    ;;
  esac
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "deploy: kcp did not answer /readyz within $((TIMEOUT * 2))s" >&2
    exit 1
  fi
  sleep 3
done
echo "ok   - kcp answers /readyz over HTTPS (UID ${uid:-assigned by the cluster}, read-only root filesystem, no capabilities)"

restarts=$(kubectl -n "$NS" get pod kcp -o jsonpath='{.status.containerStatuses[0].restartCount}')
[ "$restarts" = "0" ] || {
  echo "deploy: kcp restarted ($restarts)" >&2
  exit 1
}
echo "ok   - no restarts"
