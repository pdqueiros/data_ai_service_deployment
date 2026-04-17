#!/usr/bin/env bash
# Run pytest inside the just-built Docker image.
#
# Test dependencies must live in the consumer's pyproject.toml under
# [dependency-groups].checks (PEP 735). See run-package-staging-tests.sh
# for the convention. If the group is missing, we log and skip.
set -euo pipefail
CB_WORKSPACE="${CB_WORKSPACE:-/workspace}"
cd "${CB_WORKSPACE}"
source "${CB_WORKSPACE}/.cb-build-env"

if ! bash "$(dirname "$0")/has-checks-group.sh" pyproject.toml; then
  echo ">>> [dependency-groups].checks not defined in pyproject.toml — skipping in-image pytest."
  exit 0
fi

IMAGE_REF="${REGISTRY}/${PACKAGE_NAME}:${STAGE_NAME}_${PACKAGE_VERSION}"
COV="${PYTEST_COVERAGE_PATH:-src/}"

docker rm -f cb_pytest 2>/dev/null || true

rc=0
docker run --name cb_pytest --entrypoint=/bin/bash "${IMAGE_REF}" \
  -c "uv pip install --group checks && uv run pytest --cov=${COV} --cov-report=xml:/coverage.xml" \
  || rc=$?

docker cp cb_pytest:/coverage.xml "${CB_WORKSPACE}/coverage.xml" 2>/dev/null || true
docker rm -f cb_pytest 2>/dev/null || true

exit "${rc}"
