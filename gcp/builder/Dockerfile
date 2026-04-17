FROM gcr.io/google.com/cloudsdktool/cloud-sdk:alpine

RUN set -eux; \
    apk add --no-cache ca-certificates curl bash python3 jq docker-cli docker-cli-compose; \
    curl -LsSf https://astral.sh/uv/install.sh | sh; \
    /root/.local/bin/uv tool install keyring --with keyrings.google-artifactregistry-auth; \
    /root/.local/bin/uv tool install twine; \
    /root/.local/bin/uv cache clean; \
    rm -rf /root/.cache /tmp/*

# keyring (+ AR plugin) is used by `uv sync` for private-index auth via
# UV_KEYRING_PROVIDER=subprocess; twine uploads wheels to AR PyPI.
# UV_TOOL_* pin the pre-installed tool locations so they're discoverable
# regardless of $HOME (Cloud Build overrides HOME=/builder/home per step).
ENV PATH="/root/.local/bin:${PATH}" \
    UV_KEYRING_PROVIDER=subprocess \
    UV_TOOL_DIR=/root/.local/share/uv/tools \
    UV_TOOL_BIN_DIR=/root/.local/bin \
    BUILD_SCRIPTS_DIR=/opt/cicd_build/scripts

COPY scripts/ ${BUILD_SCRIPTS_DIR}/

ENTRYPOINT bash ${BUILD_SCRIPTS_DIR}/pipeline.sh
