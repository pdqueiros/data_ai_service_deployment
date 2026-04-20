SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
MAKEFLAGS += --no-print-directory

DOCKER_COMPOSE_BUILD_FILE ?= docker-compose-build.yaml
REGION ?= europe-west1
PROJECT_ID ?= scryn-co
ARTIFACT_REGISTRY_DOCKER ?= docker-test
IMAGE_TAG ?= latest
INSTALL_EXTRAS ?= --all-extras

REGISTRY ?= $(if $(GCP_REGISTRY),$(GCP_REGISTRY),${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_DOCKER})

PACKAGE_NAME ?= $(shell grep -m 1 '^name' pyproject.toml | sed -E 's/name = "(.*)"/\1/')


.PHONY: help check_uv install update activate test format build

# This block defines the "dictionary" logic once.
# We use $$ everywhere so Make passes the dollar signs to the Bash shell.
define SETUP_ENV_VARS
	declare -A ENV
	ENV["PACKAGE"]=$$(grep -m 1 '^name' pyproject.toml | sed -E 's/name = "(.*)"/\1/')
	ENV["PYTHON_VERSION"]=$$(grep -m 1 '^requires-python' pyproject.toml | sed -nE 's/^[^0-9]*([0-9]+\.[0-9]+).*/\1/p')
	ENV["ENV_DIR"]="${HOME}/envs/$${ENV["PACKAGE"]}"
	ENV["ENV_PATH"]="$${ENV["ENV_DIR"]}/bin/activate"
endef

# Resolve private-index credentials in-memory only.
define SETUP_EPHEMERAL_GCP_AUTH
	if ! command -v gcloud >/dev/null 2>&1; then
		echo >&2 "Error: gcloud CLI is required for ephemeral auth."
		echo >&2 "Install gcloud and run: gcloud auth login"
		exit 1
	fi
	token="$$(gcloud auth print-access-token 2>/dev/null || true)"
	if [[ -z "$$token" ]]; then
		echo >&2 "Error: gcloud is not authenticated."
		echo >&2 "Run: gcloud auth login"
		exit 1
	fi
	export UV_INDEX_GCP_USERNAME="oauth2accesstoken"
	export UV_INDEX_GCP_PASSWORD="$$token"
endef

help:
	@printf '%s\n' \
	  'Project automation targets' \
	  '' \
	  'Targets:' \
	  '  check_uv        Verify uv is installed' \
	  '  install         Create project virtualenv and sync dependencies' \
	  '  update          Recreate virtualenv and re-sync dependencies' \
	  '  test            Run test suite with uv' \
	  '  format          Run ruff check --fix and ruff format' \
	  '  build           Build image via docker compose using ephemeral auth' \
	  '' \
	  'Behavior:' \
	  '  - Default: ephemeral token via gcloud (never written to disk)' \
	  '  - Requires authenticated gcloud session (run: gcloud auth login)' \
	  '  - Local build tag defaults to latest (override with IMAGE_TAG=...)' \
	  '  - Registry can be set via GCP_REGISTRY (defaults to ${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_DOCKER})'


build:
	@$(SETUP_EPHEMERAL_GCP_AUTH)
	@REGISTRY="$(REGISTRY)" PACKAGE_NAME="$(PACKAGE_NAME)" IMAGE_TAG="$(IMAGE_TAG)" \
	  docker compose -f "$(DOCKER_COMPOSE_BUILD_FILE)" build
	@unset UV_INDEX_GCP_USERNAME UV_INDEX_GCP_PASSWORD

# --- 0. Requirement Check ---
check_uv:
	@command -v uv >/dev/null 2>&1 || { \
		echo >&2 "Error: 'uv' is not installed."; \
		echo >&2 "Please install it via: wget -qO- https://astral.sh/uv/install.sh | sh"; \
		exit 1; \
	}

# --- 1. Install ---
install: check_uv
	@$(SETUP_ENV_VARS)
	$(SETUP_EPHEMERAL_GCP_AUTH)
	if [ ! -d "$${ENV["ENV_DIR"]}" ]; then
		echo "Creating environment for $${ENV["PACKAGE"]}..."
		uv venv "$${ENV["ENV_DIR"]}" --python "$${ENV["PYTHON_VERSION"]}"
		source "$${ENV["ENV_PATH"]}" && uv sync --active $(INSTALL_EXTRAS)
		echo "Install complete. Use 'make activate' to activate it"
	else
		echo "Environment for $${ENV["PACKAGE"]} already exists at $${ENV["ENV_DIR"]}. Use 'make activate' to activate it, or 'make update' to update it."
	fi
	unset UV_INDEX_GCP_USERNAME UV_INDEX_GCP_PASSWORD
	unset ENV

# --- 2. Update ---
update: check_uv
	@$(SETUP_ENV_VARS)
	$(SETUP_EPHEMERAL_GCP_AUTH)
	if [ ! -f "$${ENV["ENV_PATH"]}" ]; then
		echo "Error: Environment not found. Run 'make install' first."
		exit 1
	fi
	echo "Updating environment for $${ENV["PACKAGE"]}..."
	rm -f uv.lock
	uv venv  --clear "$${ENV["ENV_DIR"]}" --python "$${ENV["PYTHON_VERSION"]}"
	source "$${ENV["ENV_PATH"]}" && uv sync --active $(INSTALL_EXTRAS)
	unset UV_INDEX_GCP_USERNAME UV_INDEX_GCP_PASSWORD
	unset ENV
	echo "Update complete."

activate:
	@if [ "$${IN_MAKE_SHELL:-}" = "true" ]; then
		echo "Already inside a sub-shell, either exit the sub-shell with 'exit'/ctrl+d or start a new terminal session."
		exit 0
	fi
	$(SETUP_ENV_VARS)
	if [ ! -f "$${ENV["ENV_PATH"]}" ]; then
		echo "Error: Environment not found. Run 'make install' first."
		exit 1
	fi
	echo "--- Entering $${ENV["PACKAGE"]} environment and sourcing .env (type 'exit' to leave) ---"
	bash --rcfile <(echo "source ~/.bashrc; source $${ENV["ENV_PATH"]}; export IN_MAKE_SHELL=true")
	unset ENV

test: check_uv
	@echo "Running tests via uv..."
	uv run --all-extras --group checks pytest -q

format: check_uv
	@echo "Running ruff formatter/linter via temporary uv environment..."
	uv run --with ruff ruff check . --fix
	uv run --with ruff ruff format .

