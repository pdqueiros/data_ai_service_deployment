#!/usr/bin/env bash
# Exit 0 if pyproject.toml defines [dependency-groups].checks (PEP 735), 1 otherwise.
# Used by the pipeline to decide whether to run pytest or skip gracefully.
# Usage: has-checks-group.sh [PYPROJECT_PATH]   (default: ./pyproject.toml)
set -euo pipefail
python3 - "${1:-pyproject.toml}" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
sys.exit(0 if "checks" in data.get("dependency-groups", {}) else 1)
PY
