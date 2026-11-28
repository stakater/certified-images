# ADR-002: Certified UBI rebuilds of upstream OSS (umbrella)

- **Status:** Accepted (pilot: OpenCost). Revision 10, 2026-11-28 (rule 1: look in Red Hat Hardened Images first, and hold them to our CVE gate). Earlier revisions are in `archive/`.
- **Owner:** Rasheed Amir (Stakater), who is also interim factory owner until a factory team is named.
- **References:** Iron Bank, OpenShift ART, Konflux, Chainguard (see `docs/references.md`).

## Context
Stakater products deploy upstream OSS (OpenCost, Dex, Crossplane providers, …) pulled from ghcr.io/quay.io/xpkg.upbound.io by tag. This breaks two things:
1. **Air-gapped installs.** `oc-mirror` only mirrors images listed in the bundle's `relatedImages`, and IDMS only remaps digest references.
2. **Red Hat certification.** Every operand must be a certified image.

MTO needs this now. SCO needs it for many Crossplane providers and functions. Reloader Enterprise will need it later.

## Decision
One repository, `stakater/certified-images`, with one pipeline that rebuilds admitted upstreams **from source** on Red Hat UBI, certifies them in Partner Connect, and publishes them with SBOM, signatures and provenance.

**Where an image lives, and where customers pull it from.** Every build that passes the checks is pushed to our registry, `ghcr.io/stakater/ubi/<name>`, signed and attested there. Customers pull certified images from Red Hat's address, `registry.connect.redhat.com/stakater/<name>`. How the image gets from one to the other depends on how its Partner Connect component was created (`docs/red-hat-distribution.md`):

| Setup | Who stores the certified image | What the pipeline does for Red Hat | Secrets |
|---|---|---|---|
| **A. Red Hat hosts it** (default for new components) | Red Hat's registry | Copy the same digest to Red Hat's registry, sign it there, submit | `RH_PYXIS_TOKEN` + that component's registry key |
| **B. Red Hat lists it, we host it** (not proven; do not use for new components) | Our GHCR | Submit the GHCR image for certification | `RH_PYXIS_TOKEN` only |

The pipeline does not declare which setup an image uses. It asks Red Hat's API for the component's record and follows it, and fails if it cannot read it.

**For a setup B image, GHCR is where the published image lives, not a staging area.** Three rules follow:
- A tag that has been submitted to Red Hat is never deleted from GHCR, and its package is never made private without first giving Red Hat a read credential.
- GHCR's availability is part of the product's availability.
- An image on GHCR is certified only once it has been submitted and Red Hat has accepted it. Being on GHCR is not being certified, and anything shipped to a customer still names Red Hat's address.

**Setup A is the default because it is the one that has been seen to deliver.** Revision 8 made setup B the default after a component was certified and listed while its image stayed on GHCR. The same day, a pull of that image from Red Hat's address was refused ("unauthorized") for more than eight hours, with a login that pulls our Red Hat-hosted images, although Red Hat's catalog advertises that pull command. Certification and listing work in setup B; delivery to a customer does not, for a reason we do not know. A question is open with Red Hat. Until a setup B image pulls from Red Hat's address, new components are created Red Hat-hosted, and the cost is one registry key per component, all held in one secret.

**Visibility on GHCR is declared per image, and private is the default.** `image.yaml` may set `staging.visibility: public`. That is a decision made in a reviewed PR, and it is only for rebuilds of permissively licensed open-source software. An image of Stakater's own code (ADR-006) is never public by default. The pipeline asks the registry anonymously before and after each push and fails if a package is more open than its image declares. A private setup B image additionally needs Red Hat to hold a read credential for it.

