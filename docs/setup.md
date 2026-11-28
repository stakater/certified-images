# First-time setup and first publish

What a person has to do, in order, to take the factory from "builds on pull
requests" to "publishes certified images". Steps 1 to 3 and 6a are once per
repository. The rest are once per image.

Staging to GHCR needs none of the Red Hat steps: it works as soon as the
pipeline is merged (step 1) and is checked in step 1a. Steps 4 to 9 are only
for publishing to Red Hat.

Nothing here can be done by an agent: it needs repository admin rights, a Red
Hat Partner Connect login, or a credential.

**Rule for every secret below:** type or paste the value only into GitHub's
secret form or the `gh secret set` prompt. Never into a file, a commit, a PR,
an issue or a chat.

## Overview

| # | Step | Who | Where | Once per |
|---|---|---|---|---|
| 1 | Merge the open pipeline PRs | Factory owner | GitHub | repo |
| 1a | Run the first staging publish, check the GHCR package | Factory owner, org admin | GitHub | repo, then each new image |
| 2 | Enable Renovate | Repo admin | GitHub | repo |
| 3 | Protect `main`, add `CODEOWNERS` | Repo admin | GitHub | repo |
| 4 | Create the component, get its ID | Partner Connect user | Red Hat Partner Connect | image |
| 5 | Submit the export questionnaire | Partner Connect user | Red Hat Partner Connect | image (can be batched) |
| 6a | Add the shared API key `RH_PYXIS_TOKEN` | Repo admin | GitHub | repo |
| 6b | Add the component's registry key to the shared `RH_REGISTRY_KEYS` secret | Repo admin | GitHub | image (one entry) |
| 7 | Set the component ID in `image.yaml`, merge | Factory team | GitHub | image |
| 8 | Check the publish run and Partner Connect | Factory team | GitHub, Partner Connect | publish |
| 9 | Verify from outside CI, record the result | Factory team | Your own machine | first publish |
| 10 | Add the Slack webhook `SLACK_WEBHOOK_URL`; optionally subscribe the channel to `upstream-bump` pull requests | Slack admin, repo admin | Slack, GitHub | repo |

Steps 6 and 7 can be done in either order. If the component ID is set but
`RH_PYXIS_TOKEN` or the component's registry key is missing, the run stages
the image to GHCR, skips the Red Hat stage and says what is missing. The first run with both in place publishes to
Red Hat.

## 1. Merge the pipeline

The publish workflow must be on `main` before anything else matters. Merging it
publishes nothing: an image is only published once it has a component ID.

## 1a. First staging publish to GHCR

No secrets are needed: the workflow uses its own token.

1. GitHub → Actions → `publish` → Run workflow → image `opencost`. Or merge
   any change that touches the image.
2. The run's summary shows the staged reference,
   `ghcr.io/stakater/ubi/opencost@sha256:…`, tagged `<upstream-version>-1`.
3. **Check the package's visibility matches what the image declares.** Each
   `image.yaml` declares its staging visibility; private is the default
   (ADR-002 rev 6). This repository is public, so a package it creates is
   **public by default**, whatever the image declares. As an organisation admin:
   - Once, for all future images: Organisation settings → Packages → Package
     creation → untick **Public**. New packages are then created private, and
     an image declared public is made public by hand when it is first staged.
   - For a package that should be private and is not: Packages → `ubi/<name>`
     → Package settings → Change visibility → **Private** or **Internal**, then
     give the teams that need it read access.

   The pipeline checks this itself (`scripts/assert-visibility.sh`): it asks
   the registry with no credentials, before and after each staging push, and
   fails the run if a package is public without its image declaring it. It
   cannot prevent a brand-new package from being created public; the
   organisation setting does. Until that setting is changed, **the first push
   of any private image will expose it** until the run fails a moment later.
4. Verify from your own machine with the README's commands. For a private
   image, first `docker login ghcr.io` with a token that has `read:packages`.

