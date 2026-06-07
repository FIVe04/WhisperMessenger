# Whispre: целевое техническое видение production-oriented MVP

## 1. Назначение итогового приложения

Whispre - iOS-мессенджер со сквозным шифрованием и backend на микросервисной архитектуре. Итоговая версия дипломного проекта должна демонстрировать полный жизненный цикл безопасной переписки:

- регистрация и вход пользователя;
- регистрация устройства и публикация криптографического key bundle;
- поиск пользователя и создание диалога;
- установление E2E-сессии между устройствами;
- отправка сообщения в виде encrypted envelope;
- доставка через backend без доступа сервера к plaintext;
- получение pending-сообщений и подтверждение доставки;
- realtime-уведомление через WebSocket;
- восстановление истории из ciphertext и локальное расшифрование на клиенте.

Итоговая формулировка для защиты: production-oriented MVP Signal-like messenger. Это не полный аналог Signal, но архитектурно и криптографически корректный прототип с явно описанными границами.

## 2. Границы production-oriented MVP

Проект должен быть защищен от типовых вопросов комиссии по трем направлениям:

- архитектура: сервисы разделены по зонам ответственности, есть gateway, БД, брокер событий, realtime-доставка;
- безопасность: сервер не видит plaintext, ключи создаются на клиенте, приватные ключи и токены хранятся безопасно, транспорт в production-профиле рассчитан на HTTPS/WSS;
- надежность: есть тесты критических сценариев, health/readiness endpoints, идемпотентность отправки, валидация прав доступа.

В рамках MVP допустимо честно зафиксировать ограничения:

- не реализуется полноценный Signal Double Ratchet с post-compromise security;
- групповые чаты не являются основным сценарием;
- вложения и push-уведомления можно оставить вне обязательной демонстрации;
- production-деплой описывается и поддерживается конфигурационно, но основной демонстрационный стенд может запускаться локально через Docker Compose и iOS Simulator.

## 3. Целевая криптографическая модель

Клиентская криптография должна быть описана как упрощенный Signal-like prekey protocol:

- каждое устройство имеет identity key pair;
- устройство публикует signed prekey;
- signed prekey подписывается identity/signing key;
- устройство публикует набор one-time prekeys;
- отправитель получает key bundle получателя;
- клиент проверяет подпись signed prekey;
- клиент использует identity key, signed prekey и, если доступен, one-time prekey для вывода shared secret;
- итоговый симметричный ключ выводится через HKDF-SHA256;
- сообщение шифруется AEAD-алгоритмом, например ChaCha20-Poly1305;
- сервер хранит только ciphertext, header и delivery metadata.

Важно: если полноценный Double Ratchet не реализуется, в тексте диплома нужно прямо указать, что после первичного установления сессии используется фиксированная или ограниченно обновляемая сессия без полного свойства post-compromise security. Это лучше, чем заявлять невозможное.

## 4. Backend-архитектура

Целевой backend состоит из сервисов:

- api-gateway: единая точка входа, JWT-проверка, rate limit, proxy к внутренним сервисам;
- auth-service: регистрация, login, refresh token rotation, logout, управление сессиями;
- user-service: профиль текущего пользователя, поиск пользователей;
- key-service: выдача key bundles, claim one-time prekey, пополнение prekeys;
- conversation-service: создание direct conversation, список диалогов, участники;
- message-service: прием encrypted envelopes, проверка прав, сохранение ciphertext, публикация Kafka-события;
- realtime-service: WebSocket-подключения устройств и доставка событий о новых envelopes;
- notification-service: очередь lightweight notifications для устройств.

PostgreSQL хранит пользователей, устройства, key bundles, prekeys, conversations, envelopes и refresh tokens. Kafka используется для событий доставки. Redis используется для rate limit, временных очередей или realtime state, если потребуется.

## 5. Обязательные backend-инварианты

Перед сохранением envelope message-service должен проверять:

- access token валиден;
- sender_user_id совпадает с subject токена;
- sender_device_id принадлежит sender_user_id;
- conversation_id существует;
- sender_user_id является участником conversation;
- recipient_user_id является участником conversation;
- recipient_device_id принадлежит recipient_user_id;
- ciphertext и header имеют ожидаемый формат;
- idempotency_key предотвращает повторную отправку batch.

Key-service должен проверять:

- device bundle принадлежит владельцу устройства при update/replenish;
- one-time prekey выдается атомарно;
- claimed prekey повторно не выдается;
- bundle содержит валидные поля и версии протокола.

## 6. iOS-клиент

iOS-клиент должен иметь:

- SwiftUI-интерфейс для регистрации, входа, списка чатов, создания нового чата, переписки и настроек;
- APIClient с конфигурируемым base URL;
- WebSocketManager с reconnect/backoff;
- SessionStore, который хранит чувствительные данные в Keychain;
- CryptoService, отвечающий за генерацию ключей, регистрацию bundle, проверку bundle, создание E2E-сессии, encrypt/decrypt;
- экран или debug-блок безопасности с device id, fingerprint и состоянием E2E-сессии.

Для демонстрации достаточно двух пользователей в двух симуляторах iOS. Комиссии нужно показать, что в базе данных и backend API хранится ciphertext, а plaintext отображается только на клиентах.

## 7. Transport security

Dev-профиль может использовать localhost HTTP/WS. Production-профиль должен быть описан и подготовлен:

- HTTPS для REST API;
- WSS для realtime;
- секреты только через environment variables;
- разные base URLs для dev/prod;
- запрет insecure transport в production-сборке iOS;
- опционально certificate pinning как расширение.

## 8. Тестирование

Минимальный набор тестов для защиты:

- backend unit tests: password hash, JWT, ownership helpers, key bundle validation;
- backend integration tests: register, login, device register, create conversation, send envelope, pending, ack, forbidden чужого device/conversation;
- crypto tests: encrypt/decrypt success, wrong key failure, stable key derivation, Keychain persistence;
- smoke test Docker Compose: health/readiness всех сервисов.

Цель тестов - не покрыть весь проект, а доказать, что критические security и delivery сценарии контролируются.

## 9. Observability и эксплуатация

Production-oriented MVP должен иметь:

- /health для базовой живости сервиса;
- /ready для проверки зависимостей;
- структурированные логи с service name, request id, status code и latency;
- единый формат ошибок API;
- docker-compose healthchecks;
- .env.example без реальных секретов;
- README с командами запуска, миграции, smoke-проверки и демонстрации.

## 10. Демонстрационный сценарий защиты

Оптимальный сценарий:

1. Запустить backend через Docker Compose.
2. Применить миграции.
3. Открыть два iOS Simulator.
4. Зарегистрировать или залогинить двух пользователей.
5. Показать регистрацию устройств и key bundles.
6. Создать direct chat.
7. Отправить сообщение из первого симулятора.
8. Показать realtime-доставку во втором симуляторе.
9. Показать в PostgreSQL, что хранится ciphertext.
10. Показать, что plaintext появляется только после локального decrypt на клиенте.
11. Показать тесты critical path.

## 11. Критерий готовности

Проект можно считать готовым к защите, если:

- документация соответствует коду;
- нет fake crypto placeholders;
- private keys и токены не лежат в UserDefaults;
- message-service проверяет ownership отправителя и получателя;
- есть тесты critical path;
- backend запускается одной командой;
- два симулятора стабильно обмениваются encrypted messages;
- ограничения криптографической модели честно описаны в дипломе.
