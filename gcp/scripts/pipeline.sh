#!/usr/bin/env bash
# Orchestrates the full CI/CD pipeline in a single script.
# Designed to run as one Cloud Build step (or locally).
#
# Required env:
#   STAGE_NAME  — staging | production
#   HAS_IMAGE   — true | false — build + push a Docker image in staging;
#                               retag it in production
#   HAS_PACKAGE — true | false — build + upload Python wheels in production
#   TEST_KIND   — "" (none) | in_image | host_package
#                 "in_image"     pytest inside the built Docker image (requires HAS_IMAGE)
#                 "host_package" uv sync + pytest on the host
#
# Optional env:
#   ARTIFACT_REGISTRY_LOCATION, ARTIFACT_REGISTRY_DOCKER, ARTIFACT_REGISTRY_PYPI, DOCKER_COMPOSE_FILE
#   REGISTRY_OVERRIDE, PYPI_UPLOAD_URL_OVERRIDE, PYPI_INDEX_URL_OVERRIDE  (local testing)
#   CB_WORKSPACE                               (default /workspace)
#   CLOUD_RUN_SERVICE, CLOUD_RUN_REGION        (production + HAS_IMAGE only;
#                                               deploys promoted image to Cloud Run)
set -euo pipefail

: "${STAGE_NAME:?Set STAGE_NAME (staging or production)}"
HAS_IMAGE="${HAS_IMAGE:-false}"
HAS_PACKAGE="${HAS_PACKAGE:-true}"
TEST_KIND="${TEST_KIND:-}"

# ── validate flags ────────────────────────────────────────────────────
case "${HAS_IMAGE}"   in true|false) ;; *) echo "error: HAS_IMAGE must be true|false, got '${HAS_IMAGE}'"   >&2; exit 1 ;; esac
case "${HAS_PACKAGE}" in true|false) ;; *) echo "error: HAS_PACKAGE must be true|false, got '${HAS_PACKAGE}'" >&2; exit 1 ;; esac
case "${TEST_KIND}"   in ""|in_image|host_package) ;; *) echo "error: TEST_KIND must be ''|in_image|host_package, got '${TEST_KIND}'" >&2; exit 1 ;; esac

if [[ "${HAS_IMAGE}" == false && "${HAS_PACKAGE}" == false ]]; then
  echo "error: at least one of HAS_IMAGE or HAS_PACKAGE must be true" >&2
  exit 1
fi
if [[ "${TEST_KIND}" == "in_image" && "${HAS_IMAGE}" != true ]]; then
  echo "error: TEST_KIND=in_image requires HAS_IMAGE=true" >&2
  exit 1
fi

SCRIPT_DIR="${BUILD_SCRIPTS_DIR:-$(cd "$(dirname "$0")" && pwd)}"
export CB_WORKSPACE="${CB_WORKSPACE:-/workspace}"

echo "========================================"
echo "  STAGE_NAME=${STAGE_NAME}  HAS_IMAGE=${HAS_IMAGE}  HAS_PACKAGE=${HAS_PACKAGE}  TEST_KIND=${TEST_KIND:-none}"
echo "========================================"

# ── write-env ─────────────────────────────────────────────────────────
echo ""
echo "=== [write-env] ==="
bash "${SCRIPT_DIR}/write-build-env.sh" "${CB_WORKSPACE}"
# shellcheck disable=SC1091
source "${CB_WORKSPACE}/.cb-build-env"

# ── staging ───────────────────────────────────────────────────────────
if [[ "${STAGE_NAME}" == "staging" ]]; then

  if [[ "${TEST_KIND}" == "host_package" ]]; then
    echo ""
    echo "=== [package-staging-tests] ==="
    bash "${SCRIPT_DIR}/run-package-staging-tests.sh"
  fi

  if [[ "${HAS_IMAGE}" == true ]]; then
    echo ""
    echo "=== [compose-build] ==="
    bash "${SCRIPT_DIR}/docker-compose-action.sh" build

    if [[ "${TEST_KIND}" == "in_image" ]]; then
      echo ""
      echo "=== [pytest-in-image] ==="
      bash "${SCRIPT_DIR}/run-pytest-in-built-image.sh"
    fi

    echo ""
    echo "=== [compose-push] ==="
    bash "${SCRIPT_DIR}/docker-compose-action.sh" push
  fi

# ── production ────────────────────────────────────────────────────────
elif [[ "${STAGE_NAME}" == "production" ]]; then

  if [[ "${HAS_PACKAGE}" == true ]]; then
    echo ""
    echo "=== [wheels-and-pypi] ==="
    bash "${SCRIPT_DIR}/uv-build-and-twine.sh" "${CB_WORKSPACE}"
  fi

  if [[ "${HAS_IMAGE}" == true ]]; then
    echo ""
    echo "=== [promote-image] ==="
    bash "${SCRIPT_DIR}/promote-docker-tags.sh"

    if [[ -n "${CLOUD_RUN_SERVICE:-}" ]]; then
      : "${CLOUD_RUN_REGION:?CLOUD_RUN_REGION required when CLOUD_RUN_SERVICE is set}"
      echo ""
      echo "=== [deploy-cloud-run] ==="
      gcloud run deploy "${CLOUD_RUN_SERVICE}" \
        --project="${PROJECT_ID}" \
        --region="${CLOUD_RUN_REGION}" \
        --platform=managed \
        --image="${REGISTRY}/${PACKAGE_NAME}:${STAGE_NAME}_${PACKAGE_VERSION}" \
        --quiet
    fi
  fi

else
  echo "error: STAGE_NAME must be 'staging' or 'production', got '${STAGE_NAME}'" >&2
  exit 1
fi

echo ""
echo "========================================"
echo "  Pipeline complete: ${STAGE_NAME}"
echo "========================================"
