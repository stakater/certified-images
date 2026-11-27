# How an image gets from us to a customer through Red Hat

There are three ways a certified image can be set up in Red Hat Partner
Connect. They differ in two things: **where the image's bytes are stored**, and
**which address a customer pulls from**. Those are separate questions, and
mixing them up is what makes this confusing.

Status key: ✅ observed on 2026-11-27 with the Reloader component ·
⚠️ inferred, not yet proven.

## The three setups

| | Bytes stored on | Customer pulls from | Secrets we hold | Chosen when |
|---|---|---|---|---|
| **A. Red Hat-hosted** | Red Hat's registry | `registry.connect.redhat.com` | API key + one registry key per component | the component is created; cannot be changed later ⚠️ |
| **B. Red Hat distributes, we host** | **our GHCR** | `registry.connect.redhat.com` | API key only | same |
| **C. Our registry is the distribution** | our GHCR | `ghcr.io` | API key only | same |

Reloader's component is **B**. OpenCost's and the MTO components are **A**.

**A is the default for new components** (ADR-002 rev 9). The pipeline's setup A
path ran for the first time on 2026-11-27, with OpenCost: it logged in, copied
the GHCR digest to Red Hat's registry unchanged, signed it there and submitted
it. ⚠️ OpenCost is not published yet (export approval pending), so a pull of a
pipeline-published setup A image from Red Hat's address has not been seen.

## The short answers

**Does a customer always pull from `registry.connect.redhat.com` in setup B?**
That is the only address the catalog gives. ✅ Red Hat's catalog lists exactly
one address for the image,
`registry.connect.redhat.com/stakater/reloader-operator`, and has no `ghcr.io`
entry for it.

**But that address does not serve the image yet.** ❌ Tried on 2026-11-27,
about four and a half hours after Red Hat listed it, with a valid Red Hat
login:

| Reference on `registry.connect.redhat.com` | Answer |
|---|---|
| `stakater/mto-console`, `stakater/tenant-operator` (Red Hat-hosted) | readable |
| a repository that does not exist | "no such manifest" |
| `stakater/reloader-operator`, by tag and by digest | **"unauthorized"** |

So Red Hat's registry knows the repository and refuses to serve it. Red Hat's
record of where the image lives is correct (`ghcr.io`,
`stakater/ubi/reloader-operator`, which is public). The cause is not known. It
may be a delay on Red Hat's side, or setup B may need something we have not
done. **Until a pull from that address works, setup B is not proven and no
customer-facing manifest should reference a setup B image.**

**Is Red Hat then hosting the image on its registry?**
By Red Hat's own record, no. ✅ The component says `hosted_registry = false` and
`registry = ghcr.io`. So the address is Red Hat's, and the storage is ours.
⚠️ The likely mechanism is that `registry.connect.redhat.com` is a front door:
it checks the customer's Red Hat login, then serves the image from GHCR. That
is an inference from three facts, not something we have watched happen:

1. `hosted_registry = false`, `registry = ghcr.io`. ✅
2. The image was listed as published 12 seconds after the submission. ✅ A
   143 MB copy in that time is possible but unlikely; a metadata-only listing
   fits better.
3. The component has a slot for registry credentials that is empty
   (`docker_config_json`). ✅ That slot makes sense only if Red Hat needs to
   pull from a partner's registry.

## Setup B, step by step

```mermaid
sequenceDiagram
  autonumber
  participant CI as Our pipeline (GitHub Actions)
  participant GH as GHCR (ghcr.io/stakater/ubi/NAME)
  participant PF as preflight (runs in our pipeline)
  participant RH as Red Hat Partner Connect and catalog
  participant RHR as registry.connect.redhat.com
  actor C as Customer cluster

  Note over CI,GH: Publish. Only the workflow's own token is used
  CI->>GH: Push the image, sign it, attach SBOMs
  GH-->>CI: Digest D

  Note over CI,RH: Certify. Only RH_PYXIS_TOKEN is used
  CI->>PF: Check ghcr.io/.../NAME, then submit
  PF->>GH: Pull the image to inspect it
  PF->>RH: Test results for component ID, image digest D, where it lives
  RH-->>RH: Record registry = ghcr.io. Mark certified and published
  RH-->>RHR: List stakater/NAME at digest D

  Note over C,GH: Install. The customer only ever names Red Hat's registry
  C->>RHR: Log in with a Red Hat account, pull stakater/NAME at digest D
  RHR->>GH: Fetch the image (inferred, not yet observed)
  GH-->>RHR: Image bytes
  RHR-->>C: Image, same digest D
```

