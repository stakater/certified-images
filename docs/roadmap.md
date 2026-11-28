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

**Story P.1a — an upstream that vendors its dependencies can be built** 🔨 *(approved 2026-11-28; planning: [p1a-drop-vendor](planning/p1a-drop-vendor.md); decision: ADR-003 rev 3)*
*As the factory team, I want to build an upstream that commits a `vendor/`
directory Hermeto rejects, so that etcd-druid's operand images can be built
without loosening the prefetch.*
- **Done:** an image may declare `build.dropVendor: true`; the vendored copy is
  removed before the prefetch and dependencies are fetched and verified against
  `go.sum` as for any image; a declaration with nothing to drop fails;
  `etcd-wrapper` and `etcd-backup-restore` build in CI.

**Story E.1 — images that only work together are run together** 🔨 *(approved 2026-11-28; planning: [e1-stack-test](planning/e1-stack-test.md))*
*As a product team, I want the images I deploy as a unit built and run with
each other on every pull request, so that a set of images that each pass alone
but fail together is never published.*
- **Done:** a stack is a directory under `stacks/` listing its images, with a
  test; `scripts/stack-test.sh` builds them, runs them together on a throwaway
  cluster and fails if the test fails; pull requests run every stack; the etcd
  stack (etcd-druid, etcd-wrapper, etcd-backup-restore) is the first.
- **Why this exists:** on 2026-11-28 every check on the pull request adding
  the two etcd operand images was green while they could not work under our
  etcd-druid. The smoke tests run each image in a pod of their own making,
  next to upstream's peers.

**Story P.1b — an image with a web UI built with pnpm can be built** 🔨 *(approved 2026-11-28; planning: [p1b-pnpm-ui](planning/p1b-pnpm-ui.md); decision: ADR-003 rev 4)*
*As the factory team, I want to build Prometheus with its web UI from source,
with the network off, so that MTO gets a Prometheus we patch ourselves and no
part of it is an artifact someone else built.*
- **Done:** an image may list `pnpm` lockfiles in `build.prefetch` and build
  them in a stage of its own with digest-pinned Node and pnpm images;
  Prometheus builds that way in CI and serves the UI built here.

**Story P.2 — OpenCost is certified and published** 🔨 *(approved 2026-11-25; planning: [p2-publish](planning/p2-publish.md))*
*As the MTO team, I want a certified OpenCost image published with signature,
SBOM and provenance, so that MTO can reference it by digest.*
- **Done:** the Partner Connect component exists and its ID is in `image.yaml`;
  a merge to `main` pushes, signs, attests and submits; the image shows as
  certified in Red Hat's catalog; the README's verify commands succeed against
  the **public pull spec** from a machine outside CI (ADR-008 open question 1);
  the provenance level we claim is recorded (ADR-007).
- **State:** submitted. On 2026-11-27 the pipeline pushed `v1.121.5-6` to
  GHCR, copied the same digest to Red Hat's registry, signed it there and
  submitted it; certification is in progress. Not published: Red Hat's export
  approval for the component is pending. Still to do once it is published:
  pull it from `registry.connect.redhat.com` from outside CI.

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
  Extended 2026-11-27 (approved by the owner 2026-11-28, with the instruction to merge its pull request):
  an image that cannot run as one bare pod ships `smoke/deploy.sh` and deploys
  itself into the same restricted namespace. Crossplane is the first.
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
- **State:** done on the local cluster. Run by hand without Reloader on
  2026-11-26: the control passed and the main assertion failed after its
  timeout, as it should. Not yet run on OpenShift (P.2b level 2).

**Story P.2d — Red Hat lists it, we host it** 🔨 *(approved 2026-11-27; decision: ADR-002 rev 8; explainer: [red-hat-distribution](red-hat-distribution.md))*
*As the factory team, I want an image certified and listed by Red Hat without
pushing it to Red Hat's registry, so that adding an image adds no secret.*
- **Done:** the pipeline asks Red Hat how a component is distributed and, for a
  component Red Hat does not host, submits the GHCR image with only
  `RH_PYXIS_TOKEN`; Reloader v2 is certified and listed at
  `registry.connect.redhat.com/stakater/reloader-operator` this way.
