# certified-images: checks on the factory's own inputs (story DX.2).
# `make verify` is the one command to run before calling a change done.
#
# Every tool runs from a container image pinned by tag@digest (ADR-003/004
# apply to our tools too). ENGINE may be docker or podman.

ENGINE ?= docker

HADOLINT_IMAGE   ?= docker.io/hadolint/hadolint:v2.15.1-alpine@sha256:a1d49ae1a4e83c1dbad26b8c1ad7588c8bd1e04f4866b34ad3cac50335198552
SHELLCHECK_IMAGE ?= docker.io/koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d
ACTIONLINT_IMAGE ?= docker.io/rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667
RENOVATE_IMAGE   ?= docker.io/renovate/renovate:44.263.3@sha256:7866a93dda59fff4f7d6ab500e1fdf9fe426f136e458fa2d123f0f2236c7c629

# What each target checks. Tests override these to point at broken fixtures.
CONTAINERFILES  ?= $(wildcard images/*/Containerfile)
SHELL_SCRIPTS   ?= $(wildcard scripts/*.sh tests/*.sh)
WORKFLOWS       ?= $(wildcard .github/workflows/*.yaml .github/workflows/*.yml)
RENOVATE_CONFIG ?= renovate.json
IMAGE_DIRS      ?= $(patsubst %/,%,$(wildcard images/*/))

RUN = $(ENGINE) run --rm -v "$(CURDIR)":/work:ro -w /work

.PHONY: verify lint lint-containerfiles lint-shell lint-workflows check-renovate check-images test \
	build test-image scan preflight image test-hermetic

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

image: build test-image scan preflight ## build, test, scan and dry-run certify one image

build: ## pinned source -> Hermeto prefetch -> offline build
	ENGINE=$(ENGINE) CTX="$(CTX)" scripts/build-image.sh $(IMAGE_DIR)

test-image: ## labels, /licenses, non-root, starts
	ENGINE=$(ENGINE) scripts/test-image.sh $(REF) $(IMAGE_DIR)

scan: ## SBOMs + CVE gate (fixable CRITICAL and HIGH)
	ENGINE=$(ENGINE) scripts/scan-image.sh $(REF) $(IMAGE_DIR) "$(CTX)"

test-hermetic: ## prove a build step cannot reach the network
	ENGINE=$(ENGINE) scripts/test-hermetic.sh

preflight: ## Red Hat certification checks, dry run, nothing submitted
	ENGINE=$(ENGINE) scripts/preflight-dry-run.sh $(REF) "$(CTX)"
