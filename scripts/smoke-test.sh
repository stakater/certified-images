#!/usr/bin/env bash
# Run an image as a pod and check that it actually works:
#   scripts/smoke-test.sh <image-ref> images/<name>          # against the current kubeconfig
#   scripts/smoke-test.sh --render <image-ref> images/<name> # print the pod and exit
#
# images/<name>/smoke/*.yaml, if present, are applied to the test namespace
# first (RBAC, a stub dependency). __NAMESPACE__ in them is replaced with the
# namespace's name. They are deleted afterwards, cluster-scoped objects too.
#
# The pod runs the way OpenShift's restricted-v2 security context runs it:
# non-root, an arbitrary high UID in group 0, no privilege escalation, every
# capability dropped, the default seccomp profile, and a read-only root
# filesystem. The namespace enforces Kubernetes' "restricted" pod security, so
# the cluster rejects the pod if it asks for more.
#
# Passes only if the pod is admitted, becomes Ready, answers
# http://<pod>:<smoke.port><smoke.path> with success, and has not restarted.
# An image that cannot run as one bare pod ships images/<name>/smoke/deploy.sh
# and deploys itself into TEST_NAMESPACE with TEST_IMAGE (optionally
# smoke/cleanup.sh removes what it created outside the namespace).
# If the image ships images/<name>/functional/test.sh, that runs next and must
# exit 0: it tests what the image does, with TEST_NAMESPACE, TEST_POD,
# TEST_IMAGE and TEST_TIMEOUT set.
#
# The cluster is whatever kubectl points at: a local kind cluster for pull
# requests (scripts/smoke-kind.sh), an OpenShift cluster later. On kind this
# approximates OpenShift; it is not OpenShift.
#
# image.yaml's smoke block: port and path (required); env, args and files
# (optional). files maps an absolute path to its content, for an image that
# needs a config file to start.
#
# SMOKE_RUN_AS_USER  UID to run as (default 1000680000). Set it empty on
#                    OpenShift, where the cluster assigns the UID.
# SMOKE_TIMEOUT      seconds to wait for Ready (default 120)
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

RENDER=""
if [ "${1:-}" = "--render" ]; then
  RENDER=1
  shift
fi
REF=${1:?usage: smoke-test.sh [--render] <image-ref> images/<name>}
DIR=${2:?usage: smoke-test.sh [--render] <image-ref> images/<name>}
DIR=${DIR%/}
NAME=$(basename "$DIR")
RUN_AS_USER=${SMOKE_RUN_AS_USER-1000680000}
TIMEOUT=${SMOKE_TIMEOUT:-120}

