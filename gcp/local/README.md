# Local CI/CD harness

Local-only compose files that mirror the GCP Artifact Registry services the pipeline talks to:

| File | Purpose |
|------|---------|
| [`docker-compose.registry.yaml`](docker-compose.registry.yaml) | `registry:2` on `localhost:5000` — local Docker registry |
| [`docker-compose.pypi.yaml`](docker-compose.pypi.yaml) | `pypiserver/pypiserver` on `localhost:8080` — local PyPI server |

Both are auto-started by the top-level [`Makefile`](../Makefile) when you run any variant target in the default `MODE=local`. See the **Local Testing** section in [`../README.md`](../README.md) for the full flow.

## Docker daemon: allow insecure registry

The `registry:2` image uses HTTP, so Docker must trust `localhost:5000`:

- **Linux** — `/etc/docker/daemon.json`:

  ```json
  { "insecure-registries": ["localhost:5000", "127.0.0.1:5000"] }
  ```

  Then `sudo systemctl restart docker`.

- **Docker Desktop** — Settings → Docker Engine → add the same `insecure-registries` array → Apply & Restart.

## Manual control

```bash
make registry-up       # start Docker (:5000) + PyPI (:8080) registries
make registry-down     # stop both (keeps uploaded images and wheels)
make registry-reset    # stop both AND wipe all images and wheels
```

## Environment overrides (set automatically by `MODE=local`)

| Variable | Value used locally |
|----------|-------------------|
| `REGISTRY_OVERRIDE` | `localhost:5000/scryn-local` |
| `PYPI_UPLOAD_URL_OVERRIDE` | `http://localhost:8080/` |
| `PYPI_INDEX_URL_OVERRIDE` | `http://localhost:8080/simple/` |
| `CB_WORKSPACE` | absolute path to `$(REPO)` (default `gcp/test_repo`) |

Switch to `MODE=cloud` to hit real Artifact Registry instead.
