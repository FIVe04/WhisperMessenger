#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATIONS_DIR="$ROOT_DIR/db/migrations"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"

if [[ -n "${CONTAINER_CLI:-}" ]]; then
  :
elif command -v docker >/dev/null 2>&1; then
  CONTAINER_CLI="docker"
elif command -v podman >/dev/null 2>&1; then
  CONTAINER_CLI="podman"
else
  echo "docker or podman is required"
  exit 1
fi

for migration in "$MIGRATIONS_DIR"/*.sql; do
  echo "Applying migration: $(basename "$migration")"
  "$CONTAINER_CLI" compose -f "$COMPOSE_FILE" exec -T postgres \
    psql -U whispre -d whispre < "$migration"
done

echo "Migrations applied"
