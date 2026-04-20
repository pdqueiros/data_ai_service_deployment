#!/usr/bin/env bash
# Pull staging tag, retag as production_<version> and latest, push.
set -euo pipefail
CB_WORKSPACE="${CB_WORKSPACE:-/workspace}"
source "${CB_WORKSPACE}/.cb-build-env"
IMAGE_NAME="${REGISTRY}/${PACKAGE_NAME}"
# Production promotion always pulls the matching staging tag.
IMAGE_NAME_STAGING="${IMAGE_NAME}:staging_${PACKAGE_VERSION}"
docker pull "${IMAGE_NAME_STAGING}"
docker tag "${IMAGE_NAME_STAGING}" "${IMAGE_NAME}:production_${PACKAGE_VERSION}"
docker tag "${IMAGE_NAME_STAGING}" "${IMAGE_NAME}:latest"
docker push "${IMAGE_NAME}:production_${PACKAGE_VERSION}"
docker push "${IMAGE_NAME}:latest"
