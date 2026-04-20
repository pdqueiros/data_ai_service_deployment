# GCP CI/CD pipeline harness — works both locally and against real GCP.
#
# Cloud vs. local is controlled by MODE, which only changes the infra env vars
# passed to scripts/pipeline.sh. The variant targets (package-and-image,
# image-only, …) are identical in both modes.
#
# Typical usage (from the gcp/ directory):
#
#   make help                          # list all targets
#   make package-and-image             # default: MODE=local, REPO=./test_repo
#   make package-and-image-full        # staging then production, end-to-end
#   make all                           # every variant end-to-end
#   make REPO=/path/to/my-service image-only
#
#   # Run against real GCP Artifact Registry (requires `source .env` first
#   # so PROJECT_ID and ARTIFACT_REGISTRY_* are populated, plus an
#   # authenticated gcloud session). See README.md.
#   source .env && make MODE=cloud package-and-image
#
# Modes:
#   MODE=local (default)
#     Auto-starts localhost:5000 (registry:2) and localhost:8080 (pypiserver)
#     and points the pipeline at them. After a staging image build it
#     docker-pulls the result to verify the round-trip.
#   MODE=cloud
#     No overrides, no containers started. Expects PROJECT_ID,
#     ARTIFACT_REGISTRY_LOCATION, ARTIFACT_REGISTRY_DOCKER, ARTIFACT_REGISTRY_PYPI
#     (and an authenticated gcloud session) to be in the environment already —
#     i.e. `source gcp/.env` before running.

SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:

MODE ?= local
REPO ?= $(CURDIR)/test_repo

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@printf '%s\n' \
	  'GCP CI/CD Pipeline — Makefile' \
	  '' \
	  'Variables (pass on the command line or export):' \
	  '  MODE  local (default) | cloud   Selects infra env (see per-mode details below)' \
	  '                                  e.g. make MODE=cloud package-and-image' \
	  '  REPO  path to consumer repo     Defaults to ./test_repo' \
	  '                                  e.g. make REPO=/path/to/my-service image-only' \
	  '  CONSUMER_REPO linked repo name  Required for link-and-create-triggers' \
	  '                                  e.g. pdqueiros-child_test_repo' \
	  '  GITHUB_REPO_URI GitHub clone URI Required for link-and-create-triggers' \
	  '' \
	  'MODE=local  (no GCP account needed, no env vars required)' \
	  '  Auto-starts local stand-ins for Artifact Registry and points the pipeline at them:' \
	  '    • registry:2            on http://localhost:5000   (Docker images)' \
	  '    • pypiserver/pypiserver on http://localhost:8080   (Python wheels)' \
	  '  Prereq: Docker daemon trusts localhost:5000 as an insecure registry.' \
	  '' \
	  'MODE=cloud  (runs against real GCP Artifact Registry)' \
	  '  Required env — source gcp/.env to populate:' \
	  '    PROJECT_ID                  e.g. scryn-co' \
	  '    ARTIFACT_REGISTRY_LOCATION  e.g. europe-west1' \
	  '    ARTIFACT_REGISTRY_DOCKER    e.g. docker-test' \
	  '    ARTIFACT_REGISTRY_PYPI      e.g. pypi-test' \
	  '  Optional env:' \
	  '    CLOUD_RUN_SERVICE           e.g. embeddings-api   (deploys promoted prod image)' \
	  '    CLOUD_RUN_REGION            e.g. europe-west1     (required with CLOUD_RUN_SERVICE)' \
	  '  Prereq: `gcloud auth login` (Cloud Build triggers normally run this' \
	  '  flow inside the scryn-pipeline builder image on every push; MODE=cloud' \
	  '  from your laptop is mainly for one-off debugging).' \
	  '' \
	  'Examples:' \
	  '  make package-and-image                      # local, ./test_repo' \
	  '  make REPO=/path/to/my-service image-only    # different consumer repo' \
	  '  make package-and-image-full                 # staging then production, end-to-end' \
	  '  make all                                    # every variant end-to-end' \
	  '  source gcp/.env && MODE=cloud make package-and-image' \
	  '  source gcp/.env && make link-and-create-triggers CONSUMER_REPO=pdqueiros-child_test_repo GITHUB_REPO_URI=https://github.com/scryn-co/child_test_repo.git' \
	  '' \
	  'Targets:'
	@awk 'BEGIN {FS = ":.*## "} \
	     /^[a-zA-Z][a-zA-Z0-9_-]*:.*## / {printf "  \033[36m%-32s\033[0m %s\n", $$1, $$2}' \
	     $(MAKEFILE_LIST)
	@for v in $(VARIANTS); do \
	   printf "  \033[36m%-32s\033[0m %s\n" "$$v-full" "end-to-end: $$v staging + production"; \
	 done

