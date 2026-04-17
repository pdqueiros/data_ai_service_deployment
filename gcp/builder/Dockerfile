FROM gcr.io/google.com/cloudsdktool/cloud-sdk:slim

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
      ca-certificates curl python3 jq && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /root/.docker/cli-plugins && \
    ARCH="$(dpkg --print-architecture)" && \
    if [ "$ARCH" = "amd64" ]; then ARCH="x86_64"; fi && \
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${ARCH}" \
      -o /root/.docker/cli-plugins/docker-compose && \
    chmod +x /root/.docker/cli-plugins/docker-compose

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

# Pre-install Python CLI tools uv-managed — no system pip needed.
# keyring (+ AR plugin) is used by `uv sync` for private-index auth via
# UV_KEYRING_PROVIDER=subprocess; twine uploads wheels to AR PyPI.
RUN uv tool install keyring --with keyrings.google-artifactregistry-auth && \
    uv tool install twine
ENV UV_KEYRING_PROVIDER=subprocess

ENV BUILD_SCRIPTS_DIR=/opt/cicd_build/scripts
COPY scripts/ ${BUILD_SCRIPTS_DIR}/

ENTRYPOINT ["bash", "${BUILD_SCRIPTS_DIR}/pipeline.sh"]