| It fails at | Likely cause |
|---|---|
| "Stage to GHCR" or "Staged package is not more open than declared", saying the package is PUBLIC | The package is public but its `image.yaml` does not declare that. Make it private as in step 3, or declare it public in a reviewed PR, then re-run |
| "Stage to GHCR", with a permission error | The organisation does not let workflows create packages, or the package already exists and is not linked to this repository. An org admin grants this repository write access in the package's settings |
| "Sign and attest the staged image" | The job lacks `id-token: write`, or Sigstore was unreachable |

To pull a private staged image into a cluster, the cluster needs a pull secret
for `ghcr.io` with `read:packages`. A public one needs none. Staged images are for testing; nothing shipped
to a customer references them.

## 2. Enable Renovate

Install the Renovate GitHub app on `stakater/certified-images`.

Then read its first "Dependency Dashboard" issue and check that it lists:

- the UBI base digest and the Go toolchain digest in each Containerfile;
- each image's upstream version (in `image.yaml` and the Containerfile);
- the tool images in `tools.env`.

⚠️ The Renovate config validates but has never run. If one of these is missing
from the dashboard, a regex manager in `renovate.json` does not match; open an
issue with what is missing.

## 2a. Let the re-scan open pull requests

Settings → Actions → General → Workflow permissions → tick **"Allow GitHub
Actions to create and approve pull requests"**. Without it the daily re-scan
still opens its issue and pushes the fix branch `auto/fix-<image>`, but cannot
open the pull request, and says so in the run.

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

**Create new components as Red Hat-hosted (setup A).** That is the route that has
been seen to deliver an image to a customer. The choice is made when the
component is created and, as far as we know, cannot be changed afterwards. The
sign you got it right: the component's "Set up Preflight" page shows a
registry login. Its key goes into `RH_REGISTRY_KEYS` (step 6b).

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

**One secret for the whole repository, however many images there are**, and a
second only if some component is hosted by Red Hat. No secret is named per
image (ADR-002 rev 8).

| Secret | Needed for | What it is |
|---|---|---|
| `RH_PYXIS_TOKEN` | every component | Partner Connect (Pyxis) API key. Submits certification results |
| `RH_REGISTRY_KEYS` | only components Red Hat hosts (setup A) | Those components' registry keys, as one JSON object |

A component Red Hat lists while we host the image (setup B) needs no registry
key: skip step 6b for it. `docs/red-hat-distribution.md` explains the setups.

### 6a. `RH_PYXIS_TOKEN` — once

Partner Connect → account → API keys → generate. ⚠️ Page name from memory.

One key covers every component: the key belongs to a Partner Connect account,
and the component is chosen by the ID the pipeline passes to preflight.

**Create it from a dedicated Stakater certification account, not a personal
one.** The key is tied to the user who creates it. If that person's account
changes, or the key is revoked, every publish fails at "Submit to Red Hat".

**Rotation.** Generate a new key from the same account, run
`gh secret set RH_PYXIS_TOKEN` again, re-run the failed publish. Nothing in the
repository changes. Record who holds the account and when the key was last
rotated wherever the team keeps its runbooks.

### 6b. `RH_REGISTRY_KEYS` — only for components Red Hat hosts

A Red Hat-hosted component (setup A) has its own repository on Red Hat's
registry and its own registry key. You can tell which kind a component is from
its "Set up Preflight" page: setup A shows a registry login, setup B shows
none. The pipeline keeps all setup A keys in one secret:

```json
{
  "6af9776fa950dc6dbfa4d693": { "name": "reloader-operator", "key": "<registry key>" },
  "6b07595f3ecfc52e21d75e12": { "name": "opencost",          "key": "<registry key>" }
}
```

- Each entry is filed under the **component ID** from `image.yaml`. That is
  what the pipeline looks up.
- **`name`** is the image's name (its directory under `images/`). It is there
  so a person can read the secret, and the pipeline checks it: if the entry
  found for a component names a different image, the run stops without logging
  in. That catches a key pasted under the wrong component.
- **`key`** is that component's registry key, from Partner Connect → the
  component → "Set up Preflight" / "Push image manually". ⚠️ Page name from
  memory.