The path says `ubi`, not `certified`: an image there has passed our checks, and may or may not have been certified yet.

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

   **Where to look for (a).** Search Red Hat's catalog, and look first in **Red Hat Hardened Images**, `registry.access.redhat.com/hi/<name>`. Red Hat builds them (Project Hummingbird), publishes them without a login or terms to accept, and labels them with the UBI licence and `distribution-scope: public`. On 2026-11-27 the catalog API listed 68 repositories there, among them `postgresql`, `kube-state-metrics`, `prometheus` and `dex`, and none for OpenCost, Crossplane or Reloader. 

   **A Red Hat image must pass our CVE gate, or we build.** Decided by the owner on 2026-11-28. "Red Hat ships one" settles (a) only while that image has no fixable CRITICAL or HIGH finding by our gate (ADR-008), when we pin it and in the daily re-scan afterwards. If it fails and we are able to build the software, we build it and patch it under rule 4. If it fails and we are not able to build it, we use Red Hat's and record the finding as a dated exception, as for our own images.
   Why: on 2026-11-27 three of the four hardened images we scanned failed the gate (`hi/dex`, `hi/kube-state-metrics`, `hi/prometheus`), each on Go modules at the version upstream pinned. Red Hat's own security data rates the three CVEs involved Important (CVE-2026-78661, CVE-2026-78669, CVE-2026-116587), and fixed module versions had been available since 2026-10-14 and 2026-10-27. The images are rebuilt often (`hi/postgresql` was built 2026-11-26), so the gap is not stale builds: Red Hat ships upstream's dependency versions, and this factory bumps them. ⚠️ One day's sample of four images; Red Hat's patch commitment for this line is not known to us.
   **Exit.** Admission is re-checked on every upstream bump. An image that no longer passes is retired: its consumers get a dated notice, and it is patched under rule 4 until that date.
2. **Build from source** at a pinned commit (ADR-003). Never re-tag upstream binaries.
   **Deviations from upstream.** We build what upstream released, with exactly two allowed deviations, both only to fix a vulnerability covered by rule 4:
   - a patch-level bump of the Go (or other language) toolchain;
   - a bump of a dependency to a version that fixes the vulnerability.

   Each deviation is recorded in `image.yaml`, offered upstream as a PR, and removed when upstream ships the fix. No other patches: no features, no behaviour changes, no backports.
3. **Naming and versions.** "Stakater build of <Project>"; registry path `stakater/<name>` at Red Hat and `stakater/ubi/<name>` in staging. Keep upstream LICENSE/NOTICE in `/licenses`. Don't use upstream logos or marks.
   Tags are `<upstream-version>-<release>`, e.g. `v1.121.5-3`. `release` starts at 1, goes up by one on every rebuild of the same upstream version (base-digest bump, deviation, pipeline change), and resets to 1 on an upstream bump. This is the RPM and Red Hat convention. Tags are for people; consumers still pin the digest. GHCR is the single source of release numbers. A release tag is never overwritten, and one submitted to Red Hat is never deleted.
4. **Patch SLA.** Fixable CRITICAL vulnerabilities within 7 days, fixable HIGH within 30 days; upstream minor releases within 30 days.
   - The clock starts on the day a fix is available, in UBI or in upstream, whichever applies.
   - The CVE gate (ADR-008) fails on fixable CRITICAL **and** HIGH.
   - Published digests that consumers still reference are re-scanned on a schedule, at least daily, because a build-time gate cannot see a vulnerability disclosed after publication.
   - Renovate opens the PRs.
   - We maintain one stream per image: the latest admitted upstream version.
5. **Partner Connect.** One component per image, Red Hat Container Registry distribution. Batch new images into one export questionnaire.
   **Credentials.** We will publish many components, so credentials must not multiply with them where Red Hat allows:
   - **One Partner Connect API key for all images** (`RH_PYXIS_TOKEN`). The key belongs to a Partner Connect account; the component is chosen by the ID passed to preflight. It is created from a dedicated Stakater certification account, not a personal one, and its rotation is a documented runbook step (`docs/setup.md`).
   - **New components are created Red Hat-hosted (setup A)**, see above.
   - **No secret is named per image.** A setup A component has its own registry login, which Red Hat issues. Its username is derived from the component ID, and its key is held in one shared secret, `RH_REGISTRY_KEYS`, a JSON object keyed by component ID. Fetching it from Red Hat's API was tried and is not possible.
   - The repository therefore holds two Red Hat secrets, whatever the number of images: `RH_PYXIS_TOKEN` and `RH_REGISTRY_KEYS`.
