# certified-images — agent & contributor guide

The Stakater **image factory**: rebuilds admitted upstream OSS **from source** on
Red Hat UBI, certifies it in Red Hat Partner Connect, and publishes it with SBOM,
signature and provenance. Consumers are Stakater products (MTO first, then SCO and
Reloader Enterprise) that must install in **air-gapped** OpenShift clusters and
pass Red Hat's rule that every operand is a certified image.

This is a build-and-release repo, not a service: the "code" is Containerfiles,
`image.yaml` manifests, CI workflows, Renovate config and shell scripts.

## Status — be honest about it

**Nothing has been built yet.** As of 2026-11-25:

- `images/opencost/` (Containerfile + `image.yaml`), `renovate.json` and
  `scripts/new-image.sh` exist but have never run.
- `.github/workflows/build-certify.yaml` and `.github/CODEOWNERS` are described in
  the README and ADRs but **do not exist in the repo**.
- There is no `make verify`, no linter config and no tests.
- The ADRs were reviewed and revised on 2026-11-25 (story DX.1). They are
  accepted when the first PR merges (ADR-001). ADR-005 and ADR-006 stay
  Proposed. Treat every ⚠️ in `docs/` as unverified.
- The Containerfile does not yet meet ADR-004: neither the UBI base nor the
  toolchain image is digest-pinned.

Update this section when it stops being true.

## Read first

1. `docs/vision.md` — who this is for and the value proposition.
2. `docs/method.md` — how we work: story → plan → red → green → verify → audit.
3. `docs/roadmap.md` — the stories and their lifecycle state.
4. `docs/adr/` — the decisions. ADR-001 is how we record them; ADR-002 is the
   umbrella; 003–008 are its parts.
5. `docs/references.md` — the prior art each decision copies.

## Workflow (the short form of `docs/method.md`)

- **No story built without approval.** Stories live in `docs/roadmap.md` and move
  📝 Draft → 👍 Approved → 🔨 In progress → ✅ Done. An agent may write or
  re-scope a Draft; only a human approves one.
- **Plan before implementing.** Each approved story gets a planning doc in
  `docs/planning/`, copied from `docs/planning/TEMPLATE.md` and committed before
  the implementation. It must be executable by a cold session with no chat history.
- **Red before green.** Write the failing check first (see *Testing*), then the
  change that makes it pass.
- **Challenge the story.** If it solves the wrong problem, or a simpler path
  exists, say so before building. Killing a weak Draft is a success.
- **One story at a time**, end to end, with something demo-able at the end.

## Invariants — stop and flag before breaking one

These come from the ADRs. The ADR wins if this list and an ADR disagree.

1. **Build from source at a pinned commit.** Never re-tag or re-layer upstream
   binaries. `image.yaml` carries both the tag and the commit it must point to
   (ADR-002 rule 2, ADR-003). The only allowed deviations from upstream are a
   toolchain patch bump or a dependency bump that fixes a vulnerability in the
   patch SLA, recorded in `image.yaml` and offered upstream.
2. **No network inside the build.** Dependencies are prefetched with Hermeto
   using typed fetchers, then the build runs with `--network=none` (ADR-003).
3. **Runtime base is UBI, pinned by digest.** The Containerfile `ARG` defaults
   are the single source of truth for the base (ADR-004).
4. **Consumers reference artifacts by digest only**, never by tag (ADR-002).
5. **Admission is deliberate.** Every admitted image is a permanent patching
   commitment; all four admission conditions must hold (ADR-002 rule 1).
6. **No invention.** A new pattern needs a reference in `docs/references.md`, or
   an ADR that names the missing reference as a risk (ADR-002 rule 7).
7. **CVE exceptions are OpenVEX statements**, never scanner ignore files.
   Temporary ones expire within 30 days; `not_affected` ones are re-validated
   on every upstream bump (ADR-008).
8. **Claims match evidence.** Do not claim SLSA L3, FIPS, "certified" or
   "verified" for anything the pipeline has not actually produced (ADR-007,
   ADR-008).

## Boundaries

- **Merging to `main` publishes.** It pushes to Red Hat's registry and submits
  for certification. Never merge, push to `main`, or trigger a publish without
  explicit authorization. Work on a feature branch and open a PR.
- **Secrets by reference only.** Partner Connect and registry credentials are
  GitHub secrets named in `image.yaml` (`redhat.secretSuffix`). Never read, echo
  or inline their values.
- **Partner Connect and export questionnaires are human steps.** Do not attempt
  them; record what is needed in the story.

## Testing — what "red → green" means here

There is no application code, so tests are checks on the factory's inputs and
outputs. Target pyramid (none of it exists yet; story DX.2 builds it):

| Level | Checks | Tools |
|---|---|---|
| Static | Containerfile lint, shell lint, `image.yaml` schema, Renovate config, workflow lint | hadolint, shellcheck, a JSON Schema, `renovate-config-validator`, actionlint |
| Unit | Scripts and CI helper logic (tag-to-commit check, VEX expiry check) against fixtures | bats or plain shell tests |
| Image | The built image has the required labels, `/licenses`, non-root user, and starts | container-structure-test or equivalent, preflight dry run |
| End to end | A PR run goes prefetch → offline build → SBOM → CVE gate → preflight | the CI workflow itself |

Until `make verify` exists, say plainly which checks were run by hand and which
were not run.

## Conventions

- **ADRs never rewrite history (ADR-001).** To change a decision, either
  **revise** it (copy the old version to `docs/adr/archive/<name>.vN.md` and
  bump the revision in the header) or **supersede** it (set the old ADR's status
  to `Superseded by ADR-NNN`). ADRs are accepted by PR review before the
  implementing change merges.
- **Mark unverified facts with ⚠️** and say what would verify them. Remove the
  mark only after checking, and record the date.
- **Commits:** one logical change; the message says what and why and cites the
  story or ADR. Feature branch, never `main`.
- **Docs move with the change.** A change that leaves the README, an ADR
  reference or this file stale is unfinished.

## Layout

```
images/<name>/image.yaml       one manifest per artifact (kind, upstream tag + commit, prefetch, Red Hat component)
images/<name>/Containerfile    hermetic build stage + parameterised UBI runtime stage
images/<name>/vex.openvex.json optional CVE exceptions
images/<name>/patches/*.patch  optional dependency-only patches (ADR-003 §6)
scripts/new-image.sh           scaffolds a new image from the OpenCost one
renovate.json                  bumps upstream tag + commit and the UBI base digest
docs/vision.md, method.md, roadmap.md, planning/, adr/, references.md
```
