# certified-images — agent & contributor guide

## What this repo is

The Stakater **image factory**. It takes an upstream open-source project that a
Stakater product deploys and turns it into an image that product can ship:

1. **rebuilt from source** at a pinned commit, on a Red Hat UBI base, with no
   network during the build;
2. **checked**: it starts, it carries the labels and licences Red Hat requires,
   and it has no fixable CRITICAL or HIGH vulnerabilities;
3. **pushed** to a registry Stakater controls (GHCR), with an SBOM, a signature
   and build provenance, so products can test it;
4. **certified** by Red Hat and listed under Red Hat's address, as the same
   digest.

**Why it exists.** Stakater products (Multi-Tenant Operator first, then SCO and
Reloader Enterprise) must install in air-gapped OpenShift clusters, and a Red
Hat certified operator may only deploy certified images. Upstream images pulled
by tag from public registries satisfy neither. The factory solves both once,
for every product.

**What kind of repo it is.** A build-and-release repo, not a service. There is
no application code. The "code" is one directory per image
(`images/<name>/`), the shell scripts that make up the pipeline, the CI
workflows that call them, and the Renovate config that keeps everything
current. Each image is data; the pipeline is the same for all of them.

**Who works here.** The factory team owns the pipeline and the third-party
images. Product teams consume the images by digest. Agents work under the
method below, with a human approving each story.

## Where the current state lives

This file describes how the factory works, not what state it is in. Do not put
status, image names or version numbers here; they go stale.

| Question | Where to look |
|---|---|
| What works today, what is not built yet | `README.md`, "Status" |
| Which stories are approved, in progress, done | `docs/roadmap.md` |
| What an image is pinned to, and its deviations | `images/<name>/image.yaml` |
| What is still unverified | ⚠️ marks in `docs/`, and `README.md` |
| How the pieces fit together (diagrams) | `README.md`, "How it works" |
| How an image reaches a customer through Red Hat | `docs/red-hat-distribution.md` |
| What the public catalogue site shows, and from what | `docs/planning/s1-catalog-site.md`, `scripts/site-data.sh`, `site/` |
| What a person must set up, and the secrets | `docs/setup.md` |

## Read first

1. `docs/vision.md` — who this is for and the value proposition.
2. `docs/method.md` — how we work: story → plan → red → green → verify → audit.
3. `docs/roadmap.md` — the stories and their lifecycle state.
4. `docs/adr/` — the decisions. ADR-001 is how we record them; ADR-002 is the
   umbrella; 003–009 are its parts. Check each ADR's status line.
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

Routine image work does not need a story each time. Adding an admitted image,
bumping an upstream version and fixing a vulnerability follow the skills below,
through a normal PR. A change to the pipeline, the rules or an ADR needs a story.

## Skills and hooks

| What | When | Where |
|---|---|---|
| `/add-image` | Adding a new upstream project to the factory | `.claude/skills/add-image/SKILL.md` |
| `/fix-cve` | The CVE gate or the re-scan reports a vulnerability in an image | `.claude/skills/fix-cve/SKILL.md` |
| Daily re-scan | Scans the newest published release of every image, keeps one issue per image, and opens a fix pull request on branch `auto/fix-<image>`. It never merges | `.github/workflows/rescan.yaml`, `scripts/auto-fix.sh` |
| Verify hook | Runs `make verify` after every edit to a checked file, so an unverified change cannot be called done | `.claude/settings.json`, `scripts/verify-hook.sh` |

If the hook reports a failure, fix it before doing anything else. Do not edit
the hook or a check to make a failure go away.

## Invariants — stop and flag before breaking one

These come from the ADRs. The ADR wins if this list and an ADR disagree.

1. **Build from source at a pinned commit.** Never re-tag or re-layer upstream
   binaries. `image.yaml` carries both the tag and the commit it must point to
   (ADR-002 rule 2, ADR-003). The only allowed deviations from upstream are a
   toolchain patch bump or a dependency bump that fixes a vulnerability in the
   patch SLA, recorded in `image.yaml` and offered upstream.
2. **No network inside the build.** Dependencies are prefetched with Hermeto
   using typed fetchers, then the build runs with `--network=none` (ADR-003).
3. **Every image input is pinned by digest**: the UBI runtime base, the
   toolchain image, and the tools in `tools.env`. The Containerfile `ARG`
   defaults are the single source of truth for an image's bases (ADR-004).
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

