# test_repo

Minimal repo for testing the GCP CI/CD pipeline locally.

## Usage

```bash
# Start local Docker registry
docker compose -f ../local/docker-compose.registry.yaml up -d

# Run the CI/CD locally
bash run-local-test.sh
```
