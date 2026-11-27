# Reference implementations (prior art)

Rule: **we copy proven patterns; we do not invent.** Every ADR in `docs/adr/` names the reference it follows. If a decision has no reference, say so explicitly in the ADR and treat it as a risk.

Status key: ✅ verified against the source (2026-11-25) · ⚠️ from experience, verify before relying on it.

## 1. Iron Bank (US DoD Platform One) — closest analogue
What it is: a public pipeline that rebuilds/hardens upstream OSS onto approved bases (incl. UBI) and publishes with a body of evidence.

| What we copy | Where | Used in |
|---|---|---|
| Per-image repo layout: one `Dockerfile` + `hardening_manifest.yaml` (sources, labels, maintainers) | docs-ironbank.dso.mil/hardening/manifest ✅ | ADR-002 `image.yaml` |
| `ARG BASE_REGISTRY / BASE_IMAGE / BASE_TAG` in every Containerfile so the pipeline can swap the base | docs-ironbank.dso.mil/hardening/dockerfile-requirements ✅ | ADR-004 |
| No network calls inside the build; sources declared up front | same page ✅ | ADR-003 |
| Product grouping label (`mil.dso.ironbank.product.name`) | manifest docs ✅ | `image.yaml consumers` |
| Only the hardening team merges to the publishing branch | docs-ironbank.dso.mil/quickstart/pipeline ✅ | ADR-002 governance (CODEOWNERS) |
| Findings justification tracker (VAT) | docs-ironbank.dso.mil/quickstart/components ✅ | ADR-008 (VEX exceptions) |

Read: https://repo1.dso.mil/dsop (real image repos), https://repo1.dso.mil/ironbank-tools/ironbank-pipeline (pipeline + manifest JSON schema).
Don't copy: GitLab-specific pipeline, DoD accreditation process.

## 2. OpenShift ART / ocp-build-data — how Red Hat rebuilds upstream
| What we copy | Where | Used in |
|---|---|---|
| Build metadata lives in a **separate repo** from source | github.com/openshift/ocp-build-data ✅ | ADR-002 (this repo) |
| Upstream repos carry a second build file (`Dockerfile.rhel`) for the productised build | docs.ci.openshift.org/architecture/images ✅ | ADR-006 (`Containerfile.ubi` in Stakater-owned repos) |
| Example repo shape | github.com/OpenShiftART/image-upstream-example ✅ | ADR-006 |

Don't copy: Brew/OSBS internals (Red Hat-only).

## 3. Konflux (Red Hat, Apache-2.0) — target build platform
| What we copy | Where | Used in |
|---|---|---|
| Tekton + Tekton Chains + Conforma + Hermeto + Quay; SLSA Build L3 provenance | redhat.com blog "zero CVEs symptom of a larger problem" ✅; konflux SLSA docs ✅ | ADR-007 |
| (GitHub, not Konflux) Build L3 route on GitHub Actions: artifact attestations generated inside a reusable workflow; verify with `gh attestation verify --signer-workflow` | docs.github.com "Using artifact attestations and reusable workflows to achieve SLSA v1 Build Level 3" ✅ (2026-11-25) | ADR-006, ADR-007 |
| Hermetic build = prefetch with Hermeto, then build with network off | konflux-ci.dev prefetching docs ✅ | ADR-003 |
| Conforma (Enterprise Contract) policy gates before release | ⚠️ verify policy bundle names when we migrate | ADR-007/008 |

Docs: https://konflux-ci.dev · https://github.com/konflux-ci

## 4. Hermeto (ex-Cachi2) — dependency prefetch
| What we copy | Where | Used in |
|---|---|---|
| `fetch-deps` → `generate-env` → `inject-files` → build with `--network none` | hermetoproject.github.io/hermeto/latest ✅ | ADR-003, workflow |
| Distributed as container `ghcr.io/hermetoproject/hermeto` (not on PyPI) | same ✅ (checked: no PyPI package) | workflow |
| Prefetch also emits an SBOM of dependencies | Konflux docs ✅ | ADR-008 |
| Prefer typed fetchers (gomod, pip, npm, rpm) over `generic` URL downloads | Red Hat Developer, hermetic notebook images ✅ | ADR-003 |

Using Hermeto now, in GitHub Actions, means the Konflux migration (ADR-007) does not change how dependencies are fetched.

## 5. Chainguard (melange/apko) — cadence and SBOM quality
| What we copy | Where | Used in |
|---|---|---|
| Rebuild continuously on upstream/base updates, not on a schedule | github.com/chainguard-dev/apko ✅ | ADR-002 patch SLA, Renovate |
| SBOM produced by the build, not by a later scan | chainguard.dev "Super SBOMs" ✅ | ADR-008 |
| Every image signed (Sigstore) with SBOM + SLSA provenance attestations | edu.chainguard.dev retrieve-image-sboms ✅ | ADR-008 |

Don't copy: apko/Wolfi as the runtime base. Red Hat certification needs UBI.