- **Merging to `main` publishes.** A merge that touches an image pushes it to
  our registry (`ghcr.io/stakater/ubi/<name>`) and signs it. If the image has
  a Partner Connect component ID, the pipeline then asks Red Hat how that
  component is distributed and either copies the same digest to Red Hat's
  registry or submits the GHCR image, and Red Hat lists it publicly
  (`publish.yaml`, ADR-002). Never merge, push to `main`, or trigger a publish
  without explicit authorization. Work on a feature branch and open a PR.
- **Never set a component ID without being asked.** It is what makes an image
  go to Red Hat.
- **Being on GHCR is not being certified.** An image is certified once it has
  been submitted and Red Hat has accepted it. A public image's GHCR address
  may be given to customers, by digest, and is shown on the catalogue site
  (ADR-002 rev 12). Never call an image certified unless Red Hat lists it, and
  never put a GHCR reference in an operator bundle submitted to Red Hat.
- **Never delete a tag or package from GHCR, and never make a public package
  private.** A release tag is never changed or removed (ADR-002 rule 3), and
  for a component Red Hat lists without hosting, Red Hat's address depends on
  the image staying on GHCR (`docs/red-hat-distribution.md`).
- **GHCR packages are private unless declared.** `staging.visibility: public`
  in `image.yaml` is the owner's decision, per image, and only for rebuilds of
  open-source software. Never add it without being asked, and never for an
  image of Stakater's own code (ADR-002).
- **Secrets by reference only.** There is one Red Hat secret for the whole
  repository, `RH_PYXIS_TOKEN`, plus `RH_REGISTRY_KEYS` for components Red Hat
  hosts. No secret is named per image (ADR-002); never add one. Never read, echo or inline a secret's
  value, and never print an API response without redacting it.
- **Human steps stay human.** Creating a Partner Connect component, submitting
  an export questionnaire, adding repository secrets, and opening a PR on an
  upstream project are done by a person. Say what is needed; do not attempt them.
- **Branches named `auto/fix-*` belong to the re-scan workflow.** It rebuilds
  them from `main` and force-pushes. Do not commit to them; review their pull
  request, and merge or close it.
- **Do not weaken a check to get a green run.** A failing gate is information.
  Fix the cause, or record an exception the way ADR-008 describes.

## Testing — what "red → green" means here

There is no application code, so tests are checks on the factory's inputs and
outputs. `make verify` runs the Static and Unit levels. The Image and End to end
levels need a build, so they run in CI and locally with `make image IMAGE=<name>`.

| Level | Checks | Tools |
|---|---|---|
| Static | Containerfile lint, shell lint, `image.yaml` rules, Renovate config, workflow lint | hadolint, shellcheck, `scripts/check-image.sh`, `renovate-config-validator`, actionlint |
| Unit | Scripts and check logic against fixtures; every check is shown to fail on a broken input | `tests/run.sh` (plain bash) |
| Image | The built image has the required labels, `/licenses`, non-root user, and starts as an arbitrary UID | `scripts/test-image.sh`, `scripts/preflight-dry-run.sh` |
| Cluster | The image runs as a pod under restricted pod security (arbitrary UID, read-only root, no capabilities), becomes Ready and serves. On a local kind cluster this approximates OpenShift; it is not OpenShift | `scripts/smoke-test.sh`, `make smoke`, `make test-smoke` |
| Functional | What the image does, not just that it starts. Optional, per image: `functional/test.sh` runs against the running image and its exit status decides. The same test runs wherever the pipeline has a cluster | `images/<name>/functional/test.sh`, run by `scripts/smoke-test.sh` |
| Stack | Images that only work together are built from the same checkout and run with each other, not with upstream's builds of their peers | `stacks/<name>/images`, `stacks/<name>/test.sh`, run by `scripts/stack-test.sh`, `make stack STACK=<name>` |
| End to end | A PR run goes prefetch → offline build → SBOM → CVE gate → preflight → publish rehearsal against a local registry; a separate job proves builds cannot reach the network | `build-certify.yaml`, `make test-hermetic` |

Rules for working with it:

- **Run `make verify` before calling a change done**, and report its real
  output. It needs a running container engine (`ENGINE=docker` or `podman`);
  every tool is a container image pinned by digest in `tools.env`, the only
  place a tool is pinned.
- **A new rule starts as a failing case in `tests/run.sh`**, then the rule.
- A check that cannot run must fail. Never make one skip silently.
- Scripts must run on bash 3.2 (macOS) and bash 5 (CI).
- A functional test must be shown to fail once without the thing it tests
  (run it in a namespace where the image is not running) and the result
  recorded in the PR. It may use only `kubectl` and its own namespace.
- Never say an image "works on OpenShift" on the strength of the smoke test.
  Until it runs on a real OpenShift cluster, say "passes the smoke test under
  restricted pod security".
