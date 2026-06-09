#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${WHISPRE_BASE_URL:-http://localhost:8000}"

exec python3 "$ROOT_DIR/scripts/smoke_test.py" --base-url "$BASE_URL" "$@"