6. **Governance.** CODEOWNERS on `images/**` and `.github/**`: only the factory team merges to `main`, which publishes (Iron Bank model). Anyone may open a PR.
   **One exception:** Renovate automerges UBI base-digest bumps after green CI. The diff is a single digest line, and waiting for a person on each one would break the 7-day SLA. Every other change, including upstream bumps and deviations, needs a factory-team review.
7. **No invention.** A new pattern needs a reference in `docs/references.md`, or an ADR that names the gap as a risk.
8. **Architectures.** `linux/amd64` only. `linux/arm64` is added when a consumer asks for it, as a revision of this rule, because each architecture multiplies build, scan and certification work.

## Consequences
- \+ Air gap and certification are solved once and reused across MTO, SCO and Reloader.
- \+ Pushing to GHCR first removes Red Hat's manual gates from the critical path: an image is usable for testing before its component or export approval exist.
- \+ With setup B, adding an image needs no new secret, and the signature customers can verify sits beside the very digest Red Hat lists.
- − A public GHCR image can be pulled by anyone before it is certified, and stays pullable if it later fails.
- − With setup B we carry the storage: if GHCR is down, or the tag is gone, Red Hat's address has nothing to serve. ⚠️ Inferred from Red Hat's record of the component (hosted: false), not yet observed with an authenticated pull.
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
- Answered 2026-11-26: the per-component registry key cannot be fetched with the API key. With a working key, `GET /projects/certification/id/<id>/secrets` returns only `docker_config_json`, empty, and the component record carries no registry credential. `RH_REGISTRY_KEYS` stays. (Probed against the Reloader component with `scripts/pyxis-probe.sh`.)
- ⚠️ How `registry.connect.redhat.com` serves a setup B image has not been observed: whether it fetches from GHCR on each pull or keeps a copy. `docs/red-hat-distribution.md` has the two commands that settle it; they need a Red Hat login.
- ⚠️ Whether a certified operator bundle may reference setup B images has not been tested. They are certified and listed under Red Hat's address, so it should.
- Confirmed 2026-11-27: the derived username format, `redhat-isv-containers+<componentId>-robot`, logs in, and Red Hat's registry lists tags for a repository that has none yet.
- ⚠️ That one API key covers every component is Red Hat's documented model and has not yet been exercised by this pipeline; the first publish of a second image confirms it.
- Answered 2026-11-27: Red Hat ships a Dex image, `registry.access.redhat.com/hi/dex` (Red Hat Hardened Images), at the same version we build, v2.46.1. Tried at digest `sha256:89603c42…994c6b` on a local kind cluster: it passes our smoke test under restricted pod security and our functional test (discovery, signing keys). Two differences from our build: its entrypoint is `/usr/bin/dex`, so it takes `serve <config>` as arguments, not `dex serve <config>`; and our pinned trivy reports the three fixable HIGH findings in it that our build patches (CVE-2026-116587, CVE-2026-78661, CVE-2026-78669), so at that digest it does not pass our CVE gate. Under rule 1 as revised, our Dex build stays.
- ⚠️ Whether Red Hat's operator certification accepts `hi/` images as operands of a partner operator has not been asked. They are Red Hat's own images, so it should; ask the partner contact.
- ⚠️ What support and lifecycle a customer gets for a `hi/` image, and how long a digest stays pullable, is not known. Red Hat's 2025 announcement said the free images are unsupported and that subscribers get support; the general-availability material does not state the terms.
- The factory team is not named yet. Until it is, the interim owner is the only person who can merge.

Delivery status and the order of the next images are in `docs/roadmap.md`, not here.
