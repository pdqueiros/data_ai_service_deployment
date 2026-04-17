#!/usr/bin/env bash
# Runs `docker compose <build|push>` against the consumer repo's compose file,
# with REGISTRY and (for build) UV_INDEX_PASSWORD / PYPI_INDEX_URL exported so
# private-index auth works during `uv sync`.
#
# Usage: docker-compose-action.sh <build|push>
set -euo pipefail

action="${1:-}"
case "$action" in
  build|push) ;;
  *) echo "usage: $0 <build|push>" >&2; exit 2 ;;
esac

CB_WORKSPACE="${CB_WORKSPACE:-/workspace}"
source "${CB_WORKSPACE}/.cb-build-env"

base="$(basename "${DOCKER_COMPOSE_FILE}")"
if [[ -f "${CB_WORKSPACE}/${DOCKER_COMPOSE_FILE}" ]]; then
  compose_file="${CB_WORKSPACE}/${DOCKER_COMPOSE_FILE}"
else
  compose_file="$(find "${CB_WORKSPACE}" -name "${base}" -print -quit)"
fi
if [[ -z "${compose_file}" ]]; then
  echo "error: could not find ${DOCKER_COMPOSE_FILE} under ${CB_WORKSPACE}" >&2
  exit 1
fi

cd "$(dirname "${compose_file}")"
export REGISTRY

if [[ "$action" == "build" ]]; then
  export PYPI_INDEX_URL="${PYPI_INDEX_URL:-}"
  if [[ -z "${UV_INDEX_PASSWORD:-}" ]] && [[ -z "${REGISTRY_OVERRIDE:-}" ]] && command -v gcloud &>/dev/null; then
    UV_INDEX_PASSWORD="$(gcloud auth print-access-token)"
  fi
  export UV_INDEX_PASSWORD="${UV_INDEX_PASSWORD:-}"
fi

docker compose -f "$(basename "${compose_file}")" "$action"
