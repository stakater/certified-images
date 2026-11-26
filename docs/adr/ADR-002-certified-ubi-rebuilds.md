# ADR-002: Certified UBI rebuilds of upstream OSS (umbrella)

- **Status:** Accepted (pilot: OpenCost). Revision 7, 2026-11-26. Earlier revisions are in `archive/`.
- **Owner:** Rasheed Amir (Stakater), who is also interim factory owner until a factory team is named.
- **References:** Iron Bank, OpenShift ART, Konflux, Chainguard (see `docs/references.md`).

## Context
Stakater products deploy upstream OSS (OpenCost, Dex, Crossplane providers, …) pulled from ghcr.io/quay.io/xpkg.upbound.io by tag. This breaks two things:
1. **Air-gapped installs.** `oc-mirror` only mirrors images listed in the bundle's `relatedImages`, and IDMS only remaps digest references.
2. **Red Hat certification.** Every operand must be a certified image.

MTO needs this now. SCO needs it for many Crossplane providers and functions. Reloader Enterprise will need it later.

## Decision
One repository, `stakater/certified-images`, with one pipeline that rebuilds admitted upstreams **from source** on Red Hat UBI, certifies them in Partner Connect, and publishes them with SBOM, signatures and provenance.

**Two registries, two purposes.** Every build is first published to a staging registry we control, then promoted to Red Hat's:

| Registry | Path | What it is for | Who may reference it |
|---|---|---|---|
| GHCR (staging) | `ghcr.io/stakater/ubi/<name>` | Every build, as soon as it passes the checks. Lets products test before certification, and keeps the pipeline exercised while Red Hat's manual steps are pending | Stakater teams, in test and development. Private unless the image declares otherwise (below) |
| Red Hat (certified) | `registry.connect.redhat.com/stakater/<name>` | The same digest, after certification | Anything shipped to a customer. A certified operator bundle must reference this one |

**Staging visibility is declared per image, and private is the default.** `image.yaml` may set `staging.visibility: public`. That is a decision made in a reviewed PR, and it is only for rebuilds of permissively licensed open-source software, which anyone could build themselves. An image of Stakater's own code (ADR-006) is never public in staging. The pipeline asks the registry anonymously before and after each push and fails if a package is more open than its image declares. (Revision 5 said organisation-only for everything. The first staged package was created public, the owner chose to keep that image public, and a blanket rule would then either block it or leave nothing protecting the images that must stay private.)

The staging path says `ubi`, not `certified`: an image there has passed our checks, not Red Hat's. The image is copied to Red Hat by digest, so what was staged and tested is byte for byte what is certified.

**Why from source.** Certification only requires a UBI base, so re-layering upstream's binary would pass. We build from source because it lets us fix vulnerabilities upstream has not fixed yet (rule 2), and because the SBOM and provenance then describe a build we ran, not one we trust.

We follow existing implementations rather than designing our own:

| Concern | Decision | Follows | ADR |
|---|---|---|---|
| Builds without network, pinned sources | Hermeto prefetch + `--network=none` | Iron Bank, Konflux/Hermeto | 003 |
| Swappable, pinned bases | `BASE_REGISTRY/BASE_IMAGE/BASE_TAG` + digests | Iron Bank | 004 |
| Containers and Crossplane packages | `kind:` in `image.yaml` | Crossplane xpkg tooling | 005 |
| Stakater-owned upstreams | `Containerfile.ubi` in their own repo, reusable workflow | OpenShift `Dockerfile.rhel` | 006 |
| Build platform | GitHub Actions; Konflux re-evaluated on triggers | Konflux, GitHub attestations guide | 007 |
| Supply-chain evidence | SBOM, cosign, SLSA provenance, VEX exceptions | Chainguard, Iron Bank VAT | 008 |

Consumers reference results **by digest** only: CSV `relatedImages` + `RELATED_IMAGE_*` for operators; xpkg digests + `ImageConfig` for Crossplane.

## Rules
1. **Admission.** Rebuild only when all four hold:
   - (a) no Red Hat-provided image exists that we are entitled to ship as an operand of our product (an image that is licensed only as part of another Red Hat product does not count);
   - (b) the licence is permissive (Apache-2.0/MIT/BSD; anything else needs legal sign-off);
   - (c) upstream is maintained (release in the last 6 months);
   - (d) a Stakater product deploys it.

   Otherwise use the Red Hat image or the customer's own (External mode).
   **Exit.** Admission is re-checked on every upstream bump. An image that no longer passes is retired: its consumers get a dated notice, and it is patched under rule 4 until that date.
2. **Build from source** at a pinned commit (ADR-003). Never re-tag upstream binaries.
   **Deviations from upstream.** We build what upstream released, with exactly two allowed deviations, both only to fix a vulnerability covered by rule 4:
   - a patch-level bump of the Go (or other language) toolchain;
   - a bump of a dependency to a version that fixes the vulnerability.

   Each deviation is recorded in `image.yaml`, offered upstream as a PR, and removed when upstream ships the fix. No other patches: no features, no behaviour changes, no backports.
