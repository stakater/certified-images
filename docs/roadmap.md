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

**Story DX.1 — the method and the decisions are written down and agreed** 🔨
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
  manages both" is configured and validated but not observed. It needs the
  Renovate app enabled by a repository admin. Everything else in the Done line
  is met; the `ubi-micro` result is in ADR-004.

**Story P.2 — OpenCost is certified and published** 📝
*As the MTO team, I want a certified OpenCost image published with signature,
SBOM and provenance, so that MTO can reference it by digest.*
- **Done:** the Partner Connect component exists and its ID is in `image.yaml`;
  a merge to `main` pushes, signs, attests and submits; the image shows as
  certified in Red Hat's catalog; the README's verify commands succeed against
  the **public pull spec** from a machine outside CI (ADR-008 open question 1);
  the provenance level we claim is recorded (ADR-007).

**Story P.3 — MTO installs OpenCost from a mirror** 📝
*As a customer with an air-gapped cluster, I want MTO to deploy OpenCost from my
mirror, so that showback works without internet access.*
- **Done:** MTO's CSV lists the OpenCost digest in `relatedImages`;
  `oc-mirror` mirrors it; MTO deploys OpenCost on a disconnected cluster;
  signature verification on that cluster is either demonstrated or documented
  as a limitation (ADR-008 open question 2).

## Backlog (one line each, all 📝 Draft)

- Scheduled daily re-scan of published digests (ADR-002 rule 4) and the first outer audit (method.md).
- `<upstream-version>-<release>` tagging with an automatic release counter (ADR-002 rule 3).
- Offer OpenCost's dependency bump upstream and record the PR link in `image.yaml` (ADR-002 rule 2).
- Dex as the second third-party image.
- First external caller of the reusable workflow: template-operator-v2 (ADR-006).
- Spike: build one Crossplane provider both ways and read the pod spec (ADR-005 open question 1).
- First SCO Crossplane provider (ADR-005), after its open questions are answered.
- Assess the pipeline against SLSA v1 Build L3 and record the result (ADR-007).
