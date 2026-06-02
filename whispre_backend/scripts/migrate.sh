#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATIONS_DIR="$ROOT_DIR/db/migrations"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required"
  exit 1
fi

for migration in "$MIGRATIONS_DIR"/*.sql; do
  echo "Applying migration: $(basename "$migration")"
  docker compose -f "$ROOT_DIR/docker-compose.yml" exec -T postgres \
    psql -U whispre -d whispre < "$migration"
done

echo "Migrations applied"