# ── local registries (Docker + PyPI) ────────────────────────────────
.PHONY: registry-up registry-down registry-reset
registry-up: ## Start local Docker (:5000) + PyPI (:8080) registries (auto-started in MODE=local)
	docker compose -f local/docker-compose.registry.yaml up -d
	docker compose -f local/docker-compose.pypi.yaml up -d

registry-down: ## Stop local registries (keeps uploaded images and wheels)
	docker compose -f local/docker-compose.registry.yaml down
	docker compose -f local/docker-compose.pypi.yaml down

registry-reset: ## Stop local registries AND delete all images and wheels
	docker compose -f local/docker-compose.registry.yaml down -v
	docker compose -f local/docker-compose.pypi.yaml down -v

# ── trigger automation (consumer repo) ───────────────────────────────
.PHONY: link-and-create-triggers
link-and-create-triggers: ## Link consumer repo (if needed) and create staging/production triggers
	: "$${PROJECT_ID:?source gcp/.env first (PROJECT_ID missing)}"
	: "$${PROJECT_NUMBER:?source gcp/.env first (PROJECT_NUMBER missing)}"
	: "$${REGION:?source gcp/.env first (REGION missing)}"
	: "$${CONNECTION_NAME:?source gcp/.env first (CONNECTION_NAME missing)}"
	: "$${CLOUD_BUILD_SA:?source gcp/.env first (CLOUD_BUILD_SA missing)}"
	: "$${ARTIFACT_REGISTRY_DOCKER:?source gcp/.env first (ARTIFACT_REGISTRY_DOCKER missing)}"
	: "$${ARTIFACT_REGISTRY_PYPI:?source gcp/.env first (ARTIFACT_REGISTRY_PYPI missing)}"
	: "$${IMAGE_NAME:?source gcp/.env first (IMAGE_NAME missing)}"
	: "$${CONSUMER_REPO:?set CONSUMER_REPO (linked repository name)}"
	: "$${GITHUB_REPO_URI:?set GITHUB_REPO_URI (e.g. https://github.com/org/repo.git)}"
	TRIGGER_BASE="$${CONSUMER_REPO//_/-}"
	SUBS="_ARTIFACT_REGISTRY_LOCATION=$${REGION},_ARTIFACT_REGISTRY_DOCKER=$${ARTIFACT_REGISTRY_DOCKER},_ARTIFACT_REGISTRY_PYPI=$${ARTIFACT_REGISTRY_PYPI},_IMAGE_NAME=$${IMAGE_NAME}"
	REPO_PATH="projects/$${PROJECT_NUMBER}/locations/$${REGION}/connections/$${CONNECTION_NAME}/repositories/$${CONSUMER_REPO}"
	if gcloud builds repositories describe "$${CONSUMER_REPO}" --project="$${PROJECT_ID}" --region="$${REGION}" --connection="$${CONNECTION_NAME}" >/dev/null 2>&1; then
	  echo "Repository '$${CONSUMER_REPO}' already linked to connection '$${CONNECTION_NAME}'."
	else
	  echo "Linking repository '$${CONSUMER_REPO}' to connection '$${CONNECTION_NAME}'..."
	  gcloud builds repositories create "$${CONSUMER_REPO}" \
	    --project="$${PROJECT_ID}" --region="$${REGION}" \
	    --connection="$${CONNECTION_NAME}" \
	    --remote-uri="$${GITHUB_REPO_URI}"
	fi
	for stage in staging production; do
	  trigger_name="$${TRIGGER_BASE}-$${stage}"
	  if gcloud builds triggers describe "$${trigger_name}" --project="$${PROJECT_ID}" --region="$${REGION}" >/dev/null 2>&1; then
	    echo "Trigger '$${trigger_name}' already exists; skipping."
	    continue
	  fi
	  echo "Creating trigger '$${trigger_name}'..."
	  gcloud builds triggers create github \
	    --name="$${trigger_name}" \
	    --project="$${PROJECT_ID}" --region="$${REGION}" \
	    --repository="$${REPO_PATH}" \
	    --branch-pattern="^$${stage}$$" \
	    --build-config=cloudbuild.yaml \
	    --included-files='CHANGELOG.md' \
	    --service-account="$${CLOUD_BUILD_SA}" \
	    --substitutions="_STAGE_NAME=$${stage},$${SUBS}"
	done

