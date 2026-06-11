# Whispre Backend

Микросервисный backend прототипа iOS-мессенджера со сквозным шифрованием.
Сервер маршрутизирует и хранит зашифрованные конверты, но не выполняет
шифрование или расшифрование сообщений.

## Состав системы

| Компонент | Порт | Назначение |
| --- | ---: | --- |
| `api-gateway` | 8000 | HTTP-прокси, JWT guard, rate limit |
| `auth-service` | 8001 | Регистрация, вход, refresh/logout, устройства |
| `user-service` | 8002 | Профиль и поиск пользователей |
| `key-service` | 8003 | Key bundles и one-time prekeys |
| `conversation-service` | 8004 | Личные диалоги и участники |
| `message-service` | 8005 | Envelopes, pending, история и ACK |
| `realtime-service` | 8006 | WebSocket и Kafka consumer |
| `notification-service` | 8007 | Временная очередь уведомлений |
| PostgreSQL | 5432 | Общая реляционная база данных |
| Kafka | 9094 | Внешний порт брокера |
| Zookeeper | 2181 | Координация Kafka |
| Redis | 6379 | Зарезервирован в Compose, бизнес-логикой не используется |
| Grafana | 3000 | Дашборды |
| Prometheus | 9090 | Метрики |
| Loki | 3100 | Логи |
| Alloy | 12345 | Сбор контейнерных логов |

## Требования

- Docker Compose или Podman Compose;
- `bash`, `curl` и Python 3 для локальных скриптов;
- свободные порты, перечисленные выше.

Скрипты автоматически выбирают Docker, если он доступен, иначе Podman.
Можно явно задать CLI:

```bash
CONTAINER_CLI=podman ./scripts/migrate.sh
CONTAINER_CLI=podman ./scripts/create-topics.sh
```

## Первый запуск

Из каталога `whispre_backend`:

```bash
cp .env.example .env
docker compose up -d postgres zookeeper kafka redis
./scripts/migrate.sh
./scripts/create-topics.sh
docker compose up --build -d
```

Для Podman:

```bash
cp .env.example .env
podman compose up -d postgres zookeeper kafka redis
CONTAINER_CLI=podman ./scripts/migrate.sh
CONTAINER_CLI=podman ./scripts/create-topics.sh
podman compose up --build -d
```

Перед созданием топиков Kafka должна перейти в состояние `running`. Проверить
контейнеры можно командой:

```bash
docker compose ps
```

или:

```bash
podman compose ps
```

## Миграции базы данных

Схема описана SQLAlchemy-моделями в
`packages/whispre_common/whispre_common/models.py`. История миграций находится
в `db/alembic/versions`.

Применить миграции:

```bash
./scripts/migrate.sh
```

Полезные команды Alembic:

```bash
./scripts/alembic.sh current
./scripts/alembic.sh history
./scripts/alembic.sh revision --autogenerate -m "describe schema change"
./scripts/alembic.sh downgrade -1
```

Alembic запускается в отдельном Compose-профиле `tools`. Приложения не вызывают
`Base.metadata.create_all()` при старте. Для старой базы migration runner может
проверить совместимость существующей схемы и установить baseline; частично
совместимая схема отклоняется.

## Kafka

Создание топиков:

```bash
./scripts/create-topics.sh
```

Скрипт создаёт набор топиков, предусмотренных архитектурой проекта. Текущий
рабочий поток использует `message.envelope.accepted.v1`:

1. `message-service` сохраняет конверт в PostgreSQL;
2. `message-service` публикует событие в Kafka;
3. `realtime-service` отправляет WebSocket-событие устройству получателя;
4. `notification-service` помещает уведомление во временную очередь.

`realtime-service` и `notification-service` используют разные consumer groups.
Transactional Outbox не реализован: публикация выполняется после завершения
транзакции PostgreSQL.

## Проверка работоспособности

Health endpoints:

```bash
for port in 8000 8001 8002 8003 8004 8005 8006 8007; do
  curl "http://localhost:${port}/health"
done
```

Health endpoint подтверждает работу процесса, но не проверяет PostgreSQL,
Kafka или другие зависимости. Отдельного `/ready` сейчас нет.

Интеграционный smoke test:

```bash
./scripts/smoke-test.sh
```

Проверяется цепочка из десяти шагов:

- регистрация двух пользователей;
- регистрация устройств и key bundles;
- получение и claim one-time prekey;
- создание direct conversation;
- отказ при подмене устройства получателя;
- отправка encrypted envelope;
- pending, история, ACK и удаление сообщения из pending.

Smoke test проверяет серверный контракт с синтетическим ciphertext. Реальные
операции CryptoKit проверяются при запуске iOS-клиента, а не этим скриптом.

Другой адрес API Gateway:

```bash
WHISPRE_BASE_URL=https://api.example.com ./scripts/smoke-test.sh
```

## Основные HTTP endpoints

### Auth

- `POST /v1/auth/register`
- `POST /v1/auth/login`
- `POST /v1/auth/refresh`
- `POST /v1/auth/logout`
- `POST /v1/auth/devices/register`

### Users and keys

