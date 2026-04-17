#!/usr/bin/env bash
# Build wheels with uv and upload them via twine.
#
# GCP   (default):         uploads to Artifact Registry PyPI using a short-lived
#                          oauth2 access token.
# Local (REGISTRY_OVERRIDE set): uploads to whatever ${PYPI_UPLOAD_URL} is in
#                          .cb-build-env — typically http://localhost:8080/
#                          (pypiserver), with anonymous auth.
#
# Optional first arg: workspace directory (default /workspace or CB_WORKSPACE env).
set -euo pipefail
WS="${1:-${CB_WORKSPACE:-/workspace}}"
cd "$WS"

if ! command -v uv >/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"

uv build
source "${WS}/.cb-build-env"

if [[ -z "${PYPI_UPLOAD_URL}" ]]; then
  echo "error: PYPI_UPLOAD_URL is empty — nowhere to upload wheels." >&2
  echo "  GCP builds must set ARTIFACT_REGISTRY_LOCATION/PROJECT_ID/ARTIFACT_REGISTRY_PYPI." >&2
  echo "  Local runs must set PYPI_UPLOAD_URL_OVERRIDE (e.g. http://localhost:8080/)." >&2
  exit 1
fi

if [[ -n "${REGISTRY_OVERRIDE:-}" ]]; then
  export TWINE_USERNAME="${TWINE_USERNAME:-local}"
  export TWINE_PASSWORD="${TWINE_PASSWORD:-local}"
else
  export TWINE_USERNAME=oauth2accesstoken
  export TWINE_PASSWORD
  TWINE_PASSWORD="$(gcloud auth print-access-token)"
fi

uvx twine upload --repository-url "${PYPI_UPLOAD_URL}" "${WS}"/dist/*
