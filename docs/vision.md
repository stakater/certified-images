# Vision and value proposition

> **📝 Draft.** Derived from the README and ADR-002 on 2026-11-25. Not yet
> agreed. Stories in `docs/roadmap.md` are checked against this page, so it
> needs a human decision before any story is approved.

## The problem

Stakater products deploy upstream OSS (OpenCost, Dex, Crossplane providers)
pulled from public registries by tag. Two things break:

1. **Air-gapped installs.** `oc-mirror` mirrors only the images listed in an
   operator bundle's `relatedImages`, and digest references are the only ones a
   cluster can remap to a mirror.
2. **Red Hat certification.** A certified operator may only deploy certified
   operand images.

Each product team solving this alone would repeat the same work and carry the
same patching burden separately.

## Who it is for

| Who | What they need |
|---|---|
| Stakater product teams (MTO, SCO, Reloader Enterprise) | a certified, digest-pinned image for each upstream they deploy, without running a build pipeline themselves |
| Customers running air-gapped or regulated OpenShift | products that install from a mirror, with evidence they can check themselves |
| Customer security teams and tender reviewers | SBOM, signature, provenance and a stated patch SLA per image |

## Vision

One factory that turns an admitted upstream project into a certified,
verifiable, digest-pinned artifact, the same way every time.

## Value proposition

- **For product teams:** air gap and certification are solved once and reused.
- **For customers:** every image a Stakater product runs can be mirrored and
  verified, and comes with a patch commitment.
- **For Stakater:** supply-chain claims are backed by evidence the pipeline
  produces, which supports the sovereign-cloud positioning.

## What this is not

- Not a general hardened-image catalogue. An image is admitted only when a
  Stakater product deploys it (ADR-002 rule 1).
- Not a fork. We rebuild upstream at a pinned commit and keep its APIs.
- Not a replacement for Red Hat's own images. Where Red Hat ships one, use it.

## Open questions for this page

- Who owns the factory? ADR-002 lists the factory owner as TBD, and every
  admitted image is a permanent patching commitment.
- Is the catalogue also a product customers buy, or only an enabler for the
  other products? The answer changes how much evidence and SLA we promise.
