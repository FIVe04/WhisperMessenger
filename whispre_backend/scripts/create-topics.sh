#!/usr/bin/env bash
set -euo pipefail

BROKER="${1:-localhost:9094}"

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
  docker exec -it whispre_backend-kafka-1 kafka-topics --bootstrap-server "$BROKER" \
    --create --if-not-exists --topic "$topic" --partitions 6 --replication-factor 1 || true
  echo "topic ready: $topic"
done
