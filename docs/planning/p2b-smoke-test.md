# P.2b — an image is proven to run on a cluster before it is promoted

Story: `docs/roadmap.md` P.2b (👍 Approved 2026-11-26, **level 1 first**).
Driver: owner review. Nothing runs an image on a cluster; the start-up test
runs `--help` in a container engine and preflight is a static inspection.

## Why (one paragraph)

"Certified" must also mean "works". An image can pass every current check and
still fail the moment OpenShift starts it: it writes to a path it does not own
under an arbitrary UID, needs a capability, or never serves a request. Level 1
catches most of that on every pull request with no infrastructure, on a local
cluster that enforces Kubernetes' restricted pod security. Level 2 (a real
OpenShift cluster, gating promotion to Red Hat) reuses the same script and is
planned separately once a cluster and its credentials are named.

## Governing constraints

- **ADR-007:** one script per step, the same locally and in CI, nothing
  GitHub-specific. The smoke test takes "a cluster" as a kubeconfig, so level 2
  is the same script pointed at OpenShift.
- **CLAUDE.md invariant 8:** level 1 is an approximation and must say so. It
  is not evidence that an image works on OpenShift.
- **ADR-002 rule 6:** pull requests hold no credentials. Level 1 needs none.
- **ADR-004 / invariant 3:** the cluster node image is pinned in `tools.env`.

## Prior art

- Kubernetes Pod Security Standards, `restricted` profile, enforced by a
  namespace label. It is the closest portable equivalent of OpenShift's
  `restricted-v2` SCC (non-root, no privilege escalation, all capabilities
  dropped, RuntimeDefault seccomp).
- kind for a throwaway cluster in CI.
- No reference for the per-image smoke declaration; it is a few fields.

## What level 1 does and does not prove

| Proves | Does not prove |
|---|---|
| The image starts as a pod under restricted pod security | That OpenShift's SCC admission accepts it (level 2) |
| It runs as an arbitrary high UID in group 0, which is what OpenShift assigns | Behaviour with OpenShift's own UID range, SELinux, or FIPS mode |
| It runs with a read-only root filesystem | That it does its job for a product (story P.3) |
| It becomes Ready and answers an HTTP request, without restarting | Anything that needs real dependencies the test does not deploy |

## Design

`image.yaml` gains a required `smoke` block:

```yaml
smoke:
  port: 9003          # container port that serves HTTP
  path: /healthz      # must answer 2xx
  env: {}             # optional environment for the test
  args: []            # optional container arguments
```

Optional `images/<name>/smoke/*.yaml`: extra manifests applied to the test
namespace first (RBAC, a stub dependency).

Optional `images/<name>/smoke/deploy.sh` (added 2026-11-27 for Crossplane, which
needs an init step and two deployments): the image deploys itself and the
generic pod is skipped. `smoke.port` and `smoke.path` are then not required.
The script gets `TEST_NAMESPACE`, `TEST_IMAGE`, `TEST_TIMEOUT`,
`TEST_RUN_AS_USER` and `TEST_SOURCE` (the pinned upstream source left by the
build in `.ctx/<name>/src`); its exit status decides. The namespace still
enforces restricted pod security, so the script cannot relax it. An optional
`smoke/cleanup.sh` runs last. Crossplane's script needs `helm` on the machine,
like `kind` and `kubectl`; it is not pinned in `tools.env`.

| Path | What |
|---|---|
| `scripts/smoke-test.sh <image-ref> <images/name>` | against the current kubeconfig: create a namespace enforcing `restricted`, apply extras, run the pod, wait for Ready, request the path through the API server, require zero restarts, clean up. `--render` prints the pod manifest and exits |
| `scripts/smoke-kind.sh <image-ref> <images/name>` | level 1: create a throwaway kind cluster, load the image, run `smoke-test.sh`, delete the cluster |
| `Makefile` | `smoke` target |
| `.github/workflows/build-certify.yaml` | "Smoke test on a local cluster" after the image test, on every run |
| `scripts/check-image.sh` | rule 14: `smoke.port` is a port number and `smoke.path` starts with `/` |
| `tools.env` | `KIND_NODE_IMAGE`, pinned |

The pod: `runAsNonRoot`, `runAsUser: 1000680000` (a value from the kind of
range OpenShift assigns; on OpenShift the field is omitted and the cluster
assigns one), `runAsGroup: 0`, `seccompProfile: RuntimeDefault`,
`allowPrivilegeEscalation: false`, all capabilities dropped,
`readOnlyRootFilesystem: true`, a readiness probe on the declared port and
path, `automountServiceAccountToken: false` unless extras need it.

`kind` and `kubectl` come from the machine (GitHub's runner image ships both).
That is an exception to "every tool from a pinned image", recorded here: the
node image, which is what runs the workload, is pinned.

## Checks (red first)

In `tests/run.sh`, no cluster:

- **Rendered manifest**, one assertion per restricted setting above, plus the
  port, path, env and args from `image.yaml`.
- **check-image rule 14:** missing `smoke`, a non-numeric port and a path
  without a leading `/` each fail by rule number. The scaffold from
  `new-image.sh` fails it until filled in.

On a cluster (CI, and `make smoke` locally):

- OpenCost passes.
- **Negative test:** a fixture that tries to write to the root filesystem and
  one that never listens must both fail the smoke test. A smoke test that
  cannot fail is not a check.

## Human steps and outward-facing actions

None for level 1.

## Out of scope

- **Level 2**, a real OpenShift cluster gating promotion to Red Hat. It needs a
  named cluster, a service-account credential and a GHCR pull secret. Its own
  planning doc when those exist.
- Functional tests of what an image does for a product: story P.3.

## Done means (level 1)

Every image declares a smoke test; a pull request runs it on a local cluster
enforcing restricted pod security and fails if the pod is rejected, not Ready,
restarting or not answering; the negative fixtures fail it; README and
CLAUDE.md say what this proves and that it is not OpenShift. The story stays 🔨
until level 2 is done.
