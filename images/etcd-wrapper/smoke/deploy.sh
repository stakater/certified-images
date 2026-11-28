#!/usr/bin/env bash
# Deploy etcd-wrapper for the smoke test (scripts/smoke-test.sh).
#
# This image is the etcd container of an etcd pod and does nothing alone: the
# etcd container asks the sidecar whether the data directory is valid and for
# its configuration before it starts etcd. So this runs a one-member etcd pod
# shaped like the one etcd-druid v0.39.2 creates, with the image under test as
# the etcd container and upstream's etcd-backup-restore image, pinned by digest, as
# the backup-restore sidecar. Pulling that image needs the network.
#
# Stricter than etcd-druid's own pod: restricted pod security, an arbitrary
# UID, a read-only root filesystem, and emptyDirs for the data and for HOME
# (the sidecar writes the etcd configuration into HOME). No Kubernetes API
# access: member lease renewal is switched off.
#
# Passes when both containers are ready and neither has restarted.
set -euo pipefail

NS=${TEST_NAMESPACE:?TEST_NAMESPACE must be set}
IMAGE=${TEST_IMAGE:?TEST_IMAGE must be set}
TIMEOUT=${TEST_TIMEOUT:-90}
uid=${TEST_RUN_AS_USER:-}
PEER=europe-docker.pkg.dev/gardener-project/public/gardener/etcdbrctl:v0.45.3@sha256:e33dd5c575a244819ff74a6bafdcd6022214b06833aab0eeb6e170978f00c82e
NAME=etcd-smoke

kubectl -n "$NS" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Service
metadata:
  name: $NAME-peer
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  selector:
    app.kubernetes.io/name: $NAME
  ports:
    - name: peer
      port: 2380
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: $NAME-config
data:
  etcd.conf.yaml: |
    name: etcd-config
    data-dir: /var/etcd/data/new.etcd
    metrics: basic
    snapshot-count: 10000
    # On, unlike etcd-druid's default, so the functional test can write and
    # read a key over HTTP with kubectl alone.
    enable-grpc-gateway: true
    quota-backend-bytes: 1073741824
    listen-client-urls: http://0.0.0.0:2379
    listen-peer-urls: http://0.0.0.0:2380
    advertise-client-urls:
      $NAME-0:
      - http://$NAME-0.$NAME-peer.$NS.svc:2379
    initial-advertise-peer-urls:
      $NAME-0:
      - http://$NAME-0.$NAME-peer.$NS.svc:2380
    initial-cluster: $NAME-0=http://$NAME-0.$NAME-peer.$NS.svc:2380
    initial-cluster-state: new
    initial-cluster-token: etcd-cluster
    auto-compaction-mode: periodic
    auto-compaction-retention: 15m
YAML

jq -n --arg name "$NAME" --arg etcd "$IMAGE" --arg br "$PEER" --arg uid "$uid" '
  { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: ["ALL"] } } as $sc |
  { apiVersion: "v1", kind: "Pod",
    metadata: { name: ($name + "-0"), labels: { "app.kubernetes.io/name": $name } },
    spec: {
      restartPolicy: "Never", automountServiceAccountToken: false,
      hostname: ($name + "-0"), subdomain: ($name + "-peer"),
      hostAliases: [ { ip: "127.0.0.1", hostnames: [ ($name + "-local") ] } ],
      securityContext: ({ runAsNonRoot: true, runAsGroup: 0, fsGroup: 0, seccompProfile: { type: "RuntimeDefault" } }
        + (if $uid == "" then {} else { runAsUser: ($uid | tonumber) } end)),
      containers: [
        { name: "etcd", image: $etcd, imagePullPolicy: "IfNotPresent",
          args: [ "start-etcd", ("--backup-restore-host-port=" + $name + "-local:8080"),
                  ("--etcd-server-name=" + $name + "-local"), "--backup-restore-tls-enabled=false",
                  "--etcd-client-port=2379", "--etcd-wrapper-port=9095" ],
          env: [ { name: "HOME", value: "/home/nonroot" } ],
          ports: [ { containerPort: 2379 }, { containerPort: 2380 }, { containerPort: 9095 } ],
          readinessProbe: { httpGet: { path: "/readyz", port: 9095 }, periodSeconds: 3, failureThreshold: 100 },
          securityContext: $sc,
          volumeMounts: [ { name: "data", mountPath: "/var/etcd/data" }, { name: "etcd-home", mountPath: "/home/nonroot" } ] },
        { name: "backup-restore", image: $br, imagePullPolicy: "IfNotPresent",
          args: [ "server", "--server-port=8080", "--insecure-transport=true", "--insecure-skip-tls-verify=true",
                  ("--endpoints=http://" + $name + "-local:2379"), ("--service-endpoints=http://" + $name + "-local:2379"),
                  "--data-dir=/var/etcd/data/new.etcd", "--restoration-temp-snapshots-dir=/var/etcd/data/restoration.temp",
                  "--snapstore-temp-directory=/var/etcd/data/temp", "--etcd-connection-timeout=5m",
                  "--use-etcd-wrapper=true", "--enable-member-lease-renewal=false",
                  "--storage-provider=Local", "--store-container=backups", "--store-prefix=etcd-smoke",
                  "--delta-snapshot-period=10s", "--embedded-etcd-quota-bytes=1073741824" ],
          env: [ { name: "HOME", value: "/home/nonroot" },
                 { name: "POD_NAME", valueFrom: { fieldRef: { fieldPath: "metadata.name" } } },
                 { name: "POD_NAMESPACE", valueFrom: { fieldRef: { fieldPath: "metadata.namespace" } } } ],
          ports: [ { containerPort: 8080 } ],
          readinessProbe: { httpGet: { path: "/healthz", port: 8080 }, periodSeconds: 3, failureThreshold: 100 },
          securityContext: $sc,
          volumeMounts: [ { name: "data", mountPath: "/var/etcd/data" }, { name: "config", mountPath: "/var/etcd/config/" },
                          { name: "br-home", mountPath: "/home/nonroot" } ] }
      ],
      volumes: [ { name: "data", emptyDir: {} }, { name: "etcd-home", emptyDir: {} }, { name: "br-home", emptyDir: {} },
                 { name: "config", configMap: { name: ($name + "-config") } } ]
    } }' | kubectl -n "$NS" apply -f - >/dev/null
echo "ok   - pod admitted under restricted pod security"

# Poll, so a container that exits is reported at once and not after the timeout.
deadline=$(($(date +%s) + TIMEOUT * 2))
while :; do
  ready=$(kubectl -n "$NS" get pod "$NAME-0" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  phase=$(kubectl -n "$NS" get pod "$NAME-0" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [ "$ready" = "True" ] && break
  case "$phase" in Failed | Succeeded)
    echo "deploy: a container exited before the pod became ready (phase $phase)" >&2
    exit 1
    ;;
  esac
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "deploy: the etcd pod did not become ready within $((TIMEOUT * 2))s" >&2
    exit 1
  fi
  sleep 3
done
for c in etcd backup-restore; do
  image=$(kubectl -n "$NS" get pod "$NAME-0" -o jsonpath="{.spec.containers[?(@.name==\"$c\")].image}")
  echo "ok   - container $c is ready ($image)"
done
echo "ok   - etcd is up (UID ${uid:-assigned by the cluster}, read-only root filesystem, no capabilities)"

restarts=$(kubectl -n "$NS" get pod "$NAME-0" -o jsonpath='{.status.containerStatuses[*].restartCount}')
[ "$restarts" = "0 0" ] || {
  echo "deploy: a container restarted ($restarts)" >&2
  exit 1
}
echo "ok   - no restarts"
