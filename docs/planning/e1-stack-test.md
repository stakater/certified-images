# E.1 — images that only work together are run together

Story: `docs/roadmap.md` E.1 (👍 Approved 2026-11-28 by the owner, in
conversation: "add the e2e test to CI so this can't happen again"). Driver: a
defect in `etcd-wrapper` and `etcd-backup-restore` that every check on PR #34
passed.

## Why (one paragraph)

Each image's smoke test runs it next to upstream's builds of its peers, in a
pod the test itself writes. On 2026-11-28 all checks on PR #34 were green
while our three etcd images could not work together: etcd-druid runs its etcd
pods as UID 65532 with group 65532, and our two operand images made
`/home/nonroot` writable only for UID 1001, so the sidecar could not write the
etcd configuration and etcd crash-looped. The smoke pods hid it: they mounted a
volume over that directory and ran with group 0. It was found only by building
the three images locally and running them by hand. A first fix was itself
wrong (the directory's mode was not applied) and was again caught only by hand.
SCO deploys these three as a unit; nothing in CI did.

## Governing constraints

- ADR-007, CLAUDE.md "One step, one script": the test is a script in
  `scripts/` that runs the same locally and in CI; the workflow only calls it.
- CLAUDE.md "A check that cannot run must fail": a stack without an images
  list, with an unknown image, or without an executable `test.sh` fails.
- ADR-003: the images are built by `scripts/build-image.sh`, unchanged, so the
  stack runs what the pipeline builds, offline build included.
- CLAUDE.md "Do not weaken a check": the per-image smoke tests stay as strict
  as they are (arbitrary UID, read-only root filesystem). The stack test is an
  addition, not a replacement.
- CLAUDE.md testing rules: scripts run on bash 3.2 and bash 5.

## Prior art

`scripts/smoke-kind.sh` (story P.2b): a throwaway kind cluster, locally built
image loaded, a test run against it, cluster deleted. This is the same with
several images. No new external reference.

## Design

- `stacks/<name>/images`: one image name per line, `#` comments.
- `stacks/<name>/test.sh`: executable; deploys the images together and exits 0
  if they work. It gets `TEST_IMAGE_<NAME>` and `TEST_SOURCE_<NAME>` for every
  image (`<NAME>` in capitals, `-` as `_`), `TEST_ROOT` and `TEST_TIMEOUT`.
- `scripts/stack-test.sh stacks/<name>`: validates the directory, builds every
  listed image with `scripts/build-image.sh`, creates a kind cluster with the
  pinned node image, loads the images, runs `test.sh`, deletes the cluster.
  `STACK_SKIP_BUILD=1` reuses built images; `STACK_NO_CLUSTER=1` skips the
  cluster (for the unit tests).
- `Makefile`: `make stack STACK=<name>`; `stacks/*/test.sh` joins the shell lint.
- `.github/workflows/images.yaml`: a `stack` job per directory under `stacks/`,
  on the same pull-request trigger as the image jobs, plus `stacks/**`.
- `stacks/etcd`: etcd-druid, etcd-wrapper, etcd-backup-restore. Our etcd-druid
  creates an `Etcd` naming our two operand images; the test requires the Etcd
  ready, the pod running exactly our two images with no restarts, the sidecar
  reporting etcd healthy, and a key written with `etcdctl` read back (control:
  absent before). The etcd pod is the one etcd-druid generates, unchanged.
- NOT changing: `build-certify.yaml`, the per-image jobs, `publish.yaml`. A
  merge to `main` does not run the stack test again before publishing; it ran
  on the pull request.

## Checks (red first)

- The defect itself is the red case, seen by hand on 2026-11-28 with the same
  steps `stacks/etcd/test.sh` now runs: with the operand images as first
  pushed to PR #34, the Etcd did not become ready (`open
  /home/nonroot/etcd.conf.yaml: permission denied`, five restarts).
- `tests/run.sh`, unit level, no builds and no cluster: a passing test passes;
  the test receives every image, source, root and timeout; a failing test
  fails the stack and its message is shown; no images file, an unknown image,
  a single image, a line that is not a name, no `test.sh`, a non-executable
  `test.sh` each fail; every stack in the repository is well formed.
  ⚠️ These were written after the script, not before it.
- End to end: the `stack (stacks/etcd)` job on PR #34.

## Human steps and outward-facing actions

None. Merging the pull request publishes the images it touches; a person
authorises that.

## Out of scope

- Gating publication on the stack test (it would need the publish workflow to
  know which stacks an image belongs to). Follow-up if a stack ever breaks on
  `main`.
- Running a stack on OpenShift (P.2b level 2).
- Multi-member etcd, restore, TLS: the stack test shows the images work
  together, not everything etcd-druid can do with them.
- Stacks for other images. Crossplane with a provider is the next candidate,
  once a provider is built here.

## Done means

A stack is a directory under `stacks/`; `make stack STACK=etcd` passes locally
and the `stack (stacks/etcd)` job passes on the pull request; the unit checks
above are green in `make verify`; CLAUDE.md (testing table, layout) and the
README mention stacks.
