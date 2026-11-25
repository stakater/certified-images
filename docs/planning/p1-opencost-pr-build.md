# P.1 — a pull request builds OpenCost hermetically

Story: `docs/roadmap.md` P.1 (👍 Approved 2026-11-25). Driver: ADR-002 pilot;
the design in ADR-003, ADR-004 and ADR-008 has never been run.

## Why (one paragraph)

Every claim this factory makes rests on a pipeline that does not exist. Until
one image goes through pinned clone → prefetch → offline build → SBOM → CVE gate
→ preflight, we do not know whether Hermeto handles OpenCost's Go modules,
whether the image starts, or whether it would pass certification. P.1 proves
the build half on pull requests, with no credentials and nothing published, so
that P.2 (certify and publish) only adds the outward-facing steps.

## Governing constraints

- **ADR-003:** fetch the pinned commit and fail if the tag points elsewhere;
  apply `patches/*.patch` (dependency files only) before the prefetch; Hermeto
  typed fetchers; build with `--network=none`.
- **ADR-004:** runtime base and toolchain image pinned by `tag@digest`, both
  managed by Renovate; Containerfile `ARG` defaults are the source of truth.
- **ADR-006:** the pipeline is a reusable workflow (`on: workflow_call`) from
  this first version; this repo is its first caller.
- **ADR-007:** nothing GitHub-specific in `image.yaml` or Containerfiles. The
  steps live in scripts that run the same locally and in CI.
- **ADR-008 §1, §4, §6:** Hermeto SBOM + syft SBOM; trivy gate on fixable
  CRITICAL and HIGH; OpenVEX exceptions with the two lifetimes.
- **ADR-002 rule 8:** `linux/amd64` only.
- **CLAUDE.md boundaries:** no secrets, no push to Red Hat's registry, no
  signing in this story. A PR from a fork must be able to run all of it.

## Prior art

- Hermeto's documented flow: `fetch-deps` → `generate-env` → `inject-files` →
  build with the network off (docs/references.md §4).
- GitHub's reusable-workflow pattern (docs/references.md §3, added row).
- Red Hat `preflight check container` (docs/references.md §7).
- No reference for the image start-up test; it is our own, kept to a few lines.

## Design

Each step is a script, so `make build IMAGE=opencost` on a laptop runs exactly
what CI runs.

| Path | What |
|---|---|
| `scripts/fetch-source.sh <images/name> <out>` | fetch `upstream.commit` only; fail unless `upstream.version` dereferences to it; apply `patches/*.patch`; fail if a patch touches anything but dependency manifests and lockfiles |
| `scripts/prefetch.sh <images/name> <ctx>` | Hermeto `fetch-deps` with `build.prefetch`, then `generate-env` and `inject-files` |
| `scripts/build-image.sh <images/name>` | calls the two above, then builds with `--network=none --platform linux/amd64`; prints the local image reference |
| `scripts/test-image.sh <ref> <images/name>` | required labels equal `image.yaml`; `/licenses` is not empty; the user is not root; the container starts and exits 0 for the command in the new `image.yaml` field `test.command` |
| `scripts/check-vex.sh <images/name>` | no VEX file passes; an expired temporary statement fails; a `not_affected` statement for another upstream version fails |
| `scripts/scan-image.sh <ref> <images/name>` | syft SBOM (SPDX JSON); trivy with `--ignore-unfixed --severity CRITICAL,HIGH` and the VEX file |
| `.github/workflows/build-certify.yaml` | reusable workflow; inputs `image-dir`, `publish` (default `false`; `true` is rejected until P.2). Jobs: verify → build → test → scan → preflight dry run |
| `.github/workflows/images.yaml` | caller: on pull requests touching `images/**`, `scripts/**` or the workflow, one run per image directory |
| `.github/CODEOWNERS` | `images/**` and `.github/**` owned by the factory team. **Not written**: it needs a GitHub handle (human step below) |
| `scripts/preflight-dry-run.sh`, `scripts/test-hermetic.sh` | added during the story: preflight needs a registry, and the network-isolation proof needs a control build |
| `Makefile` | `build`, `test-image`, `scan`; tool images (Hermeto, syft, trivy, preflight) pinned by digest next to the linters |

