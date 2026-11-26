---
name: add-image
description: Add a new upstream open-source project to the certified-images factory. Use when asked to add, admit, onboard or scaffold an image, or to certify a new upstream component. Takes the image name, the upstream GitHub owner/repo and a release tag.
---

# Add an image to the factory

Arguments: `<name> <owner/repo> <tag>`, for example `dex dexidp/dex v2.45.0`.
If any is missing, ask for it. `<name>` is a lowercase slug.

Read `CLAUDE.md` first if you have not. Work on a feature branch. Do not merge.

## 1. Admission (ADR-002 rule 1) — before any file is written

All four must hold. Check each and state the evidence. If one fails, stop and
report; do not scaffold.

| Condition | How to check |
|---|---|
| (a) No Red Hat image we are entitled to ship as an operand | Search the Red Hat Ecosystem Catalog. An image licensed only as part of another Red Hat product does not count |
| (b) Permissive licence (Apache-2.0, MIT, BSD) | Read `LICENSE` at the tag. Anything else needs legal sign-off from a person |
| (c) Upstream is maintained | A release in the last 6 months |
| (d) A Stakater product deploys it | Ask which product if it was not stated. It goes in `consumers` |

Also confirm upstream commits a lockfile (`go.sum` for Go). Without one the
image is not admitted (ADR-003).

Only Go upstreams have a template today. For another language, stop and say
that a template and a Hermeto fetcher check are needed first; that is a story.

## 2. Scaffold

```
scripts/new-image.sh <name> <owner/repo> <tag>
```

It resolves the tag to its commit and writes `images/<name>/image.yaml` and
`images/<name>/Containerfile` from `scripts/templates/go/`.

## 3. Fill in every TODO

Look at upstream's own Dockerfile and `go.mod` at the pinned tag to answer these.

In `image.yaml`:
- `summary`, `description`.
- `upstream.license`: the SPDX identifier.
- `build.prefetch`: `gomod` with the path of the module that holds `go.mod`.
- `test.command`: arguments that make the binary start and exit 0 with no
  network and no config, usually `["--help"]` or `["version"]`.
- `consumers`: the product(s) from admission (d).
- Leave `redhat.componentId` as the placeholder. A person fills it in step 6.

In the Containerfile:
- `GO_TAG`: a Go version that satisfies the `go` directive in upstream's
  `go.mod`, as `tag@sha256:digest`. Get the digest with
  `docker buildx imagetools inspect docker.io/library/golang:<version>`.
- The main package directory and any `-ldflags` upstream uses for its version.
- Labels: `summary`, `description`, `org.opencontainers.image.licenses`.
- `/licenses`: copy every licence and notice file upstream ships.
- Anything else upstream's image contains that the binary needs at run time
  (config files, templates). Do not add packages: the build has no network.
- Keep `ubi-minimal` unless the binary makes no outbound TLS connections;
  `ubi-micro` has no CA bundle (ADR-004).

## 4. Verify locally

```
make verify
```

It must pass. It rejects the scaffold until the TODOs are filled in.

## 5. Open a PR and read the CI run

The `images` workflow builds and checks the new image. Read each stage:

| Stage fails | What it means | What to do |
|---|---|---|
| Fetch | The tag does not point at the pinned commit | Re-check the tag; do not edit the commit to make it pass |
| Prefetch | Hermeto cannot resolve the dependencies | Check `build.prefetch` and that upstream has a lockfile |
| Build | Wrong package path, or a Go version older than `go.mod` needs | Fix the Containerfile. The build cannot download a toolchain |
| Image test | A label, licence file or the start-up command is wrong | Fix the Containerfile or `test.command` |
| CVE gate | Fixable CRITICAL or HIGH vulnerabilities | Use the `fix-cve` skill |
| Preflight | The image would not pass Red Hat certification | Read the failed check's name; fix the Containerfile |

Do not weaken a check to get a green run.

## 6. Hand over the human steps

State these plainly in the PR description. An agent does not do them.

1. Partner Connect → product → Add component → Container image, **UBI**,
   **Red Hat Container Registry**. Put the component ID in
   `redhat.componentId`.
2. Submit the export questionnaire for the component.
3. Add the image's two registry secrets, named by `redhat.secretSuffix`
   (`docs/setup.md`, step 6b). The Partner Connect API key is shared and
   already there.
4. A factory-team member reviews and merges. The merge publishes.

## 7. Report

Say what admission evidence you found, what the CI run showed stage by stage,
which deviations or exceptions were needed, and which human steps remain.