- `make image` under emulation on an Apple Silicon Mac is very slow. Use the
  PR's CI run as the image-level evidence and say that you did.
- For anything the checks do not cover, say plainly what was checked by hand
  and what was not checked.

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
- **One step, one script.** Each pipeline step is a script in `scripts/` that
  runs the same locally and in CI. Workflows only call them (ADR-007).

## Layout

```
images/<name>/image.yaml       one manifest per image: upstream tag + commit, prefetch (and dropVendor), deviations, test command, Red Hat component
images/<name>/Containerfile    hermetic build stage + parameterised, digest-pinned UBI runtime stage
images/<name>/patches/*.patch  optional dependency-only patches, each listed under deviations
images/<name>/vex.openvex.json optional CVE exceptions
images/<name>/smoke/*.yaml     optional fixtures the smoke test deploys first (RBAC, a stub dependency)
images/<name>/smoke/deploy.sh  optional: the image deploys itself for the smoke test (it needs an init step or its own chart); cleanup.sh undoes it
images/<name>/functional/test.sh optional test of what the image does; gets TEST_NAMESPACE, TEST_POD, TEST_IMAGE, TEST_TIMEOUT
stacks/<name>/images, test.sh  images that only work together, and the test that runs them with each other
scripts/new-image.sh           scaffolds images/<name>/ from scripts/templates/
scripts/check-image.sh         our own rules for one image directory
scripts/fetch-source.sh        pinned commit, moved-tag check, dependency-only patches, drops upstream's vendor/ when image.yaml says so
scripts/prefetch.sh            Hermeto prefetch (the only networked build step)
scripts/build-image.sh         fetch -> prefetch -> build with the network off
scripts/test-image.sh          labels, /licenses, non-root, starts
scripts/check-labels.sh        the label policy (ADR-009), checked on the built image
scripts/scan-image.sh          SBOMs + CVE gate; check-vex.sh checks exceptions
scripts/preflight-dry-run.sh   Red Hat certification checks, nothing submitted
scripts/test-hermetic.sh       proves a build step cannot reach the network
scripts/smoke-test.sh          runs the image as a pod under restricted pod security and asks it to serve
scripts/smoke-kind.sh          the same on a throwaway kind cluster; test-smoke.sh proves it can fail
scripts/stack-test.sh          builds the images of a stack and runs them together on a throwaway kind cluster
scripts/publish-plan.sh        staging repository, and whether and where to publish at Red Hat
scripts/next-release.sh        next <version>-<release> number; list-tags.sh reads the registry
scripts/push-image.sh          pushes and prints the digest reference; assert-tag-free.sh refuses an existing tag
scripts/copy-image.sh          promotes a digest from staging to Red Hat's registry, unchanged
scripts/assert-visibility.sh   fails if a staging package is more open than its image declares
scripts/rh-component-info.sh   asks Red Hat how a component is distributed: hosted by Red Hat, or listed from GHCR
scripts/preflight-submit.sh    OUTWARD-FACING: submits to Red Hat; only a publishing workflow runs it
scripts/rh-registry-login.sh   logs in to Red Hat's registry for a component: derived username, key from the shared secret
scripts/pyxis-probe.sh         what Red Hat's API returns for a component, field names only
scripts/publish-rehearsal.sh   the registry half of a publish against a local registry
scripts/changed-images.sh      which images a merge touched
scripts/notify-slack.sh        tells a Slack channel an image was published; the webhook is the secret SLACK_WEBHOOK_URL
scripts/site-data.sh           the catalogue site's data: every public image, its releases, evidence and Red Hat status
site/                          the catalogue site's pages (static; they render site-data's JSON), and external.json: images used from Red Hat, scanned with grype at each generation
scripts/rescan-image.sh        scans the newest published release; scan-findings.sh and latest-release.sh support it
scripts/report-findings.sh     one GitHub issue per image for its open findings
scripts/auto-fix.sh            prepares the fix: bump-base.sh for UBI packages, fix-go-deps.sh + update-deviations.sh for Go modules
scripts/lib.sh, tools.env      shared: container engine, and every tool image pinned by digest
Makefile                       make verify (repo checks), make image (one image)
tests/run.sh, tests/fixtures/  tests for the scripts and the checks
.github/workflows/             verify.yaml, images.yaml (PR builds), publish.yaml (merges to main), build-certify.yaml (the reusable pipeline both call)
renovate.json                  keeps upstream versions, base digests and tool images current
.claude/                       the verify hook and the skills above
docs/                          vision, method, roadmap, planning docs, ADRs, references
```
