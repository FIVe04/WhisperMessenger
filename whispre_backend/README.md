# Whispre Backend (Microservices Scaffold)

Backend scaffold for E2E messenger MVP with Kafka-based eventing.

## Services

- api-gateway (`:8000`)
- auth-service (`:8001`)
- user-service (`:8002`)
- key-service (`:8003`)
- conversation-service (`:8004`)
- message-service (`:8005`)
- realtime-service (`:8006`)
- notification-service (`:8007`)

Infrastructure:

- Kafka (`localhost:9094`)
- Zookeeper (`localhost:2181`)
- PostgreSQL (`localhost:5432`)
- Redis (`localhost:6379`)

## Quick start

```bash
cd whispre_backend
docker compose up --build -d
./scripts/migrate.sh
```

Health checks:

```bash
curl http://localhost:8000/health
curl http://localhost:8001/health
curl http://localhost:8002/health
curl http://localhost:8003/health
curl http://localhost:8004/health
curl http://localhost:8005/health
curl http://localhost:8006/health
curl http://localhost:8007/health
```

Gateway entrypoint:

```bash
curl http://localhost:8000/v1/auth/login
```

Create Kafka topics:

```bash
./scripts/create-topics.sh
```

## Notes

- Implemented endpoints:
  - `auth-service`: `/v1/auth/register`, `/v1/auth/login`, `/v1/auth/refresh`, `/v1/auth/logout`, `/v1/auth/devices/register`
  - `user-service`: `/v1/users/search`, `/v1/users/me`
  - `key-service`: `/v1/keys/users/{user_id}/bundles`, `/v1/keys/users/{user_id}/one-time-prekey/claim`, `/v1/keys/devices/{device_id}/bundle`, `/v1/keys/devices/{device_id}/one-time-prekeys/replenish`
  - `conversation-service`: `/v1/conversations/direct`, `/v1/conversations`, `/v1/conversations/{conversation_id}/participants`
  - `message-service`: `/v1/messages/envelopes:batch`, `/v1/messages/envelopes/pending`, `/v1/messages/envelopes/{envelope_id}/ack`, `/v1/messages/conversations/{conversation_id}`
- `notification-service`: `/v1/notifications/pending`, `/v1/notifications/{notification_id}/ack`
- `api-gateway` proxies HTTP `/v1/*` paths to internal services and applies:
  - auth guard for non-`/v1/auth/*` paths (JWT access token check)
  - simple in-memory per-IP rate limit
- `realtime-service` provides WebSocket at `/v1/realtime/ws?device_id=...` and pushes events from Kafka topic `message.envelope.accepted.v1`.
- `notification-service` consumes Kafka topic `message.envelope.accepted.v1` and builds per-device pending notification queues.
- For now WebSocket should be opened directly against `realtime-service` (`localhost:8006`), not through gateway.
- Keep payloads encrypted end-to-end; server stores only ciphertext envelopes and delivery metadata.
