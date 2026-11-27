---
name: fix-cve
description: Resolve a vulnerability reported for a certified-images image by the CVE gate (trivy) or the scheduled re-scan. Use when a build fails the CVE gate, when asked to fix or triage a CVE in an image, or when a VEX exception is about to expire.
---

# Fix a vulnerability in an image

Read `CLAUDE.md` first if you have not. The patch SLA is in ADR-002 rule 4:
fixable CRITICAL within 7 days, fixable HIGH within 30 days, counted from the
day a fix is available.

**Check first whether the re-scan already prepared the fix.** It opens a pull
request from branch `auto/fix-<image>` for UBI-package and Go-module findings,
and an issue titled "Vulnerabilities in <image>" either way. If that pull
request exists, review it instead of redoing the work. To produce the same fix
by hand: `scripts/auto-fix.sh images/<name> <findings.jsonl>`.

Start from the scan report: `.ctx/<name>/evidence/trivy.txt` locally, or the
`evidence-<name>` artifact of the CI run. For each finding, note the package,
the installed version, the fixed version, and whether it is an OS package
(from UBI) or a language module (from upstream).

Try the options in this order. Use the first one that applies.

## 1. An OS package from the UBI base

Bump the base digest. Renovate normally does this by itself; if it has not,
update `BASE_TAG` in the Containerfile to the current digest:

```
docker buildx imagetools inspect registry.access.redhat.com/ubi9/ubi-minimal:latest
```

Never add `microdnf update` to the Containerfile. The build has no network.

## 2. A newer upstream release already has the fix

Bump `upstream.version` and `upstream.commit` in `image.yaml`, and the matching
`ARG`s in the Containerfile. Re-check admission (ADR-002 rule 1), and re-validate
every `not_affected` VEX statement for the new version. Remove any deviation
the new release makes unnecessary.

## 3. The Go standard library

Bump `GO_TAG` to a patch release of the same minor version that has the fix,
with its digest. This is a deviation only if upstream's own build uses an older
patch; say so in the PR.

## 4. A dependency upstream has not bumped — a deviation (ADR-002 rule 2)

Check upstream's default branch first. If the fix is there but unreleased, say
so; the deviation is then short-lived.

Generate a patch that touches dependency files only:

```
scripts/fetch-source.sh images/<name> .ctx/patchwork/src
docker run --rm -v "$PWD/.ctx/patchwork/src:/src" -w /src \
  -e GOFLAGS=-mod=mod -e GOTOOLCHAIN=local \
  docker.io/library/golang:<the image's GO_TAG> \
  sh -c 'git config --global --add safe.directory /src && go get <module>@<fixed-version> ...'
git -C .ctx/patchwork/src diff -- go.mod go.sum \
  > images/<name>/patches/NNNN-<short-name>.patch
rm -rf .ctx/patchwork
```

- Use `go get` for exactly the modules named in the findings. Do not run
  `go mod tidy`: it rewrites more than the fix needs.
- If patches already exist, `fetch-source.sh` has applied them, so the new
  patch is relative to them. Keep the numbering in order.
- The patch may touch `go.mod`, `go.sum` and other lockfiles only.
  `fetch-source.sh` rejects anything else, and so does ADR-003.

Record it in `image.yaml` under `deviations`: `patch`, `reason`, `fixes` (the
vulnerability IDs), `bumps`, and `upstreamPR`. Opening the upstream PR is a
human step; write `none yet` and say so in the PR description.

## 5. No fix can be applied in time — an exception (ADR-008 §6)

Only when options 1 to 4 do not apply. Add a statement to
`images/<name>/vex.openvex.json` (shape in `docs/vex-example.openvex.json`):

- `not_affected`: needs a `justification` and an `impact_statement` with
  evidence (call graph, build flag, configuration). It must name the current
  upstream version in `products`. A person must agree with the reasoning.
- `under_investigation` or `affected`: needs `x-stakater-expires`, at most 30
  days after the document timestamp.

Every statement needs `x-stakater-owner`. Never use a scanner ignore file.

## Then

Run `make verify`, open a PR, and confirm the CVE gate passes in the CI run.
In the PR description, state which option you used for each finding, and why
the earlier options did not apply.

Do not lower the gate's severity, skip the scan, or otherwise weaken the gate
to get a green run.
