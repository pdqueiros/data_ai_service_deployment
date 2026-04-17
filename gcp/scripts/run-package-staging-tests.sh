#!/usr/bin/env bash
# Host-side uv sync + pytest (staging package-only flows).
#
# Test dependencies must live in the consumer's pyproject.toml under
# [dependency-groups].checks (PEP 735). Example:
#
#   [dependency-groups]
#   checks = ["pytest", "pytest-cov"]
#
# If that group is not defined we log a notice and skip pytest — the rest
# of the pipeline still runs.
set -euo pipefail
CB_WORKSPACE="${CB_WORKSPACE:-/workspace}"
cd "${CB_WORKSPACE}"

# The builder image pre-installs uv; this fallback is only hit on dev
# hosts that don't already have uv (README section 1.1 lists it as a
# prerequisite) and requires curl on PATH.
if ! command -v uv >/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"
export GOOGLE_CLOUD_PROJECT="${PROJECT_ID:-}"

# GCP Artifact Registry PyPI keyring is only needed when actually talking to
# Artifact Registry. Local runs (REGISTRY_OVERRIDE set) skip it.
if [[ -z "${REGISTRY_OVERRIDE:-}" ]]; then
  uv tool install --quiet keyring --with keyrings.google-artifactregistry-auth
  export UV_KEYRING_PROVIDER=subprocess
fi

if ! bash "$(dirname "$0")/has-checks-group.sh" pyproject.toml; then
  echo ">>> [dependency-groups].checks not defined in pyproject.toml — skipping host-side pytest."
  exit 0
fi

uv sync --group checks

COV="${PYTEST_COVERAGE_PATH:-.}"
uv run pytest --cov="${COV}" --cov-report=xml:coverage.xml
