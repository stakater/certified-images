# certified-images: checks on the factory's own inputs (story DX.2).
# `make verify` is the one command to run before calling a change done.
#
# Every tool runs from a container image pinned by tag@digest in tools.env.
# ENGINE may be docker or podman.

ENGINE ?= docker

# Tool images are pinned in tools.env, the one place Renovate maintains.
include tools.env
export HADOLINT_IMAGE SHELLCHECK_IMAGE ACTIONLINT_IMAGE RENOVATE_IMAGE YQ_IMAGE \
	HERMETO_IMAGE SYFT_IMAGE TRIVY_IMAGE PREFLIGHT_IMAGE REGISTRY_IMAGE CRANE_IMAGE KIND_NODE_IMAGE

# What each target checks. Tests override these to point at broken fixtures.
CONTAINERFILES  ?= $(wildcard images/*/Containerfile)
SHELL_SCRIPTS   ?= $(wildcard scripts/*.sh tests/*.sh images/*/functional/*.sh images/*/smoke/*.sh stacks/*/test.sh)
WORKFLOWS       ?= $(wildcard .github/workflows/*.yaml .github/workflows/*.yml)
RENOVATE_CONFIG ?= renovate.json
IMAGE_DIRS      ?= $(patsubst %/,%,$(wildcard images/*/))

RUN = $(ENGINE) run --rm -v "$(CURDIR)":/work:ro -w /work

.PHONY: verify lint lint-containerfiles lint-shell lint-workflows check-renovate check-images test \
	build test-image scan preflight image test-hermetic publish-rehearsal smoke test-smoke stack site

verify: lint check-renovate check-images test ## run every check
	@echo "verify: all checks passed"

lint: lint-containerfiles lint-shell lint-workflows

lint-containerfiles: ## hadolint on every Containerfile
	@test -n "$(CONTAINERFILES)" || { echo "lint-containerfiles: no Containerfiles found" >&2; exit 1; }
	$(RUN) $(HADOLINT_IMAGE) hadolint --config .hadolint.yaml $(CONTAINERFILES)

lint-shell: ## shellcheck on scripts and tests
	@test -n "$(SHELL_SCRIPTS)" || { echo "lint-shell: no shell scripts found" >&2; exit 1; }
	$(RUN) $(SHELLCHECK_IMAGE) $(SHELL_SCRIPTS)

lint-workflows: ## actionlint on GitHub workflows
	@test -n "$(WORKFLOWS)" || { echo "lint-workflows: no workflows found" >&2; exit 1; }
	$(RUN) $(ACTIONLINT_IMAGE) $(WORKFLOWS)

check-renovate: ## renovate-config-validator, strict (fails on config that needs migrating)
	$(RUN) --entrypoint renovate-config-validator $(RENOVATE_IMAGE) --strict $(RENOVATE_CONFIG)

check-images: ## our own rules for every images/<name>/ (scripts/check-image.sh)
	@test -n "$(IMAGE_DIRS)" || { echo "check-images: no image directories found" >&2; exit 1; }
	@rc=0; for d in $(IMAGE_DIRS); do ENGINE=$(ENGINE) scripts/check-image.sh "$$d" || rc=1; done; exit $$rc

test: ## tests for the scripts, and a self-test that every check can fail
	ENGINE=$(ENGINE) tests/run.sh

# ---------------------------------------------------------------- one image
# The same steps CI runs (.github/workflows/build-certify.yaml). Needs network
# for the prefetch, the CVE database and preflight; the build itself has none.
#   make image IMAGE=opencost
IMAGE     ?= opencost
IMAGE_DIR ?= images/$(IMAGE)
CTX       ?= $(CURDIR)/.ctx/$(notdir $(IMAGE_DIR))
REF       ?= localhost/stakater/$(notdir $(IMAGE_DIR)):build
# Release number baked into the image label (ADR-002 rule 3). The publish
# workflow computes it from the registry; local and PR builds use 0.
RELEASE   ?= 0

image: build test-image smoke scan preflight ## build, test, scan and dry-run certify one image

build: ## pinned source -> Hermeto prefetch -> offline build
	ENGINE=$(ENGINE) CTX="$(CTX)" RELEASE="$(RELEASE)" scripts/build-image.sh $(IMAGE_DIR)

test-image: ## labels, /licenses, non-root, starts
	ENGINE=$(ENGINE) RELEASE="$(RELEASE)" scripts/test-image.sh $(REF) $(IMAGE_DIR)

smoke: ## run the image as a pod on a throwaway local cluster under restricted pod security
	ENGINE=$(ENGINE) scripts/smoke-kind.sh $(REF) $(IMAGE_DIR)

# A stack: images that only work together, built and run with each other.
#   make stack STACK=etcd
STACK     ?= etcd
STACK_DIR ?= stacks/$(STACK)

stack: ## build a stack's images and run them together on a throwaway local cluster
	ENGINE=$(ENGINE) scripts/stack-test.sh $(STACK_DIR)

# The public catalogue site (story S.1): the data, read from this checkout,
# the registry, GitHub and Red Hat's catalogue, plus the static pages.
#   make site            # then serve _site/ with any static file server
SITE_OUT ?= _site

site: ## generate the catalogue site into _site/
	@rm -rf "$(SITE_OUT)" && mkdir -p "$(SITE_OUT)"
	cp site/index.html site/image.html site/app.js site/style.css "$(SITE_OUT)/"
	ENGINE=$(ENGINE) scripts/site-data.sh "$(SITE_OUT)"

test-smoke: ## prove the smoke test rejects images that do not work
	ENGINE=$(ENGINE) scripts/test-smoke.sh

scan: ## SBOMs + CVE gate (fixable CRITICAL and HIGH)
	ENGINE=$(ENGINE) scripts/scan-image.sh $(REF) $(IMAGE_DIR) "$(CTX)"

test-hermetic: ## prove a build step cannot reach the network
	ENGINE=$(ENGINE) scripts/test-hermetic.sh

publish-rehearsal: ## release numbering and push against a throwaway local registry
	ENGINE=$(ENGINE) scripts/publish-rehearsal.sh $(REF) $(IMAGE_DIR)

preflight: ## Red Hat certification checks, dry run, nothing submitted
	ENGINE=$(ENGINE) scripts/preflight-dry-run.sh $(REF) "$(CTX)"