## 6. Crossplane packaging (for SCO wrappers)
| What we copy | Where | Used in |
|---|---|---|
| Provider = xpkg (OCI) containing `package.yaml`; Crossplane installs CRDs then a Deployment from the controller image | github.com/crossplane/crossplane issue #2671 ✅ | ADR-005 |
| `crossplane xpkg build --embed-runtime-image(-tarball)` embeds our UBI controller image in the package | docs.crossplane.io/v2.1/cli/command-reference ✅ (flags exist). The provider pod runs the xpkg itself ✅ (observed 2026-11-27 with Crossplane 2.5.0 and provider-nop v0.6.0; ADR-005) | ADR-005 |
| Official reusable GitHub workflow for publishing provider/function packages | docs.crossplane.io/v2.4/guides/extensions-release-process ✅ | ADR-005 |
| `ImageConfig` (`pkg.crossplane.io/v1beta1`): prefix match, pull secrets, signature verification, `rewriteImage.prefix` for mirrors | docs.crossplane.io/v2.x/packages/image-configs ✅ (rewrite since 1.20; ImageConfig since 1.18, backported 1.16.4/1.17.3) | ADR-005 air-gap |
| `DeploymentRuntimeConfig` to override controller Deployment settings | crossplane design one-pager package-runtime-config ✅ | ADR-005 |
| Upbound UXP as a commercial Crossplane distribution | upbound.io blog "UXP 2.0" ✅ | positioning only |

⚠️ Check: SCO's Crossplane version is ≥ 1.20 (needed for `rewriteImage`). Check whether Upbound providers' licences or terms limit redistributing rebuilt packages (crossplane-contrib providers are Apache-2.0; verify per provider).

## 7. Red Hat certification sources (our constraints)
- OpenShift Software Certification Policy Guide: docs.redhat.com/en/documentation/red_hat_software_certification ✅
- Preflight: github.com/redhat-openshift-ecosystem/openshift-preflight ⚠️ verify the `--certification-component-id` flag name on the pinned preflight version (older releases used `--certification-project-id`).

## 8. Staging and promotion, and running the image (added 2026-11-26)
| What we copy | Where | Used in |
|---|---|---|
| Build once, then **promote the same digest** between registries by copying the manifest, never by rebuilding | Common release practice; `crane copy` / `skopeo copy`. ⚠️ No single source cited: Konflux's release pipelines and Iron Bank's staging-to-production promotion work this way, from experience | ADR-002 rev 5, `scripts/copy-image.sh` |
| Push to GHCR from a workflow with `GITHUB_TOKEN` and `packages: write` | GitHub Packages docs ✅ (ran 2026-11-26) | ADR-002 rev 5 |
| Kubernetes **Pod Security Standards, `restricted`**, enforced by a namespace label, as the portable stand-in for OpenShift's `restricted-v2` SCC | kubernetes.io Pod Security Standards ⚠️ equivalence is close, not exact: SCC UID ranges and SELinux are not covered | `scripts/smoke-test.sh` |
| kind for a throwaway cluster in CI | kind.sigs.k8s.io ✅ (ran 2026-11-26) | `scripts/smoke-kind.sh` |
| A check must be shown to fail: negative fixtures beside every gate | Our own rule (docs/method.md), not copied | `tests/`, `make test-hermetic`, `make test-smoke` |

## 9. Image labels (added 2026-11-26)
| What we copy | Where | Used in |
|---|---|---|
| The 14 pre-defined keys and their meanings. `source` is the "URL to get source code for building the image" | OCI image-spec `annotations.md` ✅ | ADR-009 |
| Required labels `name`, `vendor`, `version`, `release`, `summary`, `description`, `maintainer`; trademark check on `name`, `vendor`, `maintainer` | preflight `has_required_labels.go`, `has_prohibited_labels.go` ✅ (source read) | ADR-009 §1 |
| `build-date`, `vcs-ref`, `vcs-type`, `url`, `io.k8s.*`, `io.openshift.tags`, and `org.opencontainers.image.revision` equal to `vcs-ref` | Labels on `registry.access.redhat.com/ubi9/go-toolset` ✅ (inspected) | ADR-009 §2, §5 |
| `source` pointing at the directory that builds the image; `created`, `title`, `url`, `vendor`, `authors` | Labels on `cgr.dev/chainguard/static` ✅ (inspected) | ADR-009 §2, §5 |

Not readable: Red Hat's partner labelling guidance (docs.redhat.com refused automated access) and Iron Bank's label requirements (site unreachable). ⚠️ ADR-009 §6 depends on the first.

## Gaps: decisions with no reference (flagged as risk)
- Partner Connect component per image, and export questionnaire batching. Red Hat process; no public prior art.
- Using one `image.yaml` for container and xpkg kinds is our own schema.
- The release counter (`next-release.sh`) reads the staging registry's tags. Modelled on the RPM release field; the mechanism is ours.
- The pipeline is shell scripts called from GitHub Actions, not Konflux's Tekton tasks. Deliberate (ADR-007), and the part of the factory with the least prior art behind it.
- OpenVEX with our own `x-stakater-owner` and `x-stakater-expires` fields.
- **Things the reference systems do that we do not yet:** continuous re-scan of published images (Iron Bank, Chainguard); a policy gate on release (Konflux's Conforma); building with Red Hat's own Go toolchain (`ubi9/go-toolset`) as Red Hat does; a label policy (see Red Hat's container image guidelines), where today we inherit several of UBI's labels unchanged. Keep it close to Iron Bank's manifest fields to limit invention.
