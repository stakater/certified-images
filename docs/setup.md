# First-time setup and first publish

What a person has to do, in order, to take the factory from "builds on pull
requests" to "publishes certified images". Steps 1 to 3 are once per
repository. Steps 4 to 9 are once per image.

Nothing here can be done by an agent: it needs repository admin rights, a Red
Hat Partner Connect login, or a credential.

**Rule for every secret below:** type or paste the value only into GitHub's
secret form or the `gh secret set` prompt. Never into a file, a commit, a PR,
an issue or a chat.

## Overview

| # | Step | Who | Where | Once per |
|---|---|---|---|---|
| 1 | Merge the open pipeline PRs | Factory owner | GitHub | repo |
| 2 | Enable Renovate | Repo admin | GitHub | repo |
| 3 | Protect `main`, add `CODEOWNERS` | Repo admin | GitHub | repo |
| 4 | Create the component, get its ID | Partner Connect user | Red Hat Partner Connect | image |
| 5 | Submit the export questionnaire | Partner Connect user | Red Hat Partner Connect | image (can be batched) |
| 6 | Add the three secrets | Repo admin | GitHub | image |
| 7 | Set the component ID in `image.yaml`, merge | Factory team | GitHub | image |
| 8 | Check the publish run and Partner Connect | Factory team | GitHub, Partner Connect | publish |
| 9 | Verify from outside CI, record the result | Factory team | Your own machine | first publish |

Do step 6 before step 7. The merge in step 7 is what publishes; if the secrets
are missing, the run fails at the registry login.

## 1. Merge the pipeline

The publish workflow must be on `main` before anything else matters. Merging it
publishes nothing: an image is only published once it has a component ID.

## 2. Enable Renovate

Install the Renovate GitHub app on `stakater/certified-images`.

Then read its first "Dependency Dashboard" issue and check that it lists:

- the UBI base digest and the Go toolchain digest in each Containerfile;
- each image's upstream version (in `image.yaml` and the Containerfile);
- the tool images in `tools.env`.

⚠️ The Renovate config validates but has never run. If one of these is missing
from the dashboard, a regex manager in `renovate.json` does not match; open an
issue with what is missing.

## 3. Protect `main`

In Settings → Branches (or Rulesets), for `main`:

- Require a pull request, and review from Code Owners.
- Require the status check `verify`.
- Do **not** require the `image (...)` checks unless skipped checks are allowed:
  that workflow only runs when images, scripts or workflows change.
- Allow the Renovate bot to merge without review. ADR-002 rule 6 limits its
  automerge to UBI base-digest bumps.

Add `.github/CODEOWNERS` through a PR, with the factory team's handle:

```
/images/   @stakater/<factory-team>
/.github/  @stakater/<factory-team>
/scripts/  @stakater/<factory-team>
```

Recommended: Settings → Environments → create `publish` with required
reviewers. ⚠️ The workflow does not use an environment yet; say when you have
created one and the publish job will be put behind it.

## 4. Create the Partner Connect component

In Red Hat Partner Connect, under the Stakater product the image ships with:

1. Add component → **Container image**.
2. Base image: **Red Hat Universal Base Image (UBI)**.
3. Distribution: **Red Hat Container Registry**.
4. Name it after the image, e.g. `opencost`. It will be published as
   `stakater/<name>`.

Copy the **component ID** from the component's URL or overview page. It is 24
hexadecimal characters. It is an identifier, not a secret.

## 5. Export questionnaire

Submit the export compliance questionnaire for the component. Several new
components can go in one submission (ADR-002 rule 5). Certification does not
complete without it.

## 6. Add the secrets

Each image needs three secrets. Their names end in the image's
`redhat.secretSuffix` from `image.yaml`. For `opencost` the suffix is
`OPENCOST`.

| Secret name | What it is | Where to get it ⚠️ |
|---|---|---|
| `RH_REGISTRY_USER_OPENCOST` | Registry username for this component. It looks like `redhat-isv-containers+<componentId>-robot` | Partner Connect → the component → Images → "Push image manually" |
| `RH_REGISTRY_PASSWORD_OPENCOST` | The registry key shown next to that username | Same page |
| `RH_PYXIS_TOKEN_OPENCOST` | Partner Connect API key, used to submit certification results | Partner Connect → account → API keys → generate |

⚠️ The page names are from memory of Partner Connect's layout and may have
moved. The three values are what matters.

If the API key turns out to be one per partner account and not per component,
add it once as `RH_PYXIS_TOKEN` (no suffix) and skip the per-image one. The
workflow uses the suffixed secret if it exists and falls back to the shared one.

**Where they go:** GitHub → `stakater/certified-images` → Settings → Secrets
and variables → Actions → **Repository secrets** → New repository secret.
Not environment secrets, not Dependabot secrets, not variables.

Or from a terminal. Each command prompts for the value, so it never appears in
your shell history:

```
gh secret set RH_REGISTRY_USER_OPENCOST     --repo stakater/certified-images
gh secret set RH_REGISTRY_PASSWORD_OPENCOST --repo stakater/certified-images
gh secret set RH_PYXIS_TOKEN_OPENCOST       --repo stakater/certified-images
```

Check they exist (this lists names only):

```
gh secret list --repo stakater/certified-images
```

## 7. Set the component ID and merge

Open a PR that changes one line in `images/<name>/image.yaml`:

```yaml
redhat:
  componentId: "<the 24-hex component ID>"
```

`make verify` checks the format. The PR's CI run still publishes nothing. When
the PR is merged, the `publish` workflow runs for that image. **This merge is
the publish.**

## 8. Check the publish run

In GitHub → Actions → `publish`, the run's summary shows the tag
(`<upstream-version>-1` the first time) and the digest reference.

| It fails at | Likely cause |
|---|---|
| "Log in to Red Hat's partner registry" | A registry secret is missing, misnamed or wrong |
| "Release number" | The registry refused to list tags. Check the robot account can read the repository |
| "Sign the digest and attest the SBOMs" | The job lacks `id-token: write`, or Sigstore was unreachable |
| "Submit to Red Hat for certification" | The API key is missing or wrong, the component ID is wrong, or the image failed a certification check (the log names it) |

A failed run can be re-run. A re-run after a successful push takes the next
release number.

Then in Partner Connect: the component's Images tab should show the image, its
certification test results, and a health grade. Publish it there if it is not
set to publish automatically.

## 9. Verify from outside CI

On your own machine, with `cosign` and `gh` installed, run the commands in the
README's "Verify (customers)" section against the **public** pull spec
(`registry.connect.redhat.com/stakater/<name>@sha256:<digest>`).

Record in the PR or an issue, for each command: passed or failed, and the
output if it failed. This answers ADR-008 open question 1 (are signatures
reachable from the public registry?). Whatever the answer, it is then written
into ADR-008 and the README.

After that, the consuming product pins the digest in its CSV `relatedImages`
(story P.3).

## For the next image

Steps 4 to 9 again, with that image's suffix. Steps 4 and 5 can start as soon
as the image is admitted; they do not depend on its PR.
