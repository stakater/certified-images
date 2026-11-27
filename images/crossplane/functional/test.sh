#!/usr/bin/env bash
# Functional test for Crossplane (docs/planning/f1-functional-tests.md).
# Run by scripts/smoke-test.sh once smoke/deploy.sh has Crossplane up.
#
# Proves Crossplane does its job, end to end:
#   - its package manager installs a provider (pulls the package, installs its
#     CRDs, starts its controller);
#   - a resource of that provider is reconciled and becomes Ready.
# Control: the provider's resource type does not exist before the install, so
# a pass cannot come from something left behind.
#
# The provider is provider-nop, upstream's test provider, pinned by digest. It
# needs the network to pull. Its pod runs under the same restricted settings,
# supplied through a DeploymentRuntimeConfig: Crossplane's default for provider
# pods does not satisfy restricted pod security or OpenShift's restricted SCC.
set -euo pipefail

NS=${TEST_NAMESPACE:?TEST_NAMESPACE must be set}
TIMEOUT=${TEST_TIMEOUT:-90}
PACKAGE=xpkg.crossplane.io/crossplane-contrib/provider-nop:v0.6.0@sha256:714fb0496f607c6b38c0bafad7e49dddd5c604c08f5883d61985f89b4b0923c2
CRD=nopresources.nop.crossplane.io

if kubectl get crd "$CRD" >/dev/null 2>&1; then
  echo "FAIL - $CRD already exists before the provider is installed; this cluster is not clean" >&2
  exit 1
fi
echo "ok   - control: the provider's resource type does not exist yet"

kubectl apply -f - >/dev/null <<YAML
apiVersion: pkg.crossplane.io/v1beta1
kind: DeploymentRuntimeConfig
metadata:
  name: smoke-restricted
spec:
  deploymentTemplate:
    spec:
      selector: {}
      template:
        spec:
          securityContext:
            runAsNonRoot: true
            seccompProfile:
              type: RuntimeDefault
          containers:
            - name: package-runtime
              securityContext:
                runAsNonRoot: true
                allowPrivilegeEscalation: false
                capabilities:
                  drop: ["ALL"]
                seccompProfile:
                  type: RuntimeDefault
---
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: smoke-provider-nop
spec:
  package: $PACKAGE
  runtimeConfigRef:
    name: smoke-restricted
YAML

if ! kubectl wait provider.pkg.crossplane.io/smoke-provider-nop --for=condition=Healthy --timeout="$((TIMEOUT * 2))s" >/dev/null 2>&1; then
  echo "FAIL - Crossplane did not bring the provider to Healthy within $((TIMEOUT * 2))s" >&2
  kubectl get provider.pkg.crossplane.io smoke-provider-nop -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}' >&2 || true
  exit 1
fi
echo "ok   - Crossplane installed a provider: package pulled, CRDs installed, controller running"

kubectl -n "$NS" apply -f - >/dev/null <<YAML
apiVersion: nop.crossplane.io/v1alpha1
kind: NopResource
metadata:
  name: smoke
spec:
  forProvider:
    conditionAfter:
      - time: 1s
        conditionType: Ready
        conditionStatus: "True"
YAML

if ! kubectl -n "$NS" wait nopresource.nop.crossplane.io/smoke --for=condition=Ready --timeout="${TIMEOUT}s" >/dev/null 2>&1; then
  echo "FAIL - the provider's resource did not become Ready within ${TIMEOUT}s" >&2
  kubectl -n "$NS" get nopresource.nop.crossplane.io/smoke -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}' >&2 || true
  exit 1
fi
echo "ok   - a resource of that provider was reconciled and is Ready"
kubectl -n "$NS" delete nopresource.nop.crossplane.io/smoke --wait=false >/dev/null 2>&1 || true
