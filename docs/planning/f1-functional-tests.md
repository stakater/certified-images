# F.1 — an image can ship a functional test

Story: `docs/roadmap.md` F.1 (👍 Approved 2026-11-26). Driver: the smoke test
shows an image starts and reports ready. It does not show the image does its
job. Reloader passing "ready" says nothing about whether it reloads anything.

## Why (one paragraph)

A controller that starts but does not act is as broken as one that crashes, and
only a test of its behaviour finds that. The test has to be composable: written
once, per image, and run unchanged wherever the pipeline has a cluster, which
today is the throwaway local cluster on pull requests and will be the OpenShift
runner. That is also what makes the OpenShift run worth having: it will prove
behaviour on OpenShift, not just start-up.

## Governing constraints

- **ADR-007:** one script per step, the same locally and in CI. The test takes
  "a cluster" as the current kubeconfig and "where" as a namespace.
- **CLAUDE.md, "Do not weaken a check":** the functional test runs under the
  same restricted settings as the smoke test, in the same namespace.
- **Method invariant 1:** a check must be shown to fail.
- **ADR-004 / invariant 3:** any image a test deploys is pinned by digest.

## Prior art

- Reloader's own end-to-end tests: change a ConfigMap, assert the workload was
  rolled. This is that, reduced to one case.
- The contract (an executable given a namespace, exit code decides) is the
  shape of a Helm test hook and of `kuttl`/`chainsaw` steps, without adopting
  either tool. Risk of not adopting one: we maintain a tiny convention
  ourselves. Accepted while tests are a handful of `kubectl` calls.

## Design

**The contract.** If `images/<name>/functional/test.sh` exists and is
executable, `scripts/smoke-test.sh` runs it after the smoke checks pass, while
the image is still running. It gets:

| Variable | Meaning |
|---|---|
| `KUBECONFIG` / current context | the cluster |
| `TEST_NAMESPACE` | the throwaway namespace the image runs in. It enforces restricted pod security |
| `TEST_POD` | the pod running the image under test (`smoke`) |
| `TEST_IMAGE` | the image reference under test |
| `TEST_TIMEOUT` | seconds the test may wait for an effect (default 90) |

Exit 0 means the image does its job. Anything else fails the smoke test, and
the pod's log is printed. The test creates what it needs inside
`TEST_NAMESPACE`, which is deleted afterwards. It must not need anything
outside that namespace beyond what `smoke/*.yaml` already granted.

`functional/` may hold other files the script uses (manifests).

**Reloader's test** (`images/reloader-operator/functional/test.sh`):

1. Create a ConfigMap and a Deployment that reads it, annotated
   `reloader.stakater.com/auto: "true"`. The workload is a pinned `pause` image
   under the same restricted settings.
2. Wait for the Deployment to roll out. Record its generation.
3. Change the ConfigMap.
4. Pass if the Deployment's generation goes up and it rolls out again within
   the timeout. Fail otherwise.
5. Control: change a ConfigMap the Deployment does not use, and require that
   nothing rolls. A Reloader that restarts everything is also broken.

| Path | Change |
|---|---|
| `scripts/smoke-test.sh` | run `functional/test.sh` after the smoke checks |
| `scripts/check-image.sh` | rule 17: if `functional/` exists, `test.sh` exists and is executable |
| `Makefile` | shellcheck also covers `images/*/functional/*.sh` |
| `images/reloader-operator/functional/` | the test above |

## Checks (red first)

In `tests/run.sh`, with a stub `kubectl` so no cluster is needed:

- no `functional/` directory: the smoke test passes as before;
- a functional test that exits 0: the smoke test passes and says it ran;
- one that exits non-zero: the smoke test **fails**, naming the functional test;
- the test receives `TEST_NAMESPACE`, `TEST_POD`, `TEST_IMAGE`;
- check-image rule 17: a `functional/` without `test.sh`, or with a
  non-executable one, fails.

On a cluster: Reloader's test passes in CI. **Shown to fail once, by hand:**
run it in a namespace where Reloader is not running; it must time out and fail.
The result is recorded in the PR.

## Human steps and outward-facing actions

None.

## Out of scope

- Running on OpenShift: needs the runner (P.2b level 2). The contract is built
  so that needs no change to any test.
- A functional test for OpenCost: it needs real metrics to produce cost data.
  Left for story P.3, where MTO supplies them.
- Adopting a test framework.

## Done means

An image may ship `functional/test.sh`; the pipeline runs it on every pull
request after the smoke test and fails if it fails; Reloader has one that
proves a ConfigMap change rolls the workload and an unrelated change does not;
it has been shown to fail without Reloader; README, CLAUDE.md and the
add-image skill describe the contract.
