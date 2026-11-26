# ADR-002: Certified UBI rebuilds of upstream OSS (umbrella)

- **Status:** Accepted (pilot: OpenCost). Revision 3, 2026-11-25. Earlier revisions are in `archive/`.
- **Owner:** Rasheed Amir (Stakater), who is also interim factory owner until a factory team is named.
- **References:** Iron Bank, OpenShift ART, Konflux, Chainguard (see `docs/references.md`).

## Context
Stakater products deploy upstream OSS (OpenCost, Dex, Crossplane providers, …) pulled from ghcr.io/quay.io/xpkg.upbound.io by tag. This breaks two things:
1. **Air-gapped installs.** `oc-mirror` only mirrors images listed in the bundle's `relatedImages`, and IDMS only remaps digest references.
2. **Red Hat certification.** Every operand must be a certified image.

MTO needs this now. SCO needs it for many Crossplane providers and functions. Reloader Enterprise will need it later.

## Decision
One repository, `stakater/certified-images`, with one pipeline that rebuilds admitted upstreams **from source** on Red Hat UBI, certifies them in Partner Connect, and publishes them with SBOM, signatures and provenance.

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
3. **Naming and versions.** "Stakater build of <Project>"; registry path `stakater/<name>`. Keep upstream LICENSE/NOTICE in `/licenses`. Don't use upstream logos or marks.
   Tags are `<upstream-version>-<release>`, e.g. `v1.121.5-3`. `release` starts at 1, goes up by one on every rebuild of the same upstream version (base-digest bump, deviation, pipeline change), and resets to 1 on an upstream bump. This is the RPM and Red Hat convention. Tags are for people; consumers still pin the digest.
4. **Patch SLA.** Fixable CRITICAL vulnerabilities within 7 days, fixable HIGH within 30 days; upstream minor releases within 30 days.
   - The clock starts on the day a fix is available, in UBI or in upstream, whichever applies.
   - The CVE gate (ADR-008) fails on fixable CRITICAL **and** HIGH.
   - Published digests that consumers still reference are re-scanned on a schedule, at least daily, because a build-time gate cannot see a vulnerability disclosed after publication.
   - Renovate opens the PRs.
   - We maintain one stream per image: the latest admitted upstream version.
5. **Partner Connect.** One component per image, Red Hat Container Registry distribution. Batch new images into one export questionnaire.
6. **Governance.** CODEOWNERS on `images/**` and `.github/**`: only the factory team merges to `main`, which publishes (Iron Bank model). Anyone may open a PR.
   **One exception:** Renovate automerges UBI base-digest bumps after green CI. The diff is a single digest line, and waiting for a person on each one would break the 7-day SLA. Every other change, including upstream bumps and deviations, needs a factory-team review.
7. **No invention.** A new pattern needs a reference in `docs/references.md`, or an ADR that names the gap as a risk.
8. **Architectures.** `linux/amd64` only. `linux/arm64` is added when a consumer asks for it, as a revision of this rule, because each architecture multiplies build, scan and certification work.

## Consequences
- \+ Air gap and certification are solved once and reused across MTO, SCO and Reloader.
- \+ CVE, SBOM, signing and provenance claims become verifiable, which is a sellable sovereign-supply-chain story.
- \+ The SLA is measurable: the gate and the scheduled re-scan cover the same severities the SLA promises.
- − Every admitted image is a permanent patching commitment; the admission rule must keep the set small.
- − Deviations are patches we carry. The two-case limit and the upstream-PR requirement keep them few and short-lived.
- − Automerged base bumps publish without a human. The safeguard is the full PR pipeline (CVE gate, preflight), not review.
- − Partner Connect component creation and export approval stay manual (once per image).

## Open questions
- ⚠️ Secrets per image. `image.yaml` assumes three per image (`RH_PYXIS_TOKEN_*`, `RH_REGISTRY_USER_*`, `RH_REGISTRY_PASSWORD_*`). The Pyxis API key may be per partner account, which would make it one shared secret plus two per image. Check in Partner Connect when the first component is created.
- ⚠️ Whether Red Hat ships a Dex image we are entitled to use as an operand (rule 1a). Check before admitting Dex.
- The factory team is not named yet. Until it is, the interim owner is the only person who can merge.

Delivery status and the order of the next images are in `docs/roadmap.md`, not here.