What we never do in setup B: log in to Red Hat's registry, push to it, or hold
a registry key for the component.

## For comparison: setup A

```mermaid
sequenceDiagram
  autonumber
  participant CI as Our pipeline
  participant Q as Red Hat's inbound registry (quay.io/redhat-isv-containers/ID)
  participant RH as Red Hat Partner Connect and catalog
  participant RHR as registry.connect.redhat.com
  actor C as Customer cluster

  CI->>Q: Log in with the component's own registry key, push the image
  CI->>RH: preflight submit, with RH_PYXIS_TOKEN
  RH-->>RHR: Publish. Red Hat stores the image
  C->>RHR: Log in with a Red Hat account, pull
  RHR-->>C: Image, served from Red Hat's storage
```

The customer's side is identical in A and B. The difference is on our side: A
needs a registry key per component, and Red Hat keeps the bytes.

## What if

These follow from "Red Hat's address, our storage". Each is ⚠️ until tested.

| What if | Setup A | Setup B |
|---|---|---|
| GHCR is down | No effect on customers | Customers probably cannot pull through Red Hat either |
| We delete the tag or the package on GHCR | No effect | The published image probably stops being pullable. **A published tag on GHCR must never be deleted** |
| The GHCR package is made private | No effect | Red Hat can no longer fetch it, unless we give Red Hat a read-only credential (the empty `docker_config_json` slot) |
| The image is private by design (Console, Gateway) | Works | Works only with that credential in place |
| A customer's cluster is air-gapped | They mirror from Red Hat by digest | The same |
| A customer wants to verify our signature | Signatures would have to be on Red Hat's registry | The signature is on GHCR for the same digest, so it can be verified there |
| We want Red Hat to carry the storage risk | Yes | No: GHCR is a production dependency |

## What the pipeline does with this

- It asks Red Hat's API for the component's record
  (`scripts/rh-component-info.sh`) and follows it. Nothing is declared in
  `image.yaml`, and if the record cannot be read the run fails.
- **Setup B:** one step, submit the GHCR image. No login, no copy, no second
  signature.
- **Setup A:** copy the same digest to Red Hat's registry with the component's
  key, sign it there, submit.
- **Setup C** is refused: this pipeline does not publish to it.
- In setup B, GHCR is not a staging area. **It is where the published image
  lives** (ADR-002 rev 8). A tag Red Hat lists is never deleted.

## How to prove the open points

**1. That the published address pulls** (needs a Red Hat login). This currently
fails, see above; re-run it to see whether that has changed:

```
podman login registry.connect.redhat.com
podman pull registry.connect.redhat.com/stakater/reloader-operator@sha256:bef05dfdf931d6457cb899d0b64dc0b6ebb9a0ac706c1245ceec8783957c0370
```

**2. Where the bytes come from.** Same login, with debug output; look at which
host the layers are downloaded from:

```
podman --log-level=debug pull registry.connect.redhat.com/stakater/reloader-operator@sha256:bef05dfdf931d6457cb899d0b64dc0b6ebb9a0ac706c1245ceec8783957c0370 2>&1 | grep -iE "redirect|GET https|blob" | head -20
```

A host under `ghcr.io` or `githubusercontent.com` means Red Hat sends the
customer to our storage. A Red Hat or Quay host means Red Hat keeps a copy,
and the "what if" column for B is better than stated above.