- **Not done after all:** on 2026-11-27 an authenticated pull from Red Hat's
  address was refused ("unauthorized"), while Red Hat-hosted Stakater images
  pull with the same login. Certification and listing work; delivery to a
  customer is not proven. Cause unknown. This story is 🔨, not ✅, until that
  pull works.

**Story V.1 — published images are re-scanned every day** 🔨 *(built; first scheduled run pending)* *(approved 2026-11-27; planning: [v1-rescan-and-autofix](planning/v1-rescan-and-autofix.md))*
*As the factory team, I want every published image scanned daily and one issue
per image when something fixable appears, so that we know the day a
vulnerability is published, and the SLA clock is visible.*
- **Done:** a daily workflow scans the newest published release of each image
  with the build's own gate and VEX file; a finding opens or updates one issue
  per image; no findings closes it.

**Story V.2 — the fix arrives as a pull request** 🔨 *(approved 2026-11-27; same planning doc)*
*As the factory team, I want the fix for a finding prepared automatically and
built, so that a person only has to review it.*
- **Done:** for a UBI package the base digest is bumped; for a Go module the
  image's dependency patch is regenerated with the fixed version and its
  deviation recorded; the change is pushed as a pull request and built with the
  smoke and functional tests. It is never merged automatically.

**Story P.3 — MTO installs OpenCost from a mirror** 📝
*As a customer with an air-gapped cluster, I want MTO to deploy OpenCost from my
mirror, so that showback works without internet access.*
- **Done:** MTO's CSV lists the OpenCost digest in `relatedImages`;
  `oc-mirror` mirrors it; MTO deploys OpenCost on a disconnected cluster;
  signature verification on that cluster is either demonstrated or documented
  as a limitation (ADR-008 open question 2).

## Backlog (one line each, all 📝 Draft)