Changes to existing files:

- `images/opencost/Containerfile`: `BASE_TAG=latest@sha256:…`; the Go image
  becomes an `ARG` holding `tag@digest` with a `# renovate:` comment.
- `images/opencost/image.yaml`: add `test.command` (e.g. the binary's version
  or help flag; check what OpenCost supports).
- `renovate.json`: a regex manager for the toolchain `ARG`; a package rule that
  keeps toolchain bumps out of automerge.
- `scripts/check-image.sh`: rule 10, base and toolchain images are pinned by
  digest; rule 11, `test.command` is set.
- `scripts/new-image.sh`: scaffold the new field.

Not changing: the ADRs; anything that pushes, signs or submits (P.2).

**`ubi-micro` trial.** Build once with `BASE_IMAGE=ubi9/ubi-micro`, run
`test-image.sh`, and check outbound TLS to a cloud pricing endpoint. Record the
result in ADR-004 (resolving its ⚠️) and keep whichever base passes.

## Checks (red first)

Added to `tests/run.sh` before each script exists. All run without network,
using a throwaway local git repository as the "upstream".

- **fetch-source:** correct tag and commit succeeds; a tag moved to another
  commit fails; an unknown commit fails; a dependency-only patch applies; a
  patch touching a `.go` file fails.
- **check-vex:** the three cases in the table above, plus a valid file passing.
- **check-image rules 10 and 11:** the good fixture passes; an unpinned base,
  an unpinned toolchain and a missing `test.command` each fail by rule number.
- **Renovate regex:** the toolchain manager's regex matches the Containerfile
  line (asserted with the same pattern in a test).

Checks that need a container build, run by `make build` and in CI, not in
`tests/run.sh`:

- **Hermetic negative test:** a fixture Containerfile whose build stage makes a
  network call must fail under `build-image.sh`.
- **OpenCost end to end:** build, `test-image.sh`, scan, preflight dry run.

## Human steps and outward-facing actions

- **CODEOWNERS needs a GitHub team or user handle** for the factory team. The
  ADR names an interim owner but not a handle.
- **Branch protection on `main`** (require the `verify` and image checks,
  require CODEOWNERS review, allow the Renovate bot for digest bumps) is set in
  GitHub settings by a repository admin.
- Enable the Renovate app on the repository and read its first Dependency
  Dashboard: it confirms the two regex managers work (ADR-004 ⚠️).

## Out of scope

- Push, cosign, attestations, `preflight --submit`, Partner Connect: P.2.
- `<version>-<release>` tagging and the daily re-scan: backlog stories.
- **Scope change during the story:** the `deviations` field was planned as a
  backlog story. The CVE gate's first run found four fixable HIGH
  vulnerabilities that upstream has not fixed, so the first patch and the
  `deviations` field (with `check-image.sh` rule 12) were pulled into P.1.
  Without them the PR run could not go green honestly.
- arm64.

## Known unknowns to resolve inside this story

From the README's unverified list. Each is settled by running it, and the
README entry is then removed or rewritten as a fact.

1. Hermeto `gomod` with upstream's Go version and its local `replace` modules.
2. The Hermeto SBOM file name.
3. The preflight flag name on the pinned version, and whether a dry run can
   read a locally built image or needs a local registry in the job.
4. Whether the pinned trivy honours the VEX file as configured.
5. Whether `ubi-minimal` (or `ubi-micro`) carries the CA bundle OpenCost needs.

If 1 fails, stop and report: it means the first pilot image cannot be built
hermetically as designed, which is an ADR-003 question, not a workaround.

## Done means

The roadmap Done line: the reusable workflow exists with this repo as its first
caller; base and toolchain images are digest-pinned and Renovate manages both;
the `ubi-micro` result is recorded; a PR run is green for `images/opencost`
including the start-up test; the run fails on a moved tag and on a build that
reaches the network; the README's unverified list is resolved item by item.
Also: `make verify` green; `CLAUDE.md` status, the method.md enforcement table
and the README pipeline section describe what now exists; roadmap marks P.1 ✅.
