# ADR-005: Artifact kinds: container and Crossplane xpkg (SCO wrappers)

- **Status:** Proposed (container implemented; xpkg designed, not built). Edited 2026-11-25 during review, before first acceptance.
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
| `xpkg` | (1) UBI runtime image, built like `container`, **plus** (2) an xpkg rebuilt from upstream's `package/` dir so that it runs our runtime image | See open question 1 | Follows Crossplane's official reusable publish workflow |

OLM bundles for Stakater-owned operators are **not** a kind here. They are built in the product repo (ADR-006), so this repo's schema does not carry them.

Wrapper rules for `xpkg`:
1. **Same upstream commit** for the runtime image and `package/` (one `upstream.commit`).
2. Package name `stakater/<provider>`, e.g. `stakater/provider-kubernetes`. Keep upstream CRD API groups unchanged: forking API groups is a permanent incompatibility.
3. **Dependencies in `crossplane.yaml`** (e.g. family providers depending on `provider-family-*`) are rewritten to our package names in the same PR. CI fails on any remaining upstream registry reference.
4. **Air gap:** customers mirror our packages and set an `ImageConfig` with `matchImages` (prefix) + `rewriteImage.prefix` to their mirror. This requires Crossplane ≥ 1.20. Use `ImageConfig` signature verification against our cosign identity.
5. **Runtime overrides** (non-root UID for OpenShift SCC, resources) go in a `DeploymentRuntimeConfig` that SCO ships, not in patches to upstream.
6. **Admission is per provider** (ADR-002 rule 1), never per family. A family is admitted one member at a time, each because SCO deploys it.

## Open questions (all must be answered before the first xpkg; this ADR stays Proposed until then)
1. ⚠️ **Which image does the provider pod actually run?** With `crossplane xpkg build --embed-runtime-image(-tarball)`, the runtime is embedded in the package. If the pod then runs the xpkg image itself, the Red Hat-certified runtime digest is never the image that runs, and "runtime certified, xpkg signed only" does not satisfy the operand rule. The alternative is a package that references the certified image by digest instead of embedding it. Checked against the Crossplane docs on 2026-11-25: the flags are documented, the pod's image source is not. Settle it by building one provider both ways on a test cluster and reading the pod spec.
2. ⚠️ Does Red Hat accept Crossplane provider runtime images as operands of a certified SCO operator? Ask our Red Hat partner contact; no public precedent found.
3. SCO's Crossplane version: is it ≥ 1.20 for `rewriteImage`?
4. Upjet providers are large (one image per family member). Measure build time and image count for one member before admitting a second.
5. Licence or terms check per provider: crossplane-contrib is Apache-2.0; check Upbound-official providers individually.

## Consequences
- \+ One factory for MTO operands and SCO providers.
- − xpkg adds a second artifact per image and a dependency-rewrite step.
- − Questions 1 and 2 can each invalidate the xpkg design. No xpkg work starts before they are answered.