- `GET /v1/users/search`
- `GET /v1/users/me`
- `GET /v1/keys/users/{user_id}/bundles`
- `POST /v1/keys/users/{user_id}/one-time-prekey/claim`
- `PUT /v1/keys/devices/{device_id}/bundle`
- `POST /v1/keys/devices/{device_id}/one-time-prekeys/replenish`

### Conversations and messages

- `POST /v1/conversations/direct`
- `GET /v1/conversations`
- `GET /v1/conversations/{conversation_id}/participants`
- `POST /v1/messages/envelopes:batch`
- `GET /v1/messages/envelopes/pending`
- `POST /v1/messages/envelopes/{envelope_id}/ack`
- `GET /v1/messages/conversations/{conversation_id}`

### Realtime and notifications

- `WS /v1/realtime/ws?device_id={device_id}`
- `GET /v1/notifications/pending`
- `POST /v1/notifications/{notification_id}/ack`

REST-запросы клиента проходят через API Gateway. WebSocket iOS-клиент открывает
напрямую к `realtime-service` на `localhost:8006` и передаёт access token в
заголовке `Authorization`.

## Безопасность backend

API Gateway проверяет access JWT для защищённых `/v1/*` маршрутов и применяет
простой rate limit по IP: 240 запросов в минуту по умолчанию. Состояние лимитера
хранится в памяти одного процесса и не синхронизируется между репликами.

`message-service` проверяет:

- пользователя отправителя по JWT;
- участие отправителя и получателя в диалоге;
- принадлежность активных устройств соответствующим пользователям;
- UUID, формат ciphertext и поля E2E-заголовка;
- идемпотентность по `(sender_device_id, idempotency_key)`.

`key-service` атомарно выдаёт one-time prekey через
`FOR UPDATE SKIP LOCKED`. Изменять bundle и пополнять prekeys может только
владелец устройства.

Backend работает в single-device режиме: регистрация второго активного
устройства для аккаунта возвращает `409 Conflict`. Endpoint для деактивации или
замены устройства не реализован.

## Структура кода

Каждый сервис использует небольшую композиционную структуру:

- `main.py` создаёт FastAPI application;
- `router.py` содержит HTTP или WebSocket-контракты;
- `dependencies.py` содержит FastAPI-зависимости авторизации;
- `service.py` содержит бизнес-правила и запросы к БД;
- `schemas.py` содержит Pydantic-модели;
- `producer.py`, `consumer.py`, `connections.py`, `queue.py` и `lifespan.py`
  изолируют Kafka, WebSocket и временное состояние.

Общие SQLAlchemy-модели, настройки, JWT-, database-, logging- и
observability-хелперы находятся в `packages/whispre_common`.

SQLAlchemy использует синхронный psycopg 3. Большинство обычных endpoint
объявлены синхронными и исполняются FastAPI в thread pool. Асинхронный код
используется для API Gateway, Kafka и WebSocket.

## Observability

Локальные интерфейсы:

- Grafana: `http://localhost:3000`;
- Prometheus: `http://localhost:9090`;
- Loki: `http://localhost:3100`;
- Alloy: `http://localhost:12345`.

Grafana автоматически получает источники Prometheus и Loki и дашборд
`Whispre Overview`. При использовании `.env.example` учётные данные:
`admin` / `change-me`. Без `.env` Compose использует fallback
`admin` / `admin`. Для любого нелокального запуска пароль необходимо заменить.

Каждый FastAPI-сервис предоставляет `/metrics`:

- количество и длительность HTTP-запросов;
- запросы в обработке;
- результат обработки Kafka-событий;
- число активных WebSocket-соединений.

Сервисы пишут JSON-логи в stdout. В них есть `timestamp`, `level`, `service`,
`logger`, `event`, `message` и при наличии `request_id`. Пароли, токены,
ciphertext, plaintext и приватные ключи намеренно не логируются.

Alloy читает логи через Docker-совместимый сокет и добавляет Loki labels
`service`, `level` и `event`. Пример LogQL:

```logql
{application="whispre", service="message-service", level=~"warning|error"} | json
```

Prometheus и Loki хранят локальные данные семь дней. В Prometheus настроены
правила для недоступного сервиса, доли 5xx выше 5% и p95 latency выше секунды.

Проверка observability:

```bash
./scripts/observability-check.sh
```

Для rootless Podman Machine путь к сокету задаётся в `.env`, например:

```bash
CONTAINER_SOCKET_PATH=/run/user/501/podman/podman.sock
```

Для Docker Engine:

```bash
CONTAINER_SOCKET_PATH=/var/run/docker.sock
```

## Локальные ограничения

- REST и WebSocket работают без TLS;
- Compose содержит демонстрационные секреты и пароль PostgreSQL;
- внутренние сервисы опубликованы на host-портах;
- notification queue и rate limiter находятся в памяти;
- Redis пока не участвует в бизнес-логике;
- нет Transactional Outbox;
- нет горизонтального масштабирования stateful-компонентов;
- нет production-ready device replacement;
- автоматизирован только интеграционный smoke test.

Перед публичным развёртыванием необходимы HTTPS/WSS, безопасное хранение
секретов, закрытая сеть внутренних сервисов, постоянные очереди и отдельная
production-конфигурация инфраструктуры.
