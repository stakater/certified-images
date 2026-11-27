# ADR-005: Artifact kinds: container and Crossplane xpkg (SCO wrappers)

- **Status:** Proposed (container implemented; xpkg designed, not built). Edited 2026-11-25 during review and 2026-11-27 after a spike, before first acceptance.
- **References:** Crossplane package model, `crossplane xpkg build --embed-runtime-image`, official extension release workflow, `ImageConfig`, `DeploymentRuntimeConfig`; Upbound UXP as prior art for a vendor Crossplane distribution (see `docs/references.md` §6)

## Context
SCO consumes many upstream Crossplane providers and functions. They are **not** deployed by OLM. Crossplane's package manager:
- pulls an xpkg (OCI image with `package.yaml`);
- installs its CRDs;
- creates a Deployment for the provider's controller.

So rebuilding only the controller image is not enough. The package must be rebuilt so that what Crossplane runs is our build. Otherwise Crossplane still pulls upstream.

## Decision
`image.yaml` gets `kind:` with two values:

| kind | Output | Certified with Red Hat? | Pipeline |
|---|---|---|---|
| `container` | UBI image | Yes (Partner Connect container component) | ADR-002/003/004 |
| `xpkg` | One image: our UBI runtime image, built like `container`, with the package metadata added on top by `crossplane xpkg build --embed-runtime-image`. **That xpkg is the image the provider's pod runs** (spike, below) | Yes, as a container image: it is an ordinary OCI image on a UBI base, and it is the operand | Follows Crossplane's official reusable publish workflow |

OLM bundles for Stakater-owned operators are **not** a kind here. They are built in the product repo (ADR-006), so this repo's schema does not carry them.

Wrapper rules for `xpkg`:
1. **Same upstream commit** for the runtime image and `package/` (one `upstream.commit`).
2. Package name `stakater/<provider>`, e.g. `stakater/provider-kubernetes`. Keep upstream CRD API groups unchanged: forking API groups is a permanent incompatibility.
3. **Dependencies in `crossplane.yaml`** (e.g. family providers depending on `provider-family-*`) are rewritten to our package names in the same PR. CI fails on any remaining upstream registry reference.
4. **Air gap:** customers mirror our packages and set an `ImageConfig` with `matchImages` (prefix) + `rewriteImage.prefix` to their mirror. This requires Crossplane ≥ 1.20. Use `ImageConfig` signature verification against our cosign identity.
5. **Runtime overrides** (non-root UID for OpenShift SCC, resources) go in a `DeploymentRuntimeConfig` that SCO ships, not in patches to upstream.
6. **Admission is per provider** (ADR-002 rule 1), never per family. A family is admitted one member at a time, each because SCO deploys it.

## What the spike showed (2026-11-27)
Crossplane 2.5.0 and `crossplane-contrib/provider-nop` v0.6.0 on a local cluster:

- **The provider's pod runs the package image itself.** The Provider asked for `xpkg.crossplane.io/crossplane-contrib/provider-nop:v0.6.0`, and the Deployment Crossplane created runs exactly that reference, in a container named `package-runtime`.
- **The xpkg is the controller image with the package metadata added.** It has four layers: two for the runtime image, and two small ones annotated `io.crossplane.xpkg` that carry `package.yaml` (the `Provider` metadata and the CRDs). Its entrypoint is the provider binary. Its package metadata names no separate controller image.
- **Crossplane sets the pod to run as UID 2000.** OpenShift's restricted SCC rejects a fixed UID outside the namespace's range, so rule 5 below is required, not optional.

So there is no "certified runtime image plus an uncertified xpkg". There is one image, and it has to be the certified one. Whether an xpkg passes Red Hat's preflight has not been tried; nothing about it looks unusual to preflight, since it is an OCI image on a UBI base with labels, licences and a non-root user, but that is the first thing to prove.

## Open questions (all must be answered before the first xpkg; this ADR stays Proposed until then)
1. **Answered by the spike:** the pod runs the xpkg itself. ⚠️ Still to prove: that an xpkg built on our UBI runtime image passes `preflight check container`.
2. ⚠️ Does Red Hat accept Crossplane provider images as operands of a certified SCO operator? Ask our Red Hat partner contact; no public precedent found.
3. SCO's Crossplane version: is it ≥ 1.20 for `rewriteImage`?
4. Upjet providers are large (one image per family member). Measure build time and image count for one member before admitting a second.
5. Licence or terms check per provider: crossplane-contrib is Apache-2.0; check Upbound-official providers individually.
6. Which providers and functions does SCO deploy, and at which versions? The first one to build should be small and one SCO really uses.

## Consequences
- \+ One factory for MTO operands and SCO providers.
- − An xpkg adds a packaging step and a dependency-rewrite step on top of the container build.
- − Question 2, and the preflight result in question 1, can each invalidate the design. A first xpkg is built as a pull-request-only experiment before anything is promised.
