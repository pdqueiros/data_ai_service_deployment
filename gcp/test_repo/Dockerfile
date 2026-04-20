# syntax=docker/dockerfile:1.7
FROM python:3.13-slim AS build
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

RUN mkdir /app
COPY ./uv.lock /app/uv.lock
COPY ./pyproject.toml /app/pyproject.toml
COPY ./README.md /app/README.md

RUN echo $(grep -m 1 'version' /app/pyproject.toml | sed -E 's/version = "(.*)"/\1/') > /app/__version__

COPY ./src/ /app/src/
WORKDIR "/app"

RUN --mount=type=secret,id=uv_index_gcp_username \
    --mount=type=secret,id=uv_index_gcp_password \
    export UV_INDEX_GCP_USERNAME="$(cat /run/secrets/uv_index_gcp_username)" && \
    export UV_INDEX_GCP_PASSWORD="$(cat /run/secrets/uv_index_gcp_password)" && \
    uv sync --all-extras
ENV PATH="/app/.venv/bin:$PATH"

FROM build
RUN apt-get autoremove -y && apt-get clean -y
