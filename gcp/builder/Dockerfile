FROM gcr.io/google.com/cloudsdktool/cloud-sdk:alpine

RUN set -eux; \
    apk add --no-cache ca-certificates curl bash python3 jq docker-cli; \
    mkdir -p /root/.docker/cli-plugins; \
    ARCH="$(uname -m)"; \
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${ARCH}" \
      -o /root/.docker/cli-plugins/docker-compose; \
    chmod +x /root/.docker/cli-plugins/docker-compose; \
    curl -LsSf https://astral.sh/uv/install.sh | sh; \
    /root/.local/bin/uv tool install keyring --with keyrings.google-artifactregistry-auth; \
    /root/.local/bin/uv tool install twine; \
    /root/.local/bin/uv cache clean; \
    rm -rf /root/.cache /tmp/*

# keyring (+ AR plugin) is used by `uv sync` for private-index auth via
# UV_KEYRING_PROVIDER=subprocess; twine uploads wheels to AR PyPI.
ENV PATH="/root/.local/bin:${PATH}" \
    UV_KEYRING_PROVIDER=subprocess \
    BUILD_SCRIPTS_DIR=/opt/cicd_build/scripts

COPY scripts/ ${BUILD_SCRIPTS_DIR}/

ENTRYPOINT bash ${BUILD_SCRIPTS_DIR}/pipeline.sh
