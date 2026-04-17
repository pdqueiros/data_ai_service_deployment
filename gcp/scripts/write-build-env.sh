#!/usr/bin/env bash
# Writes /workspace/.cb-build-env for subsequent Cloud Build steps.
# Usage: write-build-env.sh [WORKSPACE_DIR]
#
# GCP (default): PROJECT_ID, ARTIFACT_REGISTRY_LOCATION, ARTIFACT_REGISTRY_DOCKER, ARTIFACT_REGISTRY_PYPI required
#   (supplied via Cloud Build trigger substitutions → env vars in the step).
# Local:  set REGISTRY_OVERRIDE (e.g. localhost:5000/scryn-local); AR_* optional.
# Optional (local only): PYPI_UPLOAD_URL_OVERRIDE, PYPI_INDEX_URL_OVERRIDE — point the
# pipeline at a local PyPI server (e.g. pypiserver on http://localhost:8080/).

set -euo pipefail

ROOT="${1:-/workspace}"
cd "$ROOT"

if [[ ! -f pyproject.toml ]]; then
  echo "error: pyproject.toml not found under ${ROOT}" >&2
  exit 1
fi

read -r PACKAGE_NAME PACKAGE_VERSION PYTHON_VERSION < <(python3 - <<'PY'
import re, tomllib
with open("pyproject.toml", "rb") as f:
    proj = tomllib.load(f)["project"]
m = re.search(r"(\d+\.\d+(?:\.\d+)?)", proj.get("requires-python", ""))
print(proj["name"], proj["version"], m.group(1) if m else "")
PY
)

STAGE_NAME="${STAGE_NAME:-staging}"
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-docker-compose-build.yaml}"

if [[ -n "${REGISTRY_OVERRIDE:-}" ]]; then
  REGISTRY="${REGISTRY_OVERRIDE}"
  PROJECT_ID="${PROJECT_ID:-local}"
  ARTIFACT_REGISTRY_LOCATION="${ARTIFACT_REGISTRY_LOCATION:-}"
  ARTIFACT_REGISTRY_DOCKER="${ARTIFACT_REGISTRY_DOCKER:-}"
  ARTIFACT_REGISTRY_PYPI="${ARTIFACT_REGISTRY_PYPI:-}"
  PYPI_UPLOAD_URL="${PYPI_UPLOAD_URL_OVERRIDE:-}"
  PYPI_INDEX_URL="${PYPI_INDEX_URL_OVERRIDE:-}"
else
  : "${PROJECT_ID:?PROJECT_ID is required}"
  : "${ARTIFACT_REGISTRY_LOCATION:?ARTIFACT_REGISTRY_LOCATION is required (set by Cloud Build substitutions)}"
  : "${ARTIFACT_REGISTRY_DOCKER:?ARTIFACT_REGISTRY_DOCKER is required (set by Cloud Build substitutions)}"
  : "${ARTIFACT_REGISTRY_PYPI:?ARTIFACT_REGISTRY_PYPI is required (set by Cloud Build substitutions)}"
  REGISTRY="${ARTIFACT_REGISTRY_LOCATION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_DOCKER}"
  PYPI_UPLOAD_URL="https://${ARTIFACT_REGISTRY_LOCATION}-python.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_PYPI}/"
  PYPI_INDEX_URL="https://${ARTIFACT_REGISTRY_LOCATION}-python.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_PYPI}/simple/"
fi

OUT="${ROOT}/.cb-build-env"
cat >"$OUT" <<EOF
export PACKAGE_NAME='${PACKAGE_NAME}'
export PACKAGE_VERSION='${PACKAGE_VERSION}'
export PYTHON_VERSION='${PYTHON_VERSION}'
export STAGE_NAME='${STAGE_NAME}'
export REGISTRY='${REGISTRY}'
export DOCKER_COMPOSE_FILE='${DOCKER_COMPOSE_FILE}'
export PYPI_UPLOAD_URL='${PYPI_UPLOAD_URL}'
export ARTIFACT_REGISTRY_LOCATION='${ARTIFACT_REGISTRY_LOCATION}'
export ARTIFACT_REGISTRY_DOCKER='${ARTIFACT_REGISTRY_DOCKER}'
export ARTIFACT_REGISTRY_PYPI='${ARTIFACT_REGISTRY_PYPI}'
export PYPI_INDEX_URL='${PYPI_INDEX_URL}'
export IMAGE_TAG='${STAGE_NAME}_${PACKAGE_VERSION}'
EOF
echo "Wrote ${OUT}"
cat "$OUT"
