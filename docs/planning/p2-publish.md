# P.2 — an image is certified and published

Story: `docs/roadmap.md` P.2 (👍 Approved 2026-11-25). Driver: ADR-002 pilot.
P.1 proved the build; nothing leaves the runner yet.

## Why (one paragraph)

A product can only reference an image that exists in a registry and is
certified. P.2 adds the outward-facing half of the pipeline: push to Red Hat's
registry, sign, attach the evidence, and submit for certification. It is also
where two open questions get answered with a real image: whether a customer can
verify our signature from the public pull spec, and what provenance level we
can honestly claim.

## Governing constraints

- **ADR-002 rule 3:** tags are `<upstream-version>-<release>`; release goes up
  by one on every rebuild of the same upstream version, starting at 1.
- **ADR-002 rule 6:** a merge to `main` publishes. Only the publish path may
  hold credentials; pull requests must keep working with none.
- **ADR-006:** one reusable workflow. The signing identity is that workflow.
- **ADR-007:** claim only the provenance level we have checked.
- **ADR-008 §1–3:** two SBOM attestations, a keyless signature on the digest,
  build provenance. §7: verification commands documented after they have run.
- **CLAUDE.md boundaries:** secrets by reference only; Partner Connect and
  adding secrets are human steps; an agent never triggers a publish.

## Prior art

- Red Hat's partner flow: push to `quay.io/redhat-isv-containers/<componentId>`,
  then `preflight check container --submit` (docs/references.md §7).
- Chainguard: sign the digest and attach SBOM and provenance attestations with
  Sigstore (docs/references.md §5).
- GitHub: `actions/attest-build-provenance` inside a reusable workflow
  (docs/references.md §3).
- No reference for the release counter. It is a few lines; the RPM release
  convention is the model.

## Design

Publishing is the same job as the PR build, with extra steps that run only
when `publish` is true. One job means the image that was tested is the image
that is pushed.

Order of steps when publishing:

1. **Plan** (`scripts/publish-plan.sh`): is this image publishable? It is not
   if `redhat.componentId` is still the placeholder. Then the job builds and
   checks as on a PR, says so in the run summary, and publishes nothing. This
   is a normal state for an image waiting on Partner Connect, so the run is
   green, with a visible notice.
2. **Log in** to `quay.io` with the image's registry secrets.
3. **Release number**: list the repository's tags, pass them to
   `scripts/next-release.sh`.
4. **Build** with `RELEASE=<n>`, then **test**, **scan**, **preflight dry run**
   as in P.1. `test-image.sh` checks the `release` label equals `<n>`.
5. **Push** `<repository>:<version>-<n>` (`scripts/push-image.sh`), which prints
   the pushed digest. Everything after this uses the digest.
6. **Sign** the digest with cosign, keyless.
7. **Attest** the two SBOMs with cosign, and the build provenance with
   `actions/attest-build-provenance`.
8. **Submit** to Red Hat (`scripts/preflight-submit.sh`).

| Path | What |
|---|---|
| `scripts/publish-plan.sh <images/name>` | prints `publishable`, `reason`, `component_id`, `suffix`, `version`, `repository` as `key=value` |
| `scripts/next-release.sh <version>` | reads tags on stdin, prints the next release number |
| `scripts/list-tags.sh <repository>` | tags of a repository, via a pinned skopeo image |
| `scripts/push-image.sh <local-ref> <repository> <tag>` | pushes, prints `<repository>@sha256:…` |
| `scripts/preflight-submit.sh <ref> <component-id>` | `preflight check container --submit`; token from the environment |
| `scripts/changed-images.sh <before> <after>` | image directories changed between two commits, as a JSON list |
| `scripts/publish-rehearsal.sh <local-ref> <images/name>` | steps 3 and 5 against a throwaway local registry, twice, to show the release goes 1 then 2 |
| `.github/workflows/build-certify.yaml` | the publish steps above; no workflow-level `permissions`, so the caller decides what the run may do |
| `.github/workflows/publish.yaml` | caller: on push to `main` touching `images/**`, publishes the changed images; `workflow_dispatch` with an image name republishes one (for pipeline changes). Grants `id-token: write` and `attestations: write` |
| `.github/workflows/images.yaml` | unchanged caller for PRs, read-only; now also runs the rehearsal |

Secrets, looked up by `redhat.secretSuffix`:
`RH_REGISTRY_USER_<SUFFIX>`, `RH_REGISTRY_PASSWORD_<SUFFIX>`, and
`RH_PYXIS_TOKEN_<SUFFIX>` falling back to a shared `RH_PYXIS_TOKEN` (ADR-002
open question: the Pyxis key may be per account).

Not changing: the PR path's behaviour, the checks, the ADRs.

## Checks (red first)

In `tests/run.sh`, no network:

- **next-release:** no tags → 1; `v1-1, v1-2` → 3; tags of other versions and
  non-numeric suffixes ignored; `v1.2.3-10` sorts after `v1.2.3-9`; a version
  that is a prefix of another (`v1.2` vs `v1.2.3`) is not confused.
- **publish-plan:** placeholder component ID → `publishable=false` with a
  reason; a 24-hex ID → `publishable=true` and the right repository; a
  malformed ID fails.
- **changed-images:** against a throwaway git repo: a change in one image
  directory lists that image; a docs change lists none; a deleted image is not
  listed; an all-zero `before` lists every image.
- **test-image release label:** covered in CI (needs an image).
- **check-image:** `redhat.componentId` must be the placeholder or 24 hex
  characters (rule 13).

In CI on pull requests, no credentials:

- **publish rehearsal:** against a local registry, the first push is release 1
  and the second is release 2, and the pushed digest can be pulled back.

## What cannot be tested before credentials exist

Steps 2, 6, 7 and 8 need Red Hat credentials or would write a public
transparency-log entry under this repository's identity. They are written and
linted, and they run for the first time on the first real publish. That run is
part of this story, and a person triggers it.

## Human steps and outward-facing actions

1. Partner Connect: create the container component (UBI, Red Hat Container
   Registry); submit the export questionnaire.
2. Put the component ID in `images/<name>/image.yaml`.
3. Add the repository secrets above.
4. Merge the PR that sets the component ID. That merge is the first publish.
5. After it: run the README's verify commands from a machine outside CI,
   against the public pull spec, and report the result.

## Out of scope

- The daily re-scan and the SLSA L3 assessment: backlog stories.
- Air-gapped verification: story P.3.
- A GitHub environment with required reviewers on the publish job. It is a
  repository setting; recommended, and noted in the README.

## Done means

The roadmap Done line: component ID in `image.yaml`; a merge to `main` pushes,
signs, attests and submits; the image shows as certified in Red Hat's catalog;
the README's verify commands succeed against the public pull spec from outside
CI; the provenance level we claim is recorded. Also: `make verify` green; README
status and verify section updated; ADR-008 open question 1 answered in the ADR.

**This story cannot reach ✅ on code alone.** It ends at 🔨 "ready for first
publish" until the human steps are done.
