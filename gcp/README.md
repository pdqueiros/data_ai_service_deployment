# GCP Cloud Build — CI/CD Templates

Migrated from Azure DevOps pipelines. Uses **Google Cloud Build**, **Artifact Registry** (Docker + PyPI), and optional **Cloud Run** deploy.

**Read top-to-bottom in order:**

1. [Local tests](#1-local-tests) — validate end-to-end without any GCP credentials.
2. [GCP: initial setup](#2-gcp-initial-setup) — one-time project bootstrap (APIs, Artifact Registry, service account, GitHub, builder image).
3. [GCP: setup triggers](#3-gcp-setup-triggers) — per-microservice Cloud Build triggers (staging + production).
4. [GCP: setup consumer repo](#4-gcp-setup-consumer-repo) — files that must live in each microservice repo for the triggers to do anything useful.
5. [Reference](#reference) — substitutions, env vars, private indexes, Azure mapping.

> Sections 3 and 4 are both per-microservice. Operationally you'll do **4 first** (commit files, push branches), then **3** (create triggers). They're split so that "here are all the GCP-side `gcloud` commands" lives in one place and "here are all the files in the consumer repo" in another.

---

## Architecture

### Repository layout

```text
gcp/
├── README.md                             # this file — start here
├── .env.template                         # copy to .env and fill in
├── .gitignore                            # ignores .env
├── builder/
│   ├── Dockerfile                        # Custom builder image (cloud-sdk + scripts + compose + uv)
│   └── cloudbuild.yaml                   # Cloud Build config for rebuilding the image
├── scripts/                              # Reusable bash — baked into the builder image
│   ├── pipeline.sh                       # Single-script orchestrator (dispatches by HAS_IMAGE/HAS_PACKAGE/TEST_KIND + STAGE_NAME)
│   ├── write-build-env.sh                # Parses pyproject.toml → writes .cb-build-env
│   ├── docker-compose-action.sh          # docker compose build | push
│   ├── run-pytest-in-built-image.sh      # pytest inside the built Docker image
│   ├── run-package-staging-tests.sh      # uv sync + pytest on the host (package-only flows)
│   ├── uv-build-and-twine.sh             # uv build → twine upload (GCP) or local copy
│   └── promote-docker-tags.sh            # Re-tag staging_* → production_* + latest
├── templates/
│   └── cloudbuild.yaml                   # Single-file template — copy into consumer repos
├── local/
│   ├── docker-compose.registry.yaml      # Local Docker registry (registry:2 on :5000)
│   ├── docker-compose.pypi.yaml          # Local Python package server (pypiserver on :8080)
│   └── README.md
├── Makefile                              # Entry point: `make help` — drives the pipeline
│                                         #   in either MODE=local (default) or MODE=cloud
└── test_repo/                            # Example consumer repo (mimics a service)
    ├── cloudbuild.yaml
    ├── pyproject.toml
    ├── docker-compose-build.yaml
    ├── Dockerfile
    └── src/test_repo/
```

### How it works — the builder image pattern

All CI/CD scripts are baked into a **custom Docker image** (`scryn-pipeline`) stored in Artifact Registry. Each consumer repo contains a single `cloudbuild.yaml` (~20 lines) that runs this image as a build step. No `git clone`, no submodules.

```text
Consumer repo (e.g. data_vault)          Cloud Build triggers (see Setup below)
─────────────────────────────────        ──────────────────────────────────────────
cloudbuild.yaml  ─────────────────┐      <repo>-staging    → _STAGE_NAME=staging
pyproject.toml                     │      <repo>-production → _STAGE_NAME=production
docker-compose-build.yaml          │
Dockerfile                         │
src/                               │
                                   └──▶  scryn-pipeline (builder image)
                                           pipeline.sh
                                             ├── write-build-env.sh
                                             ├── docker-compose-action.sh build
                                             ├── run-pytest-in-built-image.sh  (if TEST_KIND=in_image)
                                             ├── docker-compose-action.sh push
                                             ├── uv-build-and-twine.sh         (production)
                                             ├── promote-docker-tags.sh        (production)
                                             └── gcloud run deploy             (optional, production)
```

### pipeline.sh — the dispatcher

`pipeline.sh` reads four env vars and runs the right sequence:

| Flag | Values | Meaning |
|------|--------|---------|
| `STAGE_NAME` | `staging` \| `production` | which half of the flow to run (set by trigger substitution) |
| `HAS_IMAGE` | `true` \| `false` | build+push Docker image (staging); retag it (production) |
| `HAS_PACKAGE` | `true` \| `false` | upload Python wheels to Artifact Registry PyPI (production only) |
| `TEST_KIND` | `""` \| `in_image` \| `host_package` | `in_image` = pytest inside built Docker image (requires `HAS_IMAGE=true`); `host_package` = uv sync + pytest on the host |

**Staging steps** (in order, each conditional):
1. `host_package` test → `run-package-staging-tests.sh`
2. `HAS_IMAGE` → `docker-compose-action.sh build`
3. `in_image` test → `run-pytest-in-built-image.sh`
4. `HAS_IMAGE` → `docker-compose-action.sh push`

**Production steps**:
1. `HAS_PACKAGE` → `uv-build-and-twine.sh` (build wheels + upload to PyPI)
2. `HAS_IMAGE` → `promote-docker-tags.sh` (retag staging image as `production_${VERSION}`)
3. `HAS_IMAGE` + `CLOUD_RUN_SERVICE` set → `gcloud run deploy` with the just-promoted image

At least one of `HAS_IMAGE` or `HAS_PACKAGE` must be `true`. `TEST_KIND=in_image` requires `HAS_IMAGE=true`. Invalid combinations fail fast with a clear error.

### Test dependencies: the `checks` group

Both test runners install a [PEP 735](https://peps.python.org/pep-0735/) `[dependency-groups].checks` group defined in your consumer's `pyproject.toml`:

```toml
[dependency-groups]
checks = [
    "pytest",
    "pytest-cov",
]
```

- Host-side: `uv sync --group checks` then `uv run pytest`.
- In-image: `uv pip install --group checks` then `uv run pytest` inside the already-built image.

If the `checks` group is absent, the test step logs a notice and exits 0 — the rest of the pipeline (build, push, promote, wheels) still runs. Lets you add a repo to the pipeline before its tests are written, and keeps the production image free of test-only dependencies.

### Central env file: `.cb-build-env`

The first thing `pipeline.sh` does is run `write-build-env.sh`, which reads `pyproject.toml` and writes `.cb-build-env`:

| Variable | Source |
|----------|--------|
| `PACKAGE_NAME` | `pyproject.toml` `[project] name` |
| `PACKAGE_VERSION` | `pyproject.toml` `[project] version` |
| `PYTHON_VERSION` | `pyproject.toml` `requires-python` |
| `REGISTRY` | `ARTIFACT_REGISTRY_LOCATION-docker.pkg.dev/PROJECT_ID/ARTIFACT_REGISTRY_DOCKER` (or `REGISTRY_OVERRIDE`) |
| `PYPI_UPLOAD_URL` | `ARTIFACT_REGISTRY_LOCATION-python.pkg.dev/PROJECT_ID/ARTIFACT_REGISTRY_PYPI/` |
| `PYPI_INDEX_URL` | `ARTIFACT_REGISTRY_LOCATION-python.pkg.dev/PROJECT_ID/ARTIFACT_REGISTRY_PYPI/simple/` (or `PYPI_INDEX_URL_OVERRIDE` locally) |
| `IMAGE_TAG` | `${STAGE_NAME}_${PACKAGE_VERSION}` |

All downstream scripts `source .cb-build-env`. Consumer repos never edit it directly.

---

## 1. Local tests

Run the full CI/CD pipeline on your laptop, no GCP credentials needed. Two local containers mirror what Artifact Registry provides:

| GCP | Local equivalent | Container |
|-----|------------------|-----------|
| Artifact Registry Docker (`REGION-docker.pkg.dev/...`) | `localhost:5000` | `registry:2` ([`local/docker-compose.registry.yaml`](local/docker-compose.registry.yaml)) |
| Artifact Registry PyPI (`REGION-python.pkg.dev/...`) | `localhost:8080` | `pypiserver/pypiserver` ([`local/docker-compose.pypi.yaml`](local/docker-compose.pypi.yaml)) |

The [`Makefile`](Makefile) auto-starts both containers in `MODE=local` (the default) and runs `scripts/pipeline.sh` against `./test_repo`. No builder image required.

### 1.1 Prerequisites

1. **Docker** running.
2. **Docker daemon** trusts `localhost:5000` as insecure registry:
   - **Linux** — edit `/etc/docker/daemon.json`:
     ```json
     { "insecure-registries": ["localhost:5000", "127.0.0.1:5000"] }
     ```
     then `sudo systemctl restart docker`.
   - **Docker Desktop** — Settings → Docker Engine → same array → Apply & Restart.
3. **uv** installed (optional; used for wheel builds on the host in `package-only` flows).

### 1.2 Quick start

Run from the `gcp/` directory. Default target is `./test_repo`; override with `REPO=/path/to/my-service`.

```bash
make help                                # list every target
make registry-up                         # initializes the pypi and docker registry container
make package-and-image                   # most common staging dev loop
make package-and-image-full              # staging then production, end-to-end
make all                                 # every variant end-to-end
make REPO=/path/to/my-service image-only
```

Each variant target runs one variant/stage combination. End-to-end targets (`*-full`) chain staging then production. On every run the Makefile:

- auto-starts `localhost:5000` and `localhost:8080`,
- exports the `*_OVERRIDE` env vars so `pipeline.sh` hits local services,
- runs the pipeline,
- verifies the image round-trip by `docker pull`-ing from `localhost:5000`,
- cleans up per-run temp files (`.cb-build-env`, `dist/`, `coverage.xml`) on exit.

### 1.3 Inspecting local artifacts

```bash
curl -s http://localhost:5000/v2/_catalog
curl -s http://localhost:5000/v2/scryn-local/test_repo/tags/list

curl -s http://localhost:8080/simple/
uv pip install --index-url http://localhost:8080/simple/ test-repo
```

### 1.4 Cleanup

```bash
make clean                               # remove per-run artifacts from $(REPO)
make registry-down                       # stop local registries (keeps data)
make registry-reset                      # stop local registries AND delete all data
```

### 1.5 Running against real GCP from your laptop (`MODE=cloud`)

The same Makefile drives the real GCP pipeline — the only difference is the infra env. After finishing Section 2 (initial setup), you can one-off debug against the real Artifact Registry:

```bash
source gcp/.env                          # populates PROJECT_ID, ARTIFACT_REGISTRY_*, etc.
gcloud auth login
cd gcp
MODE=cloud make package-and-image
```

`MODE=cloud` disables local container auto-start and the `*_OVERRIDE` exports. Missing `PROJECT_ID` / `ARTIFACT_REGISTRY_*` vars fail fast with a clear error.

> Day-to-day you won't use `MODE=cloud` — Cloud Build triggers run the pipeline inside the builder image on every push. `MODE=cloud` is only for one-off debugging.

---

## 2. GCP: initial setup

One-time per GCP project. Everything is explicit `gcloud` — no scripts run on your behalf. Fill in [`.env.template`](.env.template) once, `source` it, then work down the list.

### 2.1 Prep `.env`

```bash
cp gcp/.env.template gcp/.env
# Edit gcp/.env — see the file for field descriptions.
source gcp/.env
```

Every command below uses `$PROJECT_ID`, `$REGION`, etc. from `.env`.

### 2.2 Enable APIs


Verify enabled APIs
```bash
gcloud services list --enabled --project="$PROJECT_ID"   --filter="NAME:(cloudbuild.googleapis.com OR artifactregistry.googleapis.com OR secretmanager.googleapis.com OR run.googleapis.com)"
```

And enable it:
```bash
gcloud services enable  cloudbuild.googleapis.com  artifactregistry.googleapis.com   secretmanager.googleapis.com   run.googleapis.com   --project="$PROJECT_ID"
```

### 2.3 Create Artifact Registry repos

```bash
gcloud artifacts repositories list \
  --project="$PROJECT_ID" --location="$REGION"
```

```bash
gcloud artifacts repositories create "$ARTIFACT_REGISTRY_DOCKER" --repository-format=docker --location="$REGION" --project="$PROJECT_ID"

gcloud artifacts repositories create "$ARTIFACT_REGISTRY_PYPI" --repository-format=python --location="$REGION" --project="$PROJECT_ID"
```

### 2.4 Cloud Build service account + IAM

Projects created after ~April 2024 no longer auto-provision the legacy `${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com`. List what you have:

```bash
gcloud iam service-accounts list --project="$PROJECT_ID" --format='table(email,disabled,displayName)'
```

Pick one of:

- The Compute default SA (`${PROJECT_NUMBER}-compute@developer.gserviceaccount.com`) — already has broad roles, easiest to get working.
- A dedicated SA you create (cleaner for production):

  ```bash
  gcloud iam service-accounts create scryn-cicd-sa \
    --display-name="Scryn CI/CD Service Account" --project="$PROJECT_ID"
  ```

Put the full resource path in `CLOUD_BUILD_SA` in `gcp/.env`, e.g. `projects/$PROJECT_ID/serviceAccounts/${PROJECT_NUMBER}-compute@developer.gserviceaccount.com`, then `source gcp/.env` again.

Grant roles to that SA:

```bash
CB_SA_EMAIL="${CLOUD_BUILD_SA##*/}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$CB_SA_EMAIL" --role=roles/artifactregistry.writer --condition=None

gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$CB_SA_EMAIL" --role=roles/logging.logWriter --condition=None
```

If `CB_SA_EMAIL` is **not** the Compute default (which already has `roles/editor`), also grant `roles/cloudbuild.builds.builder`:

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$CB_SA_EMAIL" --role=roles/cloudbuild.builds.builder --condition=None
```

Finally, grant yourself `actAs` on the SA so you can reference it in triggers:

```bash
gcloud iam service-accounts add-iam-policy-binding "$CB_SA_EMAIL" --project="$PROJECT_ID" --member="user:$(gcloud config get-value account)"  --role=roles/iam.serviceAccountUser
```

### 2.5 GitHub host connection

Cloud Build triggers need a **2nd-generation** repository connection so Cloud Build can clone your GitHub org on each push. This is a one-time, Console-only step — there's no `gcloud` equivalent for the initial GitHub App consent.

**In the GCP Console:**

1. Open **Cloud Build** → **Repositories (2nd gen)** → **Manage connections**.
2. **Create host connection** → choose **GitHub**. Create it in the same region as your Artifact Registry (`$REGION` in `gcp/.env`).
3. Authorize the **Google Cloud Build** GitHub App on the GitHub organization (or user) that owns your repositories. Grant it access to the specific repos you want to build (or all org repos).
4. Back on **Repositories (2nd gen)**, **Link repository** for every microservice you want to build, plus the deployment repo itself (needed for the builder-image rebuild trigger in 2.6).

> If your org restricts third-party GitHub Apps, an org admin must approve the Cloud Build app under **GitHub** → **Settings** → **GitHub Apps** → **Installed GitHub Apps** before step 3 will succeed.

Put the connection name into `gcp/.env` and `source` again:

```bash
export CONNECTION_NAME="..."   # the connection you just created
```

Verify:

```bash
gcloud builds connections describe "$CONNECTION_NAME" --project="$PROJECT_ID" --region="$REGION"

gcloud builds repositories list --project="$PROJECT_ID" --region="$REGION" --connection="$CONNECTION_NAME"
```

The `NAME` column in the second output is the linked-repo name you'll pass as `DEPLOY_REPO_NAME` (Section 2.6) and `CONSUMER_REPO` (Section 3) — **not** the raw GitHub slug.

> **Push vs PR:** all trigger commands in this README use `--branch-pattern`, so they fire only on pushes to the matching branch, not on pull requests. This matches the old Azure DevOps behavior.

### 2.6 Builder image

**First build** — runs once so the image exists before any consumer trigger fires:

```bash
gcloud builds submit \
  --config=gcp/builder/cloudbuild.yaml \
  --project="$PROJECT_ID" --region="$REGION" \
  --substitutions="_ARTIFACT_REGISTRY_LOCATION=$REGION,_ARTIFACT_REGISTRY_DOCKER=$ARTIFACT_REGISTRY_DOCKER,_IMAGE_NAME=$IMAGE_NAME"
```

**Auto-rebuild trigger** — rebuilds the image whenever `gcp/scripts/**`, `gcp/builder/Dockerfile`, or `gcp/builder/cloudbuild.yaml` change on `main`. Set `DEPLOY_REPO_NAME` to the linked name of **this deployment repo** (as listed in the 2.5 repositories check):

```bash
DEPLOY_REPO_NAME="pdqueiros-data_ai_service_deployment"  # <- linked name of THIS repo

gcloud builds triggers create github \
  --name="${IMAGE_NAME}-builder" \
  --project="$PROJECT_ID" --region="$REGION" \
  --repository="projects/$PROJECT_NUMBER/locations/$REGION/connections/$CONNECTION_NAME/repositories/$DEPLOY_REPO_NAME" \
  --branch-pattern='^main$' \
  --build-config=gcp/builder/cloudbuild.yaml \
  --included-files='gcp/scripts/**,gcp/builder/Dockerfile,gcp/builder/cloudbuild.yaml' \
  --service-account="$CLOUD_BUILD_SA" \
  --substitutions="_ARTIFACT_REGISTRY_LOCATION=$REGION,_ARTIFACT_REGISTRY_DOCKER=$ARTIFACT_REGISTRY_DOCKER,_IMAGE_NAME=$IMAGE_NAME"
```

After this section, the GCP project is fully wired. All further work is per-microservice — see Sections 3 and 4.

---

## 3. GCP: setup triggers

One pair of triggers (staging + production) per consumer microservice repo.

> **Prerequisite**: the consumer repo must be linked in the GitHub connection (Section 2.5) and must contain the files from Section 4 on the `staging` / `production` branches. Triggers can be created before the files exist, but they won't *fire* on a push until `CHANGELOG.md` (the path filter below) shows up on the matching branch.

### 3.1 Staging + production triggers

Set `CONSUMER_REPO` to the linked name for that microservice, then run both commands:

```bash
CONSUMER_REPO="pdqueiros-test_repo"          # real linked name (has underscore)
TRIGGER_BASE="${CONSUMER_REPO//_/-}"         # pdqueiros-test-repo (no underscores)

SUBS="_ARTIFACT_REGISTRY_LOCATION=$REGION,_ARTIFACT_REGISTRY_DOCKER=$ARTIFACT_REGISTRY_DOCKER,_ARTIFACT_REGISTRY_PYPI=$ARTIFACT_REGISTRY_PYPI,_IMAGE_NAME=$IMAGE_NAME"
REPO_PATH="projects/$PROJECT_NUMBER/locations/$REGION/connections/$CONNECTION_NAME/repositories/$CONSUMER_REPO"

gcloud builds triggers create github \
  --name="${TRIGGER_BASE}-staging" \
  --project="$PROJECT_ID" --region="$REGION" \
  --repository="$REPO_PATH" \
  --branch-pattern='^staging$' \
  --build-config=cloudbuild.yaml \
  --included-files='CHANGELOG.md' \
  --service-account="$CLOUD_BUILD_SA" \
  --substitutions="_STAGE_NAME=staging,$SUBS"

gcloud builds triggers create github \
  --name="${TRIGGER_BASE}-production" \
  --project="$PROJECT_ID" --region="$REGION" \
  --repository="$REPO_PATH" \
  --branch-pattern='^production$' \
  --build-config=cloudbuild.yaml \
  --included-files='CHANGELOG.md' \
  --service-account="$CLOUD_BUILD_SA" \
  --substitutions="_STAGE_NAME=production,$SUBS"
```

The triggers only fire when a push to the matching branch includes a change to `CHANGELOG.md`. That's intentional — it's how the old Azure pipelines gated staging/production releases, and it means ordinary feature-branch work never kicks off a build.

### 3.2 Verify

```bash
# List all triggers
gcloud builds triggers list \
  --project="$PROJECT_ID" --region="$REGION" \
  --format='table(
    name,
    repositoryEventConfig.repository.basename():label=REPO,
    repositoryEventConfig.push.branch:label=BRANCH
  )'

# Manual test run (fires without a git push)
gcloud builds triggers run pdqueiros-test-repo-staging --project="$PROJECT_ID" --region="$REGION" --branch=staging
```

The manual run is the fastest feedback loop when first onboarding a repo — it bypasses the `--included-files` filter so you don't need to craft a `CHANGELOG.md` commit yet.

You can also check it on the GCP UI [here](https://console.cloud.google.com/artifacts?project=scryn-co)

---

## 4. GCP: setup consumer repo

What every microservice repo needs so the triggers in Section 3 actually do something. See [`test_repo/`](test_repo/) for a complete worked example.

### 4.1 Required files at the repo root

| File | Purpose |
|------|---------|
| `cloudbuild.yaml` | Copied from [`templates/cloudbuild.yaml`](templates/cloudbuild.yaml); edited for this repo (see 4.2). |
| `Dockerfile` | Builds the runtime image (if `HAS_IMAGE=true`). |
| `docker-compose-build.yaml` | Tells `docker compose` which image to build and wires private-index build args (see 4.3). |
| `pyproject.toml` | Package metadata + `[dependency-groups].checks` if you want tests (see Architecture § Test dependencies). |
| `CHANGELOG.md` | Gate file for the triggers. Bump it to release — pushes that don't touch it don't build. |
| `src/…` | Your package code (standard layout). |

### 4.2 Configure pipeline flags in `cloudbuild.yaml`

Copy [`templates/cloudbuild.yaml`](templates/cloudbuild.yaml) into the repo root, then edit **only** the three pipeline flags in the step's `env:` block. Everything else is supplied by the trigger at build time.

```yaml
# consumer-repo/cloudbuild.yaml
substitutions:
  _STAGE_NAME: ""
  _ARTIFACT_REGISTRY_LOCATION: ""
  _ARTIFACT_REGISTRY_DOCKER: ""
  _ARTIFACT_REGISTRY_PYPI: ""
  _IMAGE_NAME: ""
timeout: 2400s
options:
  logging: CLOUD_LOGGING_ONLY   # required when --service-account is set on the trigger
steps:
  - name: ${_ARTIFACT_REGISTRY_LOCATION}-docker.pkg.dev/$PROJECT_ID/${_ARTIFACT_REGISTRY_DOCKER}/${_IMAGE_NAME}
    env:
      - HAS_IMAGE=true          # build+push Docker image
      - HAS_PACKAGE=true        # upload wheels in production
      - TEST_KIND=in_image      # "" | in_image | host_package
      - PROJECT_ID=$PROJECT_ID  # built-in substitution; forward into step container
      - STAGE_NAME=${_STAGE_NAME}
      - ARTIFACT_REGISTRY_LOCATION=${_ARTIFACT_REGISTRY_LOCATION}
      - ARTIFACT_REGISTRY_DOCKER=${_ARTIFACT_REGISTRY_DOCKER}
      - ARTIFACT_REGISTRY_PYPI=${_ARTIFACT_REGISTRY_PYPI}
      # Optional Cloud Run deploy after production image promotion — append:
      # - CLOUD_RUN_SERVICE=<svc>
      # - CLOUD_RUN_REGION=<region>
```

See the [Azure → GCP mapping](#azure--gcp-mapping) table at the bottom for the flag combination that matches each Azure template you were using.

### 4.3 Private Python index auth

If your consumer repo depends on private packages hosted in Artifact Registry PyPI, auth is automatic — but the consumer's `docker-compose-build.yaml` and `Dockerfile` must propagate two build args.

**`docker-compose-build.yaml`:**

```yaml
build:
  args:
    - UV_INDEX_PASSWORD=${UV_INDEX_PASSWORD:-}
    - PYPI_INDEX_URL=${PYPI_INDEX_URL:-}
```

**`Dockerfile`:**

```dockerfile
ARG UV_INDEX_PASSWORD=""
ARG PYPI_INDEX_URL=""
RUN if [ -n "$PYPI_INDEX_URL" ] && [ -n "$UV_INDEX_PASSWORD" ]; then \
      export UV_EXTRA_INDEX_URL="https://oauth2accesstoken:${UV_INDEX_PASSWORD}@${PYPI_INDEX_URL#https://}"; \
    fi && \
    uv sync --all-extras
```

At build time, `docker-compose-action.sh build` fetches a short-lived OAuth2 token via `gcloud auth print-access-token` and passes both args into the build. When they're empty (e.g. local testing with no private deps), `uv sync` falls back to public PyPI. See [`test_repo/Dockerfile`](test_repo/Dockerfile) for the full working example.

**Host-side package tests** (`run-package-staging-tests.sh`) use `keyrings.google-artifactregistry-auth` which auto-authenticates via the Cloud Build service account — nothing to wire manually.

### 4.4 Optional: Cloud Run deploy after promotion

To deploy the freshly-promoted production image to Cloud Run, uncomment the two env entries in `cloudbuild.yaml`:

```yaml
      - CLOUD_RUN_SERVICE=data-vault-api
      - CLOUD_RUN_REGION=europe-west1
```

Grant the Cloud Build SA `roles/run.admin` + `roles/iam.serviceAccountUser` (in addition to the roles from Section 2.4):

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$CB_SA_EMAIL" --role=roles/run.admin --condition=None
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$CB_SA_EMAIL" --role=roles/iam.serviceAccountUser --condition=None
```

### 4.5 Optional: third-party private indexes via Secret Manager

If a repo pulls from a non-GCP private index (e.g. internal Artifactory, test PyPI), store the credential in Secret Manager and expose it to the build step by adding `availableSecrets` to the consumer `cloudbuild.yaml`:

```yaml
availableSecrets:
  secretManager:
    - versionName: projects/$PROJECT_ID/secrets/third-party-index-password/versions/latest
      env: UV_INDEX_PASSWORD
```

---

## Reference

### Substitutions vs step `env:`

Consumer `cloudbuild.yaml` files split knobs into two blocks. **Substitutions** are trigger-filled infra (consumer leaves defaults as `""`); **env vars** are hardcoded per-repo pipeline behavior.

| Substitution | Meaning | Source |
|--------------|---------|--------|
| `_STAGE_NAME` | `staging` or `production` | Trigger (Section 3) |
| `_ARTIFACT_REGISTRY_LOCATION` | AR region | Trigger, from `$REGION` |
| `_ARTIFACT_REGISTRY_DOCKER` | AR Docker repo | Trigger, from `$ARTIFACT_REGISTRY_DOCKER` |
| `_ARTIFACT_REGISTRY_PYPI` | AR PyPI repo | Trigger, from `$ARTIFACT_REGISTRY_PYPI` |
| `_IMAGE_NAME` | Builder image name | Trigger, from `$IMAGE_NAME` |

| Step env var | Meaning |
|--------------|---------|
| `HAS_IMAGE` | `true`/`false` — build+push Docker image |
| `HAS_PACKAGE` | `true`/`false` — publish Python wheels |
| `TEST_KIND` | `""`, `in_image`, or `host_package` |
| `CLOUD_RUN_SERVICE` | Cloud Run service name (optional — omit or leave unset to skip deploy) |
| `CLOUD_RUN_REGION` | Cloud Run region (required when `CLOUD_RUN_SERVICE` is set) |

Built-in `PROJECT_ID` is supplied automatically by Cloud Build. No infra values are hardcoded in `cloudbuild.yaml` or in the scripts — everything traces back to `gcp/.env`.

### Makefile env var reference (local mode)

| Variable | When set | Effect |
|----------|----------|--------|
| `MODE` | `local` (default) / `cloud` | Selects which infra env the Makefile exports before invoking `pipeline.sh`. |
| `REPO` | Path (default `./test_repo`) | Consumer repo to run the pipeline against. |
| `REGISTRY_OVERRIDE` | Non-empty | `REGISTRY` uses this instead of Artifact Registry. Set automatically in `MODE=local`. |
| `PYPI_UPLOAD_URL_OVERRIDE` | Non-empty | Written as `PYPI_UPLOAD_URL`; `twine` uses anonymous `local/local` auth. Set automatically in `MODE=local`. |
| `PYPI_INDEX_URL_OVERRIDE` | Non-empty | Written as `PYPI_INDEX_URL`; used as a build arg by `docker-compose-action.sh build`. Set automatically in `MODE=local`. |
| `CB_WORKSPACE` | Optional | Root directory with `pyproject.toml`. Defaults to `/workspace` in the builder image; the Makefile sets it to `$(REPO)`. |

### PyPI uploads

Production steps upload wheels via `twine` with `oauth2accesstoken` + `gcloud auth print-access-token`. The Cloud Build SA needs `roles/artifactregistry.writer` (granted in 2.4).

### Runtime deployment

| Target | How images get there |
|--------|---------------------|
| **Cloud Run** | Add `CLOUD_RUN_SERVICE` + `CLOUD_RUN_REGION` to the `env:` block in the consumer's `cloudbuild.yaml`. `pipeline.sh` runs `gcloud run deploy` after promoting the image. Grant `roles/run.admin` + `roles/iam.serviceAccountUser` (see 4.4). |
| **GCE + Docker Compose** | `gcloud auth configure-docker REGION-docker.pkg.dev` then `docker pull`. |
| **GKE** | Reference the Artifact Registry image in Kubernetes manifests. |

### Azure → GCP mapping

Each Azure template maps to a combination of the three pipeline flags in the consumer's `cloudbuild.yaml` (`steps[0].env`):

| Azure template | `HAS_IMAGE` | `HAS_PACKAGE` | `TEST_KIND` |
|----------------|:-----------:|:-------------:|:-----------:|
| `azure/package_and_image/` | `true` | `true` | `in_image` |
| `azure/package_and_image_no_test/` | `true` | `true` | `""` |
| `azure/image_only/` | `true` | `false` | `in_image` |
| `azure/image_only_no_test/` | `true` | `false` | `""` |
| `azure/package_only/` | `false` | `true` | `host_package` |
| `azure/package_only_no_test/` | `false` | `true` | `""` |
| `azure/package_test_image/` | `true` | `true` | `host_package` |