- The **username is not stored**. The pipeline derives it:
  `redhat-isv-containers+<componentId>-robot`. ⚠️ That is the format in Red
  Hat's push instructions as remembered; the first real login confirms it.

To add an image later: add one entry and set the secret again. GitHub cannot
show you a secret's current value, so **keep the full JSON in the team's
password manager** and paste the whole object each time.

An image whose component has no entry is not an error: the run stages it to
GHCR, skips the Red Hat stage, and names the missing component ID.

### 6c. Why `RH_REGISTRY_KEYS` cannot be fetched instead

Checked on 2026-11-26 with a working API key, using the `pyxis-probe` workflow
against the Reloader component. Red Hat's API has a per-component `/secrets`
endpoint, and the key may call it, but it holds one field,
`docker_config_json`, and it was empty. Nothing in the component record or in
that endpoint carries the registry key Red Hat issues for pushing. So the key
has to be copied from Partner Connect once per component, into this one secret.

⚠️ Read of that field: it looks like a credential a partner *gives* Red Hat,
for pulling from the partner's own registry, not one Red Hat hands out. That
interpretation is from memory of Red Hat's pipeline, not from their docs.

The probe stays useful: it shows a component's settings as Red Hat has them
(name, status, base type, repository name), which is the quickest way to check
a new component was created correctly.

GitHub → Actions → `pyxis-probe` → Run workflow → the image name.

### Where they go

GitHub → `stakater/certified-images` → Settings → Secrets and variables →
Actions → **Repository secrets** → New repository secret. Not environment
secrets, not Dependabot secrets, not variables.

Or from a terminal. Each command prompts for the value, so it never appears in
your shell history:

```
gh secret set RH_PYXIS_TOKEN   --repo stakater/certified-images
gh secret set RH_REGISTRY_KEYS --repo stakater/certified-images
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
the PR is merged, the `publish` workflow runs for that image: it stages to
GHCR, and if the secrets from step 6 exist it also publishes to Red Hat.

## 8. Check the publish run

In GitHub → Actions → `publish`, the run's summary shows the tag
(`<upstream-version>-1` the first time) and the digest reference.

| It fails at | Likely cause |
|---|---|
| "Log in to Red Hat's partner registry" | The key held for this component in `RH_REGISTRY_KEYS` is wrong, the secret is not valid JSON, or the derived username format is wrong. (A missing entry skips the stage with a warning instead) |
| "Promote the staged digest to Red Hat" | The robot account cannot push, the tag already exists there, or the digest changed in transit |
| "Release number" | GHCR refused to list the staging repository's tags |
| "Sign the digest and attest the SBOMs" | The job lacks `id-token: write`, or Sigstore was unreachable |
| "Submit to Red Hat for certification" | `RH_PYXIS_TOKEN` is missing, revoked or wrong, the component ID is wrong, or the image failed a certification check (the log names it) |

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

## 10. Slack notifications

The publish workflow can post a message to a Slack channel each time a release
is published and signed (story N.1). It needs one secret.

1. In Slack: create an **incoming webhook** for the channel (Slack → Apps →
   Incoming Webhooks → Add to Slack, pick the channel). It gives an address
   that starts with `https://hooks.slack.com/services/`.
2. In GitHub: Settings → Secrets and variables → Actions → New repository
   secret, name `SLACK_WEBHOOK_URL`, value that address. Treat it like a
   password: whoever has it can post to the channel.

Until the secret exists, each publish run has a notice saying Slack was not
told, and the release is unaffected. To see the message without sending it:
`scripts/notify-slack.sh --print <image> <tag> <repository@sha256:digest>`.

**New upstream versions.** No code is needed for "a new version was detected":
Renovate opens a pull request labelled `upstream-bump`. With the GitHub app for
Slack installed, in the channel:

```
/github subscribe stakater/certified-images pulls +label:"upstream-bump"
```

⚠️ Renovate has not opened a pull request on this repository yet (step 2).

## For the next image

Steps 4, 5, 6b and 7 to 9 again: one new entry in `RH_REGISTRY_KEYS`. The API key is already there. Steps 4 and 5 can start as soon
as the image is admitted; they do not depend on its PR.