3. **Naming and versions.** "Stakater build of <Project>"; registry path `stakater/<name>` at Red Hat and `stakater/ubi/<name>` in staging. Keep upstream LICENSE/NOTICE in `/licenses`. Don't use upstream logos or marks.
   Tags are `<upstream-version>-<release>`, e.g. `v1.121.5-3`. `release` starts at 1, goes up by one on every rebuild of the same upstream version (base-digest bump, deviation, pipeline change), and resets to 1 on an upstream bump. This is the RPM and Red Hat convention. Tags are for people; consumers still pin the digest. The staging registry is the single source of release numbers, and a release has the same tag in both registries. A release tag is never overwritten.
4. **Patch SLA.** Fixable CRITICAL vulnerabilities within 7 days, fixable HIGH within 30 days; upstream minor releases within 30 days.
   - The clock starts on the day a fix is available, in UBI or in upstream, whichever applies.
   - The CVE gate (ADR-008) fails on fixable CRITICAL **and** HIGH.
   - Published digests that consumers still reference are re-scanned on a schedule, at least daily, because a build-time gate cannot see a vulnerability disclosed after publication.
   - Renovate opens the PRs.
   - We maintain one stream per image: the latest admitted upstream version.
5. **Partner Connect.** One component per image, Red Hat Container Registry distribution. Batch new images into one export questionnaire.
   **Credentials.** We will publish many components, so credentials must not multiply with them where Red Hat allows:
   - **One Partner Connect API key for all images** (`RH_PYXIS_TOKEN`). The key belongs to a Partner Connect account; the component is chosen by the ID passed to preflight. It is created from a dedicated Stakater certification account, not a personal one, and its rotation is a documented runbook step (`docs/setup.md`).
   - **No secret is named per image.** Red Hat gives each component its own registry login, which we cannot change, but we do not mirror that as two GitHub secrets per image: at dozens of components that is unmanageable. The username is derived from the component ID. The registry key comes from Red Hat's API using the shared API key if the API offers it (⚠️ unconfirmed; `scripts/pyxis-probe.sh` answers it), and otherwise from one shared secret, `RH_REGISTRY_KEYS`, a JSON object keyed by component ID.
   - The repository therefore holds at most two Red Hat secrets, whatever the number of images.
6. **Governance.** CODEOWNERS on `images/**` and `.github/**`: only the factory team merges to `main`, which publishes (Iron Bank model). Anyone may open a PR.
   **One exception:** Renovate automerges UBI base-digest bumps after green CI. The diff is a single digest line, and waiting for a person on each one would break the 7-day SLA. Every other change, including upstream bumps and deviations, needs a factory-team review.
7. **No invention.** A new pattern needs a reference in `docs/references.md`, or an ADR that names the gap as a risk.
8. **Architectures.** `linux/amd64` only. `linux/arm64` is added when a consumer asks for it, as a revision of this rule, because each architecture multiplies build, scan and certification work.

## Consequences
- \+ Air gap and certification are solved once and reused across MTO, SCO and Reloader.
- \+ Staging removes Red Hat's manual gates from the critical path: an image is usable for testing, and the outward-facing pipeline is exercised, before its component, secrets or export approval exist.
- − A public staging image can be pulled by anyone before it is certified, and stays pullable if it later fails. Staging is for testing; nothing we tell customers points at it.
- − Two references to the same image invite the wrong one being shipped. The rule is simple and must be enforced in product repos: customer-facing manifests reference Red Hat's registry only.
- \+ CVE, SBOM, signing and provenance claims become verifiable, which is a sellable sovereign-supply-chain story.
- \+ The SLA is measurable: the gate and the scheduled re-scan cover the same severities the SLA promises.
- − Every admitted image is a permanent patching commitment; the admission rule must keep the set small.
- − Deviations are patches we carry. The two-case limit and the upstream-PR requirement keep them few and short-lived.
- − Automerged base bumps publish without a human. The safeguard is the full PR pipeline (CVE gate, preflight), not review.
- − Partner Connect component creation and export approval stay manual (once per image).
- − One registry key per component still has to be copied from Partner Connect by hand, into one shared secret, unless the API fetch works. GitHub cannot show a secret's value, so the full set of keys must also live in the team's password manager.
- − One API key means the certification account is a single point of failure, hence the dedicated account and the rotation runbook.

## Open questions
- A public staging package makes Stakater a public distributor of that software, uncertified builds included. Licence files ship in the image; whether export rules add anything is a question for legal, per image.
- ⚠️ Can the per-component registry credentials be fetched with the API key, leaving one secret in total? Not confirmed: no such endpoint was found in Red Hat's public API docs or their pipeline code (checked 2026-11-26). Partial evidence (2026-11-26): `GET /projects/certification/id/<id>/secrets` answers 401 to an invalid key, where a made-up path under the same component answers 404, so the endpoint exists. What it returns is unknown. The `pyxis-probe` workflow tests it against a real component once `RH_PYXIS_TOKEN` exists. If it works, the fetch is implemented and `RH_REGISTRY_KEYS` is retired.
- ⚠️ The derived username format, `redhat-isv-containers+<componentId>-robot`, is from Red Hat's push instructions as remembered. The first real login confirms it.
- ⚠️ That one API key covers every component is Red Hat's documented model and has not yet been exercised by this pipeline; the first publish of a second image confirms it.
- ⚠️ Whether Red Hat ships a Dex image we are entitled to use as an operand (rule 1a). Check before admitting Dex.
- The factory team is not named yet. Until it is, the interim owner is the only person who can merge.

Delivery status and the order of the next images are in `docs/roadmap.md`, not here.
