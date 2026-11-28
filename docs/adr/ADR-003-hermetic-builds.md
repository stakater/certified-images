# ADR-003: Hermetic, pinned-source builds

- **Status:** Accepted. Revision 4, 2026-11-28 (decision 8: build stages in other languages, pnpm first). Earlier revisions are in `archive/`.
- **References:** Iron Bank Dockerfile requirements (no internet in the build); Konflux/Hermeto prefetch; Red Hat hermetic notebook images guidance (see `docs/references.md` §1, §3, §4)

## Context
v1 of the OpenCost Containerfile ran `git clone` and `go build` with network access inside the build. That has three problems:
- What gets built depends on the network at build time.
- The SBOM can't be trusted to list everything that went in.
- An attacker who controls a module proxy or a tag can change the build.

Iron Bank forbids internet calls inside the build. Konflux makes builds hermetic by prefetching with Hermeto.

## Decision
1. **Pin source by commit.** `image.yaml` carries `upstream.version` (tag) **and** `upstream.commit` (the SHA the tag dereferences to). CI clones the tag and **fails if `HEAD` ≠ `commit`**, which catches moved or re-pointed tags.
2. **Prefetch with Hermeto**, using the same tool Konflux uses, so ADR-007 is a lift-and-shift:
   `hermeto fetch-deps` (typed fetchers: `gomod`, `pip`, `npm`, `rpm`) → `generate-env` → `inject-files`.
   Image: `ghcr.io/hermetoproject/hermeto`, pinned by digest in the workflow (Hermeto is not on PyPI).
3. **Build with network off.** `docker build --network=none`. The source and `hermeto-output/` go into the build context; the Containerfile sources `/tmp/hermeto.env` before the toolchain runs.
4. **Typed fetchers only.** `generic` URL downloads need an ADR-level exception with sha256 pins (Red Hat's own rule).
5. **RPMs in the runtime stage.** `microdnf update` needs network, so the runtime stage takes base-image updates through **Renovate digest bumps** (ADR-004) instead of in-build updates. Adding RPMs later means Hermeto's `rpm` fetcher with an `rpms.lock.yaml`, not `microdnf install` from the internet.
6. **Apply recorded deviations, and nothing else.** ADR-002 rule 2 allows a dependency bump to fix a vulnerability. Such a change is a patch file in `images/<name>/patches/*.patch`, listed in `image.yaml`. CI applies the patches after the pinned clone (step 1) and before the prefetch (step 2), and **fails if a patch touches any file other than dependency manifests and lockfiles** (`go.mod`, `go.sum`, `requirements*.txt`, `package.json`, `package-lock.json`). A toolchain bump needs no patch: it is the toolchain version in `image.yaml`.
7. **An upstream's vendored dependencies are dropped, when the image says so.** Some Go upstreams commit a `vendor/` directory. Hermeto regenerates it and rejects the source if the result differs at all, and it does differ for upstreams that gitignore files inside it (seen 2026-11-28 with `gardener/etcd-wrapper` and `gardener/etcd-backup-restore`: only added non-code files, `CLAUDE.md` and a `.swp` file, no modified file). For such an image, `image.yaml` sets `build.dropVendor: true`. CI then removes `vendor/` after the patches (step 6) and before the prefetch (step 2). Dependencies come from Hermeto at the versions and hashes in `go.sum`, as for every other image. It **fails if the image declares it and the source has no `vendor/modules.txt`**, so a stale declaration is noticed. Hermeto's permissive mode is not used: it would turn the same check into a warning for every difference, including a modified file.
8. **A build may have stages in another language, under the same rules.** Prometheus' web UI is JavaScript built with pnpm and compiled into the Go binary. Such a part is built from source in its own stage of the Containerfile, not taken from upstream's prebuilt artifact (that would be re-shipping a binary we did not build, ADR-002 rule 2, and a `generic` download, decision 4). The rules do not change: its dependencies are listed in `build.prefetch` with Hermeto's typed fetcher for that package manager (`pnpm` here, one entry per lockfile), the stage runs with the network off, and its toolchain images are pinned by digest like the Go toolchain (ADR-004). Tried 2026-11-28 with Hermeto 0.64.0: the `pnpm` fetcher prefetches both of Prometheus' lockfiles and the UI builds with no network. Known limits, each a reason to stop and not to loosen: pnpm 12 refuses the lockfile Hermeto rewrites, so pnpm is held at 11.x; a package manager Hermeto has no typed fetcher for is not admitted.

## Consequences
- \+ Reproducible inputs; the dependency SBOM comes from Hermeto (ADR-008).
- \+ Same mechanics on GitHub Actions and Konflux.
- − Each language needs its lockfile (`go.sum`, `requirements*.txt`, `package-lock.json`). An upstream without a committed lockfile is **not admitted**: generating one would be a patch outside the two deviations ADR-002 rule 2 allows.
- − Patches are a second input to the build. They are limited to dependency files, so the source we compile is still upstream's.
- − `ca-certificates` and other runtime RPM updates arrive only via base-digest bumps. These are frequent and automerged, so this is acceptable.
- − With `build.dropVendor`, we compile the modules `go.sum` names, not the bytes upstream committed under `vendor/`. They are the same unless upstream edited a vendored file by hand, which `go.sum` would not show. Before setting it for an image, run the prefetch once without it and confirm Hermeto reports only added files; record that in the image's `image.yaml`. ⚠️ No reference in `docs/references.md` does exactly this (ADR-002 rule 7): Hermeto and Konflux document the consistency check, not dropping the directory.
- − A second toolchain per such image: for Prometheus, a Node image and a pnpm image, both to keep current, and a version ceiling on pnpm that someone must lift. More build inputs than a Go-only image, all pinned.

## Not doing
- Vendoring upstream source into this repo (a mirror maintenance burden; Iron Bank declares sources instead).
- GitHub archive tarballs + sha256. They are less robust than commit pins: archives are generated on demand and have changed checksums in the past. ⚠️ From experience, not re-verified.
