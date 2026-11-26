# Roadmap

Stories are the unit of delivery. Each one must serve `docs/vision.md`.

## How we work

- **Story format:** *As a `<role>`, I want `<capability>`, so that `<value>`.*
  Each story has a **Done:** line a third party could check.
- **Lifecycle:** **📝 Draft** (written, not agreed; may be re-scoped or killed)
  → **👍 Approved** (a human said build it) → **🔨 In progress** → **✅ Done**
  (Done line met, checks green, planning doc linked).
  Nothing moves from Draft to In progress without explicit approval.
- **One story at a time**, end to end, then demoed.
- **Walking skeleton first:** one image through the whole pipeline before a
  second image or a second artifact kind.
- The full method is in [method.md](method.md).

## Phase 0 — method and decisions

**Story DX.1 — the method and the decisions are written down and agreed** ✅ *(merged as PR #1, 2026-11-25)*
*As a maintainer or a cold agent session, I want the working method, the vision
and the ADRs agreed and in the repo, so that nobody builds from unreviewed
decisions or re-derives the method from chat history.*
- **Done:** `CLAUDE.md`, `docs/method.md`, `docs/planning/TEMPLATE.md`,
  `docs/vision.md` and this roadmap exist and are approved; each ADR has been
  reviewed and is either accepted as is, revised, or marked Proposed with its
  open questions listed; the README no longer describes files that do not exist.

**Story DX.2 — `make verify` runs the static and unit checks** ✅ *(planning: [dx2-make-verify](planning/dx2-make-verify.md))*
*As a contributor, I want one command that lints Containerfiles, scripts,
`image.yaml`, the Renovate config and workflows, so that "red → green" is
possible before any CI exists.*
- **Done:** `make verify` runs hadolint, shellcheck, the `image.yaml` rules
  (`scripts/check-image.sh`), `renovate-config-validator` and actionlint, plus tests for
  `scripts/new-image.sh`; it fails on a deliberately broken fixture for each;
  a Claude Code edit hook runs it after edits to those files.

## Phase 1 — walking skeleton: OpenCost

**Story P.1 — a pull request builds OpenCost hermetically** 🔨 *(planning: [p1-opencost-pr-build](planning/p1-opencost-pr-build.md))*
*As the factory team, I want a PR to run pinned clone → Hermeto prefetch →
offline build → SBOM → CVE gate → preflight dry run for OpenCost, so that we
know the design in ADR-003, ADR-004 and ADR-008 works before we certify
anything.*
- **Done:** `.github/workflows/build-certify.yaml` exists as a reusable workflow
  (ADR-006) with this repo as its first caller; the runtime base and the
  toolchain image are digest-pinned and Renovate manages both (ADR-004); the
  image has been tried on `ubi-micro` and the result recorded; a PR run is
  green for `images/opencost`, including a start-up test of the image; the run
  fails when the tag does not match the pinned commit and when the build tries to reach the network; the "unverified items"
  list in the README is resolved item by item.
- **Open before this is ✅:** Renovate has not run on the repo, so "Renovate
  manages both" is configured and validated but not observed. The same goes
  for the managers added in review (tool images in `tools.env`, and the
  Containerfile's upstream version and commit). It needs the
  Renovate app enabled by a repository admin. Everything else in the Done line
  is met; the `ubi-micro` result is in ADR-004.

**Story P.2 — OpenCost is certified and published** 🔨 *(approved 2026-11-25; planning: [p2-publish](planning/p2-publish.md))*
*As the MTO team, I want a certified OpenCost image published with signature,
SBOM and provenance, so that MTO can reference it by digest.*
- **Done:** the Partner Connect component exists and its ID is in `image.yaml`;
  a merge to `main` pushes, signs, attests and submits; the image shows as
  certified in Red Hat's catalog; the README's verify commands succeed against
  the **public pull spec** from a machine outside CI (ADR-008 open question 1);
  the provenance level we claim is recorded (ADR-007).
- **State:** ready for first publish. The publish path is written; release
  numbering and push are rehearsed in CI against a local registry. Login,
  signing, attestations and submission have never run. Waiting on a person:
  the Partner Connect component and its ID, the export questionnaire, the
  repository secrets, then the merge that sets the ID, then verification from
  outside CI.

**Story P.2a — every image is published to GHCR as a staging registry** 🔨 *(approved 2026-11-26; planning: [p2a-ghcr-staging](planning/p2a-ghcr-staging.md))*
*As a product team, I want every image that passes the checks pushed, signed and
attested to a registry Stakater controls, so that we can test it and keep adding
images without waiting for Red Hat's manual steps.*
- **Done:** a merge that touches an image stages it to
  `ghcr.io/stakater/ubi/<name>` with a `<version>-<release>` tag, a signature,
  two SBOM attestations and provenance; the README's verify commands succeed
  against it from outside CI; the package is confirmed not public; the Red Hat
  stage receives the same digest by copy; ADR-002 rev 5 is merged.

**Story P.2b — an image is proven to run on OpenShift before it is promoted** 🔨 *(approved 2026-11-26, level 1 first; planning: [p2b-smoke-test](planning/p2b-smoke-test.md))*
*As a product team, I want every staged image deployed on a real OpenShift
cluster under the default restricted security context and checked for doing its
job, so that "certified" also means "works", and a broken image is never
promoted to Red Hat.*
- **Done:** each image declares a smoke test (how to deploy it and what a
  healthy answer looks like); after staging, the pipeline deploys the staged
  digest to an OpenShift test cluster under `restricted-v2`, waits for Ready,
  runs the check, and cleans up; promotion to Red Hat does not run unless it
  passes; pull requests run the same test on a local cluster with restricted
  pod security as an approximation.
- **State:** level 1 is done: every PR runs the smoke test on a local cluster
  under restricted pod security, and two broken fixtures prove it can fail.
  Level 2 (a real OpenShift cluster, gating promotion) is not built.
- **Open for level 2:** which OpenShift cluster, and who provides its
  service-account credentials and a GHCR pull secret.
- **Why this exists:** today nothing runs the image on OpenShift. The checks
  prove it starts with `--help` as an arbitrary UID in a plain container
  engine, and that it passes Red Hat's static checks. Neither proves it serves
  requests, runs with a read-only root filesystem, or works under an SCC.

**Story P.2c — images carry correct labels** 🔨 *(approved 2026-11-26; decision: [ADR-009](adr/ADR-009-image-labels.md))*
*As someone inspecting an image, or a scanner reading it, I want its labels to say
who built it, from which commit, on what base and when, so that I am not told
UBI's build date and Red Hat's commit.*
- **Done:** ADR-009 is merged; every image sets the labels it lists; the build
  passes the build commit, build date and base digest; `check-labels.sh` fails
  an image whose labels are missing, wrong or still inherited from the base;
  the scaffold template has them.

**Story F.1 — an image can ship a functional test** 🔨 *(approved 2026-11-26; planning: [f1-functional-tests](planning/f1-functional-tests.md))*
*As a product team, I want each image to carry a test of what it actually does,
run by the pipeline wherever it has a cluster, so that an image that starts but
does not work is caught before it is published.*
- **Done:** an image may ship `functional/test.sh`; the pipeline runs it after
  the smoke test and fails if it fails; Reloader has one proving that a
  ConfigMap change rolls the workload and an unrelated change does not; it has
  been shown to fail without Reloader.

**Story P.3 — MTO installs OpenCost from a mirror** 📝
*As a customer with an air-gapped cluster, I want MTO to deploy OpenCost from my
mirror, so that showback works without internet access.*
- **Done:** MTO's CSV lists the OpenCost digest in `relatedImages`;
  `oc-mirror` mirrors it; MTO deploys OpenCost on a disconnected cluster;
  signature verification on that cluster is either demonstrated or documented
  as a limitation (ADR-008 open question 2).

## Backlog (one line each, all 📝 Draft)

- Scheduled daily re-scan of published digests (ADR-002 rule 4) and the first outer audit (method.md).
- Offer OpenCost's dependency bump upstream and record the PR link in `image.yaml` (ADR-002 rule 2).
- Make the pipeline callable from another repository (ADR-006), then move Reloader's build to the Reloader repository.
- Split the pipeline into build-and-stage, test-on-OpenShift, promote-to-Red-Hat, once the OpenShift runner exists (P.2b level 2).
- Reloader Console (Partner Connect component `6af9ac3f8523cfd9714c7645`) and Reloader Gateway (`6af9ac54ad3a47dac910b90b`): components exist; their source repository and release tags are not yet known to this repo.
- Dex as the second third-party image.
- First external caller of the reusable workflow: template-operator-v2 (ADR-006).
- Spike: build one Crossplane provider both ways and read the pod spec (ADR-005 open question 1).
- First SCO Crossplane provider (ADR-005), after its open questions are answered.
- Assess the pipeline against SLSA v1 Build L3 and record the result (ADR-007).
