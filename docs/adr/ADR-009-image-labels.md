# ADR-009: Image labels

- **Status:** Proposed (accepted when its PR merges, per ADR-001)
- **Date:** 2026-11-26
- **References:** OCI image-spec pre-defined annotations ✅; Red Hat preflight `HasRequiredLabel` and `HasNoProhibitedLabels` (source read ✅); the labels on Red Hat's own images (`ubi9/go-toolset`, inspected ✅) and on Chainguard's (`cgr.dev/chainguard/static`, inspected ✅). See `docs/references.md` §9.

## Context
Our first staged image passed Red Hat's required-label check and still carried labels that were wrong. A final image inherits every label of its base unless it overrides it, so ours said:

- `build-date` and `org.opencontainers.image.created`: the day **UBI** was built, not our image;
- `vcs-ref`: a commit in **Red Hat's** repository;
- `url`: Red Hat's catalog search page;
- `io.openshift.tags`: `minimal rhel9`.

Our own labels had a second problem. `org.opencontainers.image.source` named upstream's repository. The OCI spec defines it as the "URL to get source code for building the image", which is this repository. Chainguard and Red Hat both point it, and the revision beside it, at the repository that builds the image.

Labels are how a person or a scanner answers "what is this, who built it, from what, and when". Wrong answers are worse than none.

## Decision
Every image sets the labels below. `scripts/check-labels.sh` enforces them on the built image, and `scripts/check-image.sh` requires the Containerfile to declare them.

### 1. Red Hat required (preflight fails without them)
| Label | Value |
|---|---|
| `name` | `stakater/<name>` |
| `vendor` | `Stakater AB` |
| `maintainer` | `Stakater AB <support@stakater.com>` |
| `version` | upstream version |
| `release` | the release number (ADR-002 rule 3) |
| `summary`, `description` | from `image.yaml` |

`name`, `vendor` and `maintainer` must not use Red Hat's trademarks (preflight checks exactly these three).

### 2. What built it: this repository
| Label | Value |
|---|---|
| `org.opencontainers.image.source` | `https://github.com/stakater/certified-images` |
| `org.opencontainers.image.revision`, `vcs-ref` | the commit of **this repository** that built the image |
| `vcs-type` | `git` |
| `org.opencontainers.image.created`, `build-date` | when the image was built, RFC 3339 |
| `org.opencontainers.image.url`, `url` | `https://github.com/stakater/certified-images/tree/main/images/<name>` |

`source` and `revision` are a pair: the revision is a commit in the source repository. Red Hat's images set `revision` equal to `vcs-ref` for the same reason.

### 3. What is inside: the upstream project
| Label | Value |
|---|---|
| `org.opencontainers.image.version` | upstream version |
| `org.opencontainers.image.licenses` | upstream licence, SPDX |
| `com.stakater.upstream.repo` | upstream repository URL |
| `com.stakater.upstream.version` | upstream tag |
| `com.stakater.upstream.commit` | the pinned upstream commit |

The upstream commit gets our own namespace because no standard key means "the commit of the software inside, as distinct from the commit that built the image".

### 4. What it is based on
| Label | Value |
|---|---|
| `org.opencontainers.image.base.name` | e.g. `registry.access.redhat.com/ubi9/ubi-minimal` |
| `org.opencontainers.image.base.digest` | the pinned base digest |

### 5. Descriptive
| Label | Value |
|---|---|
| `org.opencontainers.image.title` | "Stakater build of <Project>" |
| `org.opencontainers.image.description` | same as `description` |
| `org.opencontainers.image.vendor` | `Stakater AB` |
| `io.k8s.display-name`, `io.k8s.description` | as title and description |
| `io.openshift.tags` | from `image.yaml` `tags`, comma separated |

### 6. Inherited from UBI and left alone
`architecture`, `com.redhat.component`, `com.redhat.license_terms`, `cpe`, `distribution-scope`, `io.buildah.version`, `io.openshift.expose-services`.

These describe the base layer, and some are in Red Hat's own namespace. ⚠️ We do not know whether Red Hat's catalog or scanners read `cpe` or `com.redhat.component` from a partner image, so we do not overwrite them. Red Hat's partner labelling guidance could not be read (the documentation site refused automated access); ask our partner contact, then revise this section.

## Consequences
- \+ An image answers "who built this, from which commit of which repo, on what base, when" correctly, in the keys tools already read.
- \+ `revision` pointing at this repository means GitHub can link a package to the commit that built it.
- − The build date and the build commit change on every build, so two builds of the same inputs no longer have the same digest. Red Hat's and Chainguard's images accept the same trade-off. We do not claim bit-for-bit reproducible images.
- − Images staged before this ADR keep their old labels. The next release of each has the new ones.

## Not doing
- Removing inherited labels. A Containerfile can only set a label, not delete one.
- `org.opencontainers.image.documentation` and `.authors`: nothing reads them for us yet.