# ── pipeline runner ──────────────────────────────────────────────────
# $(call run-pipeline, HAS_IMAGE, HAS_PACKAGE, TEST_KIND, STAGE_NAME)
define run-pipeline
	export CB_WORKSPACE="$(REPO)"
	export HAS_IMAGE="$(1)"
	export HAS_PACKAGE="$(2)"
	export TEST_KIND="$(3)"
	: "$${STAGE_NAME:=$(4)}"
	export STAGE_NAME

	if [[ "$(MODE)" == "local" ]]; then
	  export REGISTRY_OVERRIDE="localhost:5000/scryn-local"
	  export PYPI_UPLOAD_URL_OVERRIDE="http://localhost:8080/"
	  export PYPI_INDEX_URL_OVERRIDE="http://localhost:8080/simple/"
	  echo "=== Ensuring local registries are running (Docker :5000, PyPI :8080) ==="
	  docker compose -f local/docker-compose.registry.yaml up -d
	  docker compose -f local/docker-compose.pypi.yaml up -d
	elif [[ "$(MODE)" == "cloud" ]]; then
	  : "$${PROJECT_ID:?MODE=cloud requires PROJECT_ID — source gcp/.env first}"
	  : "$${ARTIFACT_REGISTRY_LOCATION:?MODE=cloud requires ARTIFACT_REGISTRY_LOCATION — source gcp/.env first}"
	  : "$${ARTIFACT_REGISTRY_DOCKER:?MODE=cloud requires ARTIFACT_REGISTRY_DOCKER — source gcp/.env first}"
	  : "$${ARTIFACT_REGISTRY_PYPI:?MODE=cloud requires ARTIFACT_REGISTRY_PYPI — source gcp/.env first}"
	else
	  echo "error: MODE must be 'local' or 'cloud', got '$(MODE)'" >&2
	  exit 1
	fi

	cleanup() {
	  echo ""
	  echo "=== Cleaning up temporary files in $(REPO) ==="
	  rm -f  "$(REPO)/.cb-build-env" "$(REPO)/coverage.xml"
	  rm -rf "$(REPO)/dist"
	}
	trap cleanup EXIT

	bash scripts/pipeline.sh

	if [[ "$(MODE)" == "local" && "$(1)" == "true" ]]; then
	  source "$(REPO)/.cb-build-env"
	  IMAGE="$${REGISTRY}/$${PACKAGE_NAME}:$${IMAGE_TAG}"
	  echo ""
	  echo "=== [verify] Pulling $${IMAGE} ==="
	  docker pull "$${IMAGE}"
	  echo "SUCCESS: image $${IMAGE} is available in the local registry."
	fi
endef

# ── per-variant staging targets ──────────────────────────────────────
.PHONY: package-and-image package-and-image-no-test \
        image-only image-only-no-test \
        package-only package-only-no-test \
        package-test-image

package-and-image: ## staging: image + package, pytest-in-image
	$(call run-pipeline,true,true,in_image,staging)

package-and-image-no-test: ## staging: image + package, no tests
	$(call run-pipeline,true,true,,staging)

image-only: ## staging: image only, pytest-in-image
	$(call run-pipeline,true,false,in_image,staging)

image-only-no-test: ## staging: image only, no tests
	$(call run-pipeline,true,false,,staging)

package-only: ## staging: package only, host pytest
	$(call run-pipeline,false,true,in_host,staging)

package-only-no-test: ## staging: package only, no tests
	$(call run-pipeline,false,true,,staging)

package-test-image: ## staging: package + image, host pytest
	$(call run-pipeline,true,true,in_host,staging)

# ── end-to-end (staging → production) ────────────────────────────────
# To run a single variant in production only, pass STAGE_NAME=production,
# e.g. `STAGE_NAME=production make package-and-image`. The *-full targets
# below run staging first, then re-run the same variant in production.
# Image-producing production runs assume the matching staging run has
# already uploaded the staging_<version> tag (promote-docker-tags.sh
# pulls it and retags it as production_<version>).
VARIANTS := package-and-image package-and-image-no-test \
            image-only image-only-no-test \
            package-only package-only-no-test \
            package-test-image

define _full_rule
$(1)-full: ## end-to-end: $(1) staging + production
$(1)-full: $(1)
	$$(MAKE) STAGE_NAME=production $(1)
endef
$(foreach v,$(VARIANTS),$(eval $(call _full_rule,$(v))))
.PHONY: $(addsuffix -full,$(VARIANTS))

# ── aggregators ──────────────────────────────────────────────────────
.PHONY: all-staging all-production all

all-staging: ## Run every variant in staging
	@for v in $(VARIANTS); do $(MAKE) $$v || exit $$?; done

all-production: ## Run every variant in production (needs staging first)
	@for v in $(VARIANTS); do $(MAKE) STAGE_NAME=production $$v || exit $$?; done

all: ## Run every variant end-to-end (staging then production)
	$(MAKE) all-staging
	$(MAKE) all-production

# ── clean ────────────────────────────────────────────────────────────
.PHONY: clean
clean: ## Remove pipeline artifacts from $(REPO) (does not touch registry/PyPI)
	rm -f  "$(REPO)/.cb-build-env" "$(REPO)/coverage.xml"
	rm -rf "$(REPO)/dist"
