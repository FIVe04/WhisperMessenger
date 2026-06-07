#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
BROKER="${1:-kafka:9092}"

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

TOPICS=(
  auth.user.created.v1
  auth.device.registered.v1
  keys.prekey_bundle.updated.v1
  conversation.created.v1
  message.envelope.accepted.v1
  message.envelope.persisted.v1
  message.delivery.requested.v1
  message.delivery.status.v1
  realtime.push.requested.v1
)

for topic in "${TOPICS[@]}"; do
  "$CONTAINER_CLI" compose -f "$COMPOSE_FILE" exec -T kafka \
    kafka-topics --bootstrap-server "$BROKER" \
    --create --if-not-exists --topic "$topic" --partitions 6 --replication-factor 1
  echo "topic ready: $topic"
done
