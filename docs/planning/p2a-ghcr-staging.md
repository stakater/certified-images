# P.2a — every image is published to GHCR as a staging registry

Story: `docs/roadmap.md` P.2a (👍 Approved 2026-11-26). Driver: the Red Hat
publish path is blocked on manual steps (secrets, export questionnaire), and
until it runs, push, signing, attestations and outside verification have never
executed. Products also cannot test an image before it is certified.

## Why (one paragraph)

Publishing only to Red Hat makes every image wait on Red Hat's manual gates
before anything outward-facing is proven. A staging registry we control removes
that dependency: every merge pushes, signs and attests to GHCR with the
workflow's own token, products can pull the image into test clusters by digest,
and more images can be added and exercised now. Red Hat becomes a second stage
that receives the same digest when its component and secrets exist.

## Governing constraints

- **ADR-002 revision 5** (written with this story): GHCR is staging. A
  certified operator bundle references Red Hat's registry only.
- **ADR-002 rule 3:** `<upstream-version>-<release>`; a tag is never
  overwritten. One release number per build, the same in both registries.
- **ADR-002 rule 6:** pull requests stay read-only and hold no credentials.
- **ADR-008 §2:** sign the digest, never the tag. Each registry that holds the
  image carries its own signature and attestations.
- **CLAUDE.md "Claims match evidence":** the staging path must not be called
  "certified". Hence the neutral path `ghcr.io/stakater/ubi/<name>`.
- **Decided by the owner (2026-11-26):** packages are visible to the Stakater
  organisation only, not public.

## Prior art

- GitHub's documented flow: `docker/login-action` with `GITHUB_TOKEN` and
  `packages: write`, then push to `ghcr.io`.
- Promoting one digest between registries by copying the manifest, as `crane
  copy` and `skopeo copy` do. It guarantees the digest is identical, which a
  second `docker push` does not.
- No reference for "staging registry first, certified registry second" as a
  whole. It is our own arrangement of standard parts; the risk is confusion
  about which reference a product should ship, which ADR-002 rev 5 addresses.

## Design

On a merge to `main` that touches an image, for every such image:

1. **Plan**: `publish-plan.sh` now also prints `staging_repository`
   (`ghcr.io/stakater/ubi/<name>`).
2. **Log in to GHCR** with `GITHUB_TOKEN`.
3. **Release number** from the staging repository's tags. GHCR is the single
   source of release numbers.
4. **Build, test, scan, preflight dry run**, as before.
5. **Stage**: assert the tag is free, push to GHCR, sign the digest, attest
   both SBOMs and the build provenance.
6. **Red Hat**, only if the image has a component ID **and** its registry
   secrets and `RH_PYXIS_TOKEN` exist:
   log in to `quay.io` → assert the tag is free there → **copy** the staged
   digest to Red Hat's repository (`scripts/copy-image.sh`, which fails unless
   the digest arrives unchanged) → sign and attest that reference → submit.
   If the component ID is set but a secret is missing, the stage is skipped
   with a warning naming what is missing. The run is green: the image is staged.

| Path | Change |
|---|---|
| `scripts/publish-plan.sh` | adds `staging_repository` |
| `scripts/copy-image.sh <src@digest> <repository> <tag>` | new: copy by digest with crane; prints `<repository>@sha256:…`; fails if the digest differs |
| `scripts/lib.sh` | `crane` helper shared by `list-tags.sh` and `copy-image.sh` |
| `scripts/publish-rehearsal.sh` | also copies the staged image to a second repository and checks the digest is the same |
| `.github/workflows/build-certify.yaml` | the two stages above |
| `.github/workflows/publish.yaml` | grants `packages: write` |
| `docs/adr/ADR-002` | revision 5: the two registries and what each is for |

Not changing: the PR path, the checks, `image.yaml` (the staging path is
derived from the image name).

## Checks (red first)

In `tests/run.sh`:

- **publish-plan:** `staging_repository=ghcr.io/stakater/ubi/<name>` for an
  image with and without a component ID.
- **copy-image**, against a stub engine: an unchanged digest prints the
  destination reference; a changed digest fails; a failed copy fails; a source
  without a digest is refused.
- **No "certified" in the staging path:** a test fails if the staging registry
  default contains the word.

In CI on pull requests: the rehearsal stages to one local repository, copies to
a second, and checks both hold the same digest.

## What only the first real run can show

- Whether `GITHUB_TOKEN` may create `ghcr.io/stakater/ubi/<name>` (an
  organisation setting can forbid it).
- The package's default visibility. Expected: private, linked to this repo.
- cosign keyless signing and attestations, and build provenance, from this
  workflow. Signing writes a public transparency-log entry containing the
  digest and this repository's workflow identity. It does not expose the image.
- Verification from outside CI with the README commands.

## What the first real run showed (2026-11-26)

- The workflow token can create the package; push, cosign signing, both SBOM
  attestations and provenance ran without error. Release 1 of OpenCost is
  `ghcr.io/stakater/ubi/opencost@sha256:efce362bd3995d99661aa1e3b6e0a2a6d47ae78d9e456b996e17e6b280880d91`.
- `gh attestation verify` from outside CI passes with the reusable workflow as
  signer. `cosign verify` has not been run from outside CI yet.
- **The package was created public**, against the owner's decision. The
  expectation above ("private, linked to this repo") was wrong: a public
  repository's packages default to public. Follow-up:
  `scripts/assert-not-public.sh` fails the run when a staging package is
  anonymously pullable, and `docs/setup.md` step 1a has the organisation
  setting that prevents it.

## Human steps and outward-facing actions

1. Merging this story's PR, then running the `publish` workflow for one image
   (or merging a change to an image). **That run is the first real push and
   signature.** A person authorises it.
2. After the first push, an organisation admin checks the package's visibility
   in GitHub → Packages → `ubi/<name>` → Package settings: **not public**;
   readable by the organisation. Visibility cannot be set from the workflow.
3. Product teams that pull from a cluster need a pull secret with
   `read:packages`.

## Out of scope

- Public distribution on GHCR. That is a licensing and export decision.
- Mirroring signatures between registries with `cosign copy`. Each registry is
  signed directly.
- The Red Hat stage's first real run: still story P.2.

## Done means

A merge that touches an image stages it to `ghcr.io/stakater/ubi/<name>` with a
`<version>-<release>` tag, a signature, two SBOM attestations and provenance;
the README's verify commands succeed against that reference from outside CI;
the package is confirmed not public; ADR-002 rev 5 is merged; README, CLAUDE.md
and `docs/setup.md` describe the two registries. `make verify` green.