JSON=$("$ENGINE" run --rm -i "$YQ_IMAGE" -o=json '.' <"$DIR/image.yaml") || {
  echo "smoke-test: could not read $DIR/image.yaml" >&2
  exit 1
}
# An image that cannot be tested as one bare pod (it needs an init step, or its
# own chart) ships smoke/deploy.sh and deploys itself. Otherwise the generic
# pod below is used, and needs a port and a path to ask.
DEPLOY="$DIR/smoke/deploy.sh"
custom=false
[ -e "$DEPLOY" ] && custom=true
PORT=$(printf '%s' "$JSON" | jq -r '.smoke.port // ""')
PATH_=$(printf '%s' "$JSON" | jq -r '.smoke.path // ""')
if [ "$custom" = false ]; then
  if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [[ "$PATH_" != /* ]]; then
    echo "smoke-test: $DIR/image.yaml needs smoke.port (a number) and smoke.path (starting with /), or $DIR/smoke/deploy.sh" >&2
    exit 1
  fi
fi
# Extra manifests (RBAC, a stub dependency) may need the API token.
automount=false
[ -d "$DIR/smoke" ] && automount=true

render() {
  printf '%s' "$JSON" | jq --arg ref "$REF" --arg name "$NAME" --arg uid "$RUN_AS_USER" \
    --argjson port "$PORT" --arg path "$PATH_" --argjson automount "$automount" '
    # smoke.files: {"/abs/path": "content"}. Each becomes a key in one ConfigMap,
    # mounted read-only at its path.
    ((.smoke.files // {}) | to_entries | to_entries | map({ key: "file-\(.key)", path: .value.key, content: .value.value })) as $files
    | [ (if ($files | length) > 0 then
        { apiVersion: "v1", kind: "ConfigMap", metadata: { name: "smoke-files" },
          data: ($files | map({ key: .key, value: .content }) | from_entries) }
      else empty end),
    {
      apiVersion: "v1",
      kind: "Pod",
      metadata: { name: "smoke", labels: { "app.kubernetes.io/name": $name, "stakater.com/smoke-test": "true" } },
      spec: ({
        restartPolicy: "Never",
        automountServiceAccountToken: $automount,
        securityContext: (
          { runAsNonRoot: true, runAsGroup: 0, seccompProfile: { type: "RuntimeDefault" } }
          + (if $uid == "" then {} else { runAsUser: ($uid | tonumber) } end)
        ),
        containers: [
          ({
            name: "app",
            image: $ref,
            imagePullPolicy: "IfNotPresent",
            args: (.smoke.args // []),
            env: ((.smoke.env // {}) | to_entries | map({ name: .key, value: (.value | tostring) })),
            ports: [ { containerPort: $port } ],
            securityContext: {
              allowPrivilegeEscalation: false,
              readOnlyRootFilesystem: true,
              capabilities: { drop: ["ALL"] }
            },
            readinessProbe: {
              httpGet: { path: $path, port: $port },
              periodSeconds: 2,
              failureThreshold: 60
            }
          } + (if ($files | length) > 0 then
                { volumeMounts: ($files | map({ name: "smoke-files", mountPath: .path, subPath: .key, readOnly: true })) }
              else {} end))
        ]
      } + (if ($files | length) > 0 then
            { volumes: [ { name: "smoke-files", configMap: { name: "smoke-files" } } ] }
          else {} end))
    } ]' | "$ENGINE" run --rm -i "$YQ_IMAGE" -P -o=yaml '.[] | split_doc'
}

if [ -n "$RENDER" ]; then
  if [ "$custom" = true ]; then
    echo "# $NAME deploys itself with $DEPLOY; there is no generic pod to render."
    exit 0
  fi
  render
  exit 0
fi

command -v kubectl >/dev/null || {
  echo "smoke-test: kubectl is required" >&2
  exit 1
}
NS="smoke-$NAME-$(date +%s)"
EXTRAS=$(mktemp -d)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# Where the image's pinned upstream source is, if the build left it there. A
# deploy script may use it, for example for upstream's own chart.
SOURCE=${SMOKE_SOURCE:-$ROOT/.ctx/$NAME/src}
test_env() { # runs a script of the image with what it may know
  TEST_NAMESPACE="$NS" TEST_IMAGE="$REF" TEST_TIMEOUT="${TEST_TIMEOUT:-90}" \
    TEST_RUN_AS_USER="$RUN_AS_USER" TEST_SOURCE="$SOURCE" "$@"
}
cleanup() {
  # What the image's own deploy script created outside the namespace.
  if [ -x "$DIR/smoke/cleanup.sh" ]; then
    test_env "$DIR/smoke/cleanup.sh" >/dev/null 2>&1 || true
  fi
  # Extras may hold cluster-scoped objects, which do not go with the namespace.
  if [ -n "$(ls -A "$EXTRAS" 2>/dev/null)" ]; then
    kubectl -n "$NS" delete -f "$EXTRAS/" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
  kubectl delete namespace "$NS" --wait=false >/dev/null 2>&1 || true
  rm -rf "$EXTRAS"
}
trap cleanup EXIT

fail() {
  echo "FAIL - $1" >&2
  {
    echo "--- pods"
    kubectl -n "$NS" get pods -o wide 2>&1 || true
    echo "--- events"
    kubectl -n "$NS" get events --sort-by=.lastTimestamp 2>&1 | tail -n 15 || true
    echo "--- logs"
    if [ "$custom" = true ]; then
      for pod in $(kubectl -n "$NS" get pods -o name 2>/dev/null); do
        echo "--- $pod"
        kubectl -n "$NS" logs "$pod" --all-containers --tail=25 2>&1 || true
      done
    else
      kubectl -n "$NS" logs smoke --tail=40 2>&1 || true
    fi
  } >&2
  exit 1
}

kubectl create namespace "$NS" >/dev/null
kubectl label namespace "$NS" --overwrite \
  pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=latest >/dev/null
echo "ok   - namespace $NS enforces restricted pod security"

shopt -s nullglob
extras=("$DIR"/smoke/*.yaml)
shopt -u nullglob
if [ "${#extras[@]}" -gt 0 ]; then
  # __NAMESPACE__ in an extra manifest is replaced with the test namespace.
  for f in "${extras[@]}"; do
    sed "s/__NAMESPACE__/$NS/g" "$f" >"$EXTRAS/$(basename "$f")"
  done
  kubectl -n "$NS" apply -f "$EXTRAS/" >/dev/null || fail "could not apply the extra manifests in $DIR/smoke/"
  # Wait for any dependency the extras deploy, so the image under test is not
  # failed for starting before it.
  if [ -n "$(kubectl -n "$NS" get deployments -o name 2>/dev/null)" ]; then
    kubectl -n "$NS" wait --for=condition=Available deployment --all --timeout="${TIMEOUT}s" >/dev/null 2>&1 ||
      fail "a dependency in $DIR/smoke/ did not become available within ${TIMEOUT}s"
  fi
  echo "ok   - extra manifests applied and their deployments are available"
fi

if [ "$custom" = true ]; then
  [ -x "$DEPLOY" ] || fail "$DEPLOY is not executable"
  echo "--- deploy: $DEPLOY"
  test_env "$DEPLOY" || fail "$DEPLOY failed: the image could not be deployed and brought up"
  echo "ok   - deployed and up, by its own deploy script"
else
  if ! out=$(render | kubectl -n "$NS" apply -f - 2>&1); then
    printf '%s\n' "$out" >&2
    fail "the cluster rejected the pod (pod security or admission)"
  fi
  echo "ok   - pod admitted under restricted pod security"

  # Poll, so a container that exits is reported at once and not after the timeout.
  deadline=$(($(date +%s) + TIMEOUT))
  while :; do
    ready=$(kubectl -n "$NS" get pod smoke -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    phase=$(kubectl -n "$NS" get pod smoke -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [ "$ready" = "True" ] && break
    case "$phase" in Failed | Succeeded) fail "the container exited before becoming Ready (phase $phase)" ;; esac
    [ "$(date +%s)" -lt "$deadline" ] || fail "the pod did not become Ready within ${TIMEOUT}s"
    sleep 2
  done
  echo "ok   - pod is Ready (UID ${RUN_AS_USER:-assigned by the cluster}, read-only root filesystem, no capabilities)"

  kubectl get --raw "/api/v1/namespaces/$NS/pods/smoke:$PORT/proxy$PATH_" >/dev/null 2>&1 ||
    fail "GET $PATH_ on port $PORT did not succeed"
  echo "ok   - GET $PATH_ on port $PORT succeeds"

  restarts=$(kubectl -n "$NS" get pod smoke -o jsonpath='{.status.containerStatuses[0].restartCount}')
  phase=$(kubectl -n "$NS" get pod smoke -o jsonpath='{.status.phase}')
  if [ "$restarts" != "0" ] || [ "$phase" != "Running" ]; then
    fail "the container did not stay up (phase $phase, restarts $restarts)"
  fi
  echo "ok   - still running, no restarts"
fi

# The image's own functional test, if it ships one: does it do its job, not
# just start? Same cluster, same namespace, same restrictions. Its exit status
# decides (docs/planning/f1-functional-tests.md).
if [ -d "$DIR/functional" ]; then
  ftest="$DIR/functional/test.sh"
  [ -x "$ftest" ] || fail "functional test $ftest is missing or not executable"
  echo "--- functional test: $ftest"
  test_pod=smoke
  [ "$custom" = false ] || test_pod=""
  if TEST_POD="$test_pod" test_env "$ftest"; then
    echo "ok   - functional test passed"
  else
    fail "functional test failed: the image starts but does not do its job"
  fi
  echo "smoke-test: $NAME works and does its job on this cluster under restricted pod security"
else
  echo "smoke-test: $NAME works on this cluster under restricted pod security"
fi