- The first outer audit (method.md), once the daily re-scan has run for a while.
- Automatic merge of dependency-only fixes whose tests pass (needs an ADR-002 revision).
- Go standard-library findings: bump the toolchain automatically.
- Reachability analysis, so findings in code that is never called become VEX statements with evidence.
- A public page of the patch SLA per image.
- Offer OpenCost's dependency bump upstream and record the PR link in `image.yaml` (ADR-002 rule 2).
- Make the pipeline callable from another repository (ADR-006), then move Reloader's build to the Reloader repository.
- Split the pipeline into build-and-stage, test-on-OpenShift, promote-to-Red-Hat, once the OpenShift runner exists (P.2b level 2).
- Reloader Console (Partner Connect component `6af9ac3f8523cfd9714c7645`) and Reloader Gateway (`6af9ac54ad3a47dac910b90b`): components exist; their source repository and release tags are not yet known to this repo.
- First external caller of the reusable workflow: template-operator-v2 (ADR-006).
- Crossplane core (`images/crossplane`) is added as a `kind: container` image so providers have something certified to run on; first built by the pull request that adds it. Admission (a) checked 2026-11-27: Red Hat's catalog API lists no container repository named or described as Crossplane, from Red Hat or any partner; the only Crossplane entries are operator bundles from IBM (last bundle 2024) and the community (Upbound's `universal-crossplane`, Crossplane 1.5), neither a Red Hat image. ⚠️ The consuming product's name is not confirmed.
- etcd-druid (`images/etcd-druid`, the operator) is added; first built by the pull request that adds it. Admission (a) to (c) checked 2026-11-28: no Red Hat image (the catalog's "druid" entries are Apache Druid), Apache-2.0, last release 2026-11-04. Admission (d): SCO deploys it (stated by the owner, 2026-11-28). Its two operand images, `etcd-wrapper` v0.8.4 and `etcd-backup-restore` v0.45.3 (the pair used with the `UpgradeEtcdVersion` feature gate on, the chart's default), are added as `images/etcd-wrapper` and `images/etcd-backup-restore` (story P.1a); admission checked 2026-11-28: no Red Hat equivalent (`hi/etcd` is plain etcd, not Gardener's wrapper), Apache-2.0, released 2026-11-03, SCO deploys them. Each is smoke-tested next to upstream's image of the other; the three of ours are run together by the etcd stack test (story E.1). Not built: the `alpine` init image (only used with a local backup store, and it runs as root) and the older operand pair used with the feature gate off. ⚠️ etcd-druid still defaults to Gardener's images; SCO must point it at ours per `Etcd` or through the operator's image override file.
- Images MTO needs that Red Hat also ships as hardened images, decided per image under ADR-002 rule 1 (rev 10: a Red Hat image must pass our CVE gate, or we build). Scanned 2026-11-27 with our pinned trivy, fixable CRITICAL and HIGH, amd64, the `latest` digests:
  - **Dex:** keep our build. `hi/dex` 2.46.1 has 3 HIGH (the three our build patches); it passes our smoke and functional tests.
  - **kube-state-metrics:** build ours: `images/kube-state-metrics`, published 2026-11-28. `hi/kube-state-metrics` 2.20.0 had 2 HIGH in `golang.org/x/net`; upstream's own pins carry 7, so Red Hat does patch dependencies and was behind on the newest.
  - **Prometheus:** build ours: `images/prometheus` (story P.1b), with its web UI built from source. `hi/prometheus` 3.13.5 had 1 HIGH in `golang.org/x/net`.
  - **PostgreSQL:** use `registry.access.redhat.com/hi/postgresql`, by digest. Decided by the owner on 2026-11-28, for now; we do not build it (ADR-002 rev 11).
    - **Not assessed by our gate.** Trivy does not recognise the image's operating system, from the image or from Red Hat's own SBOM, so nothing in it was checked. It is not "passing".
    - Tried 2026-11-28 (18.7, upstream's latest release, image built that day; local kind cluster, arm64): under restricted pod security as an arbitrary UID in group 0 with no capabilities, it started, accepted a write and returned the row, with no restarts. It also runs as its own user (UID 999).
    - **Read-only root filesystem: works, with one condition.** Tried 2026-11-28 with `readOnlyRootFilesystem: true` and volumes for `/var/lib/postgresql` (data), `/var/run/postgresql` and `/tmp`; a write was read back in each case that started:
      - as the image's own user (UID 999, group 999): **works**. This is the case on AKS, EKS and any cluster that does not assign UIDs, and policies there commonly require a read-only root filesystem.
      - as an arbitrary UID in group 0 (how OpenShift runs it): **exits at start-up**. The entrypoint adds an unknown UID to `/etc/passwd` and cannot.
      - as an arbitrary UID with `/etc/passwd` supplied read-only from a ConfigMap that names that UID: **works**. So what it needs is a passwd entry, not a writable filesystem.
      - ⚠️ On OpenShift itself the container runtime may add that entry for the pod, in which case the plain case would work there too. Not tried: nothing here has run on OpenShift. Until it has, an OpenShift deployment either leaves the root filesystem writable or supplies the passwd entry.
    - Why not ours: it fails admission (a); its licence is the PostgreSQL License, permissive but not on our named list, so it would need sign-off; and a PostgreSQL we compile would be invisible to our own gate. Building C software with RPM dependencies would also be a story of its own.
    - ⚠️ Not run on OpenShift. ⚠️ Only the default configuration was run: no replication, no TLS, no extensions.
  - ⚠️ None of the `hi/` images has been run on OpenShift by us; only Dex was run at all. ⚠️ Operand acceptance and support terms are open questions in ADR-002.
- Add the Red Hat images our products consume to the daily re-scan, so a pass or a failure of the gate is noticed (ADR-002 rule 1, rev 10).
- Report the three findings to Red Hat's Hummingbird project (its source is public). A human step.
- ⚠️ To decide: does MTO have to run on AKS and EKS? Then pulls without a login matter: Red Hat's hardened images allow them, our certified images on Red Hat's partner registry do not, and our GHCR address is not one customers may use today (ADR-002).
- kcp (`images/kcp`) is added; first built by the pull request that adds it. Admission (a) to (c) checked 2026-11-28: no Red Hat image or operator in the catalog, Apache-2.0, last release 2026-11-04. Admission (d): SCO deploys it (stated by the owner, 2026-11-28). ⚠️ Our image leaves out the `kubectl` binary upstream downloads into its image; whether a chart or the kcp-operator relies on it has not been checked.
- Crossplane, next step: build one small provider as `kind: xpkg` on pull requests only, and run Red Hat's preflight against the resulting xpkg (ADR-005). The spike of 2026-11-27 showed the pod runs the xpkg itself.
- First SCO Crossplane provider (ADR-005), after its open questions are answered.
- Assess the pipeline against SLSA v1 Build L3 and record the result (ADR-007).
