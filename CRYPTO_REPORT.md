# Документация по Whispre (E2E‑мессенджер)

## Оглавление
- [1. Общее описание проекта](#1-общее-описание-проекта)
  - [1.1. Высокоуровневая архитектура](#11-высокоуровневая-архитектура)
  - [1.2. Организация репозитория](#12-организация-репозитория)
    - [1.2.1. Ключевые классы и файлы](#121-ключевые-классы-и-файлы)
- [2. Использование криптографии по сценариям](#2-использование-криптографии-по-сценариям)
  - [2.1. Регистрация пользователя](#21-регистрация-пользователя)
  - [2.2. Вход в аккаунт / аутентификация](#22-вход-в-аккаунт--аутентификация)
  - [2.3. Установление/обновление сессии шифрования](#23-установлениеобновление-сессии-шифрования)
  - [2.4. Отправка сообщения](#24-отправка-сообщения)
  - [2.5. Получение и расшифровка сообщения](#25-получение-и-расшифровка-сообщения)
  - [2.6. Работа с вложениями/медиа](#26-работа-с-вложениямимедиа)
  - [2.7. Push-уведомления](#27-push-уведомления)
  - [2.8. Хранение данных](#28-хранение-данных)
  - [2.9. Ротация ключей, logout, удаление](#29-ротация-ключей-logout-удаление)
- [3. Описание используемых криптографических алгоритмов](#3-описание-используемых-криптографических-алгоритмов)
  - [3.1. bcrypt (хэширование пароля)](#31-bcrypt-хэширование-пароля)
  - [3.2. JWT HS256/HS??? (подпись токенов)](#32-jwt-hs256hs-подпись-токенов)
  - [3.3. P256 Key Agreement + HKDF-SHA256 (установление сессионного ключа)](#33-p256-key-agreement--hkdf-sha256-установление-сессионного-ключа)
  - [3.4. P256 ECDSA (подпись signed prekey)](#34-p256-ecdsa-подпись-signed-prekey)
  - [3.5. AES-GCM (шифрование сообщений)](#35-aes-gcm-шифрование-сообщений)
  - [3.6. Base64 (кодирование бинарных данных)](#36-base64-кодирование-бинарных-данных)
  - [3.7. Собственная схема установления сессий (статический DH с one-time prekeys)](#37-собственная-схема-установления-сессий-статический-dh-с-one-time-prekeys)

# 1. Общее описание проекта

Мессенджер с end-to-end шифрованием для iOS и backend на FastAPI. Пользователь регистрируется/логинится, регистрирует устройство с публичными ключами, устанавливает симметричные сессионные ключи с другими устройствами и шифрует сообщения на клиенте.

**Технологии:**
- Backend: Python, FastAPI (`app/main.py`), SQLAlchemy ORM (`app/database.py`), PostgreSQL (подключение через `settings.db_url`), JWT через `python-jose`, хэш паролей через `passlib` (bcrypt).
- iOS: Swift/SwiftUI, MVVM; сеть через `URLSession` (async/await), WebSocket через `URLSessionWebSocketTask`; криптография через `CryptoKit` (P256, AES.GCM, HKDF).

## 1.1. Высокоуровневая архитектура

**Backend компоненты:**
- Auth/Users (`app/routes/users.py`, `app/auth.py`): регистрация, логин, токены, список друзей.
- Devices/Keys (`app/routes/devices.py`, `app/routes/keys.py`): регистрация устройства (identity key, signed prekey, one-time prekeys), выдача ключевых бандлов.
- Messages (`app/routes/messages.py`, `app/websocket.py`): REST + WebSocket приём/рассылка зашифрованных сообщений; статус delivered/read.
- Models/DB (`app/models.py`, `app/database.py`): таблицы users, devices, one_time_prekeys, messages, sessions.
- Конфигурация (`app/config.py`, `.env`).

**iOS модули:**
- Авторизация/регистрация (`LoginViewModel.swift`, `RegisterViewModel.swift`, `LoginView.swift`, `RegisterView.swift`).
- Главный флоу/табы/чаты (`MainTabView.swift`, `ChatsView.swift`, `ChatView.swift`, `FriendsViewModel.swift`, `ChatViewModel.swift`).
- Криптография (`Crypto/KeyManager.swift`, `SessionManager.swift`, `EncryptionService.swift`, `EncryptionSessionHelper.swift`).
- Инициализация устройства и WebSocket (`SessionInitializer.swift`, `WebSocketService.swift`).
- Сеть (`Networking/APIService.swift`).

## 1.2. Организация репозитория

**Backend `whispre_backend/app`:**
- `main.py` — сборка FastAPI, middleware, роуты.
- `auth.py` — хэш паролей, JWT.
- `routes/` — users, devices, messages, keys, sessions.
- `models.py` — ORM модели (User, Device, OneTimePreKey, Message, Session, статус MessageStatus).
- `schemas.py` — Pydantic-схемы запрос/ответ.
- `database.py` — engine, session, Base, init_db.
- `config.py` — настройки из .env.

**iOS `WhispreClient/WhispreClient`:**
- `App/` — SwiftUI Views, ViewModels, AppState, навигация.
- `Networking/` — `APIService` (REST), `WebSocketService` (ws://).
- `Crypto/` — KeyManager (Keychain + UserDefaults для one-time prekeys), SessionManager (DH + HKDF + storage), EncryptionService (AES-GCM + envelope для OTPK handshake), EncryptionSessionHelper (legacy создание сессий по identity).
- `App/Initializers/SessionInitializer.swift` — регистрация устройства, старт WebSocket, генерация и сохранение OTPK.
- `Models/` — DTO: MessageResponse, ChatMessage, User, Device, Token, Friend и т.д.
- Хранение ключей/сессий: Keychain (SecItem), UserDefaults.

### 1.2.1. Ключевые классы и файлы

Backend:
- `app/auth.py` — bcrypt-хэш пароля, JWT (HS алгоритм из `settings.ALGORITHM`), проверка токена.
- `app/routes/users.py` — register/login, friends, текущий пользователь.
- `app/routes/devices.py` — регистрация девайса и one-time prekeys, получение ключей устройств.
- `app/routes/keys.py` — выдача key bundle (identity, signed prekey, one-time prekey).
- `app/routes/messages.py` — REST отправка/история/статус сообщений.
- `app/websocket.py` — WebSocket для приёма/доставки сообщений, статус update.
- `app/models.py` — таблицы users/devices/one_time_prekeys/messages/sessions.

iOS:
- `Crypto/KeyManager.swift` — генерация/хранение identity key (P256.KeyAgreement), signed prekey (P256.Signing), one-time prekeys (приватные — UserDefaults), удаление ключей.
- `Crypto/SessionManager.swift` — хранение сессий (симметрические ключи) по deviceId, деривация через P256 DH + HKDF-SHA256; UserDefaults persistence, создание сессии из готового ключа.
- `Crypto/EncryptionService.swift` — шифрование/дешифрование AES.GCM, envelope (cipher + handshake) и bootstrap по OTPK handshake.
- `Crypto/EncryptionSessionHelper.swift` — получение публичных ключей устройств с сервера и создание сессии (legacy по identity).
- `App/Initializers/SessionInitializer.swift` — генерация ключей, регистрация устройства (identity, signed prekey, подпись), генерация/сохранение one-time prekeys, старт WebSocket.
- `Networking/APIService.swift` — REST вызовы (users, devices, messages, keys).
- `Networking/WebSocketService.swift` — WebSocket отправка/приём JSON сообщений.
- `App/ViewModel/ChatViewModel.swift`, `FriendsViewModel.swift` — создание сессий при необходимости, вызов шифрования/дешифрования, автоподнятие сессий с OTPK.
- `App/View/WhispreClientApp.swift` — logout: сброс сессий, токенов, disconnect WebSocket (ключи и OTPK остаются).

# 2. Использование криптографии по сценариям

## 2.1. Регистрация пользователя
- Пароль отправляется в открытом виде (HTTP) с клиента (`APIService.register`), хэширование только на сервере.
- Сервер: `app/routes/users.py` → `get_password_hash` (`passlib.CryptContext` с bcrypt) — соль генерируется bcrypt автоматически, хранится вместе с хэшем.
- Ключи E2E при регистрации пользователя не создаются на сервере; на клиенте при последующем логине/инициализации устройства генерируются:
  - Identity key: `KeyManager.generateIdentityKey` (P256 Key Agreement private key) в `SessionInitializer.startSession`.
  - Signed prekey: `KeyManager.generateSignedPreKey` (P256.Signing.PrivateKey) + подпись собственного паблика.
  - One-time prekeys: массив P256.KeyAgreement.PrivateKey.

## 2.2. Вход в аккаунт / аутентификация
- Клиент: `APIService.login` отправляет email/password (без клиентского хэширования).
- Сервер: `app/routes/users.py@login_user` проверяет bcrypt (`verify_password`).
- Токены: `app/auth.py` создаёт JWT access/refresh (`jwt.encode`, алгоритм `settings.ALGORITHM`, секрет `settings.SECRET_KEY`). Формат — HSxxx (точное значение алгоритма задаётся в .env; по коду не видно).
- Транспорт: `baseURL` и WebSocket — `http://` и `ws://` (TLS/пиннинг по коду не реализованы → “не определено/не реализовано”).
- Клиент сохраняет access/refresh в `UserDefaults`; SessionManager сбрасывает сессии при логине (`resetCryptoState`).

## 2.3. Установление/обновление сессии шифрования
- Протокол: статический DH на P256 с попыткой использовать one-time prekey (OTPK) получателя для первого сообщения; если OTPK недоступен, откат к DH по identity.
- Получение ключей другой стороны:
  - `APIService.exchangeKeys(recipientId)` возвращает bundle: identity_key, signed_prekey, signed_prekey_signature, one_time_prekey (+ id), device_id.
  - `ChatViewModel`/`SessionBootstrapper` берут нужный device_id, пытаются использовать OTPK; если нет — используют identity_key.
- Деривация сессионного ключа:
  - OTPK-путь: sender генерирует ephemeral P256, делает DH(ephemeral, recipient OTPK) → HKDF-SHA256 (соль `"WhispreHKDFSalt_OTPK_v1"`, 32 байта). Сохраняет сессию в SessionManager под device_id, прикладывает handshake (ephemeralPub, recipientOneTimePrekey) в envelope.
  - Фолбек: `SessionManager.createSession` — DH(identity_priv, identity_pub) → HKDF-SHA256 (соль `"WhispreHKDFSalt_v2"`, 32 байта).
- Сохранение: SessionManager хранит сессии в памяти и UserDefaults (`com.whispre.sessions.v2`) по device_id собеседника.
- Подписи в бандле и one_time_prekey_signature не проверяются; OTPK хранится локально для собственных устройств в UserDefaults и расходуется/читается по handshake.

## 2.4. Отправка сообщения
1. Пользователь вводит текст в `ChatViewModel.send`.
2. Если сессии нет: тянет `/keys/exchange`, пробует создать сессию через OTPK (DH(ephemeral, OTPK) + HKDF) и формирует handshake (ephemeralPub, recipientOneTimePrekey). Если OTPK нет — создаёт сессию по identity.
3. Шифрование: `EncryptionService.encryptMessage`:
   - Ключ: из SessionManager для device_id.
   - Алгоритм: `AES.GCM.seal` (CryptoKit), nonce генерируется автоматически, combined формат.
   - Если есть handshake — шлёт envelope (JSON с `ciphertext`, `handshake`), иначе просто Base64 ciphertext.
4. Отправка:
   - WebSocket: `WebSocketService.sendMessage` с `ciphertext` (envelope или Base64), `recipient_user_id`, `recipient_device_id`, `sender_device_id`, `content_type`.
   - REST `/messages/send` остаётся закомментированным.
5. Подписи сообщений нет; аутентификация — только AEAD‑tag AES-GCM и знание сессионного ключа.

## 2.5. Получение и расшифровка сообщения
- WebSocket: `WebSocketService` получает JSON `new_message` → делегаты (`FriendsViewModel`, `ChatViewModel`).
- Дешифрование: `EncryptionService.decryptMessage`:
  - Пытается взять сессию по `senderDeviceID` и открыть AES-GCM.
  - Если нет сессии и есть handshake в envelope: берёт свой приватный OTPK (по public из handshake), делает DH(ephemeral, OTPK) + HKDF, создаёт сессию и расшифровывает. OTPK хранится локально, не на сервере.
  - Если handshake нет/не сработал: `decryptMessageWithAutoSession` запрашивает `/keys/exchange` и создаёт сессию по identity (фолбек), затем повторяет расшифровку; иначе возвращает "🔒".
- Проверка подписи отправителя отсутствует; проверяется только AES-GCM tag (целостность/аутентичность ключа).

## 2.6. Работа с вложениями/медиа
- По коду не реализовано.

## 2.7. Push-уведомления
- По коду не реализовано.

## 2.8. Хранение данных

**Локально (iOS):**
- Identity и signed prekey приватные ключи — Keychain (`KeyManager`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- One-time prekeys приватные — UserDefaults (словарь pub->priv raw); не удаляются автоматически.
- Сессионные ключи — UserDefaults (`SessionManager`, JSON `com.whispre.sessions.v2`).
- Токены/ID пользователя/DeviceId — UserDefaults (`accessToken`, `refreshToken`, `userId`, `com.whispre.deviceId`).
- Локальная БД шифрованием не покрыта (её нет).

**Сервер:**
- Пароли — bcrypt hash в таблице `users.password_hash`.
- Сообщения — `ciphertext` (LargeBinary) в таблице `messages`; не шифруются дополнительно на сервере (сервер хранит то, что прислал клиент).
- Ключи устройств — identity_key, signed_prekey, signed_prekey_signature в таблице `devices`; one_time_prekeys в таблице `one_time_prekeys`.
- Токены refresh — bcrypt hash в таблице `sessions.refresh_token_hash`.
- Шифрование данных в БД (полевая/строчная) по коду не реализовано.

## 2.9. Ротация ключей, logout, удаление
- Ротация ключей: явного механизма нет (identity/signed prekey генерируются один раз при инициализации устройства; обновление не предусмотрено).
- Logout (клиент `AppState.logout`):
  - Сбрасывает сессии SessionManager (`resetAll` + `logoutCurrentUser`), удаляет токены/userId из UserDefaults, разрывает WebSocket.
  - Identity/signed prekey и приватные OTPK остаются (Keychain/UserDefaults), поэтому при повторном входе ключевой материал сохраняется, но сохранённые сессии стираются.
- Удаление аккаунта: по коду не реализовано.
- One-time prekeys: выдаются по `keys/exchange`, сервер помечает used=true; клиент использует для создания сессии (sender) и для восстановления по handshake (receiver). Обновление/допоставка OTPK на сервер не реализовано.

# 3. Описание используемых криптографических алгоритмов

## 3.1. bcrypt (хэширование пароля)
1. **Назначение и роль:** Серверный хэш пароля при регистрации и проверка при логине (`app/auth.py`, `app/routes/users.py`). Используется для защиты пароля в БД.
2. **Как работает:** Медленная адаптивная функция на основе Blowfish; принимает пароль + соль, выполняет многократные раунды вычислений, выдаёт хэш, включающий параметры и соль.
3. **Свойства:** Устойчивость к перебору за счёт настраиваемой стоимости; соль предотвращает радужные таблицы. Не защищает от онлайн‑бранута.
4. **Особенности в проекте:** Применяется через `passlib.CryptContext(schemes=["bcrypt"])`; соль и cost выбираются библиотекой по умолчанию. Клиент не хэширует пароль.

## 3.2. JWT HS256/HS??? (подпись токенов)
1. **Назначение:** Подпись access/refresh токенов на сервере (`create_access_token`, `create_refresh_token` в `app/auth.py`).
2. **Как работает:** JSON-пейлоад + exp кодируются и подписываются симметричным ключом `SECRET_KEY` по алгоритму `settings.ALGORITHM` (по коду конкретный HS вариант не указан, зависит от .env).
3. **Свойства:** Целостность/аутентичность токена при хранении общего секрета. Конфиденциальность не обеспечивается.
4. **Особенности:** Симметричная подпись (HS); проверка в `decode_access_token`/`get_current_user`. Передача токена по HTTP/WS без TLS → уязвимо к перехвату (TLS не настроен по коду).

## 3.3. P256 Key Agreement + HKDF-SHA256 (установление сессионного ключа)
1. **Назначение:** Вычисление общего секрета между устройствами и вывод симметрического ключа для AES-GCM (`SessionManager.createSession`).
2. **Как работает:** P256 ECDH между приватным identity ключом одной стороны и публичным identity другой → shared secret; HKDF-SHA256 с солью `"WhispreHKDFSalt_v2"` и пустым info выводит 32-байтный ключ.
3. **Свойства:** Конфиденциальность ключа при компрометации канала; нет forward secrecy при компрометации статических ключей (используются статические identity ключи без рачетов).
4. **Особенности:** Реализация CryptoKit (`P256.KeyAgreement`), `SharedSecret.hkdfDerivedSymmetricKey`. Используется как фолбек, если OTPK недоступен; подмена публичного ключа не защищена (нет TLS/пиннинга/подписей).

## 3.4. P256 ECDSA (подпись signed prekey)
1. **Назначение:** Клиент подписывает свой signed prekey приватным P256.Signing key (`SessionInitializer.startSession`), отправляет подпись на сервер.
2. **Как работает:** ECDSA на кривой P-256, подпись raw публичного ключа signed prekey.
3. **Свойства:** Должна подтверждать владение приватным ключом, связывая signed prekey с identity.
4. **Особенности:** Сервер не проверяет подпись в `app/routes/devices.py` — безопасность не достигается. Клиент также не проверяет подпись удалённого бандла.

## 3.5. AES-GCM (шифрование сообщений)
1. **Назначение:** Шифрование/дешифрование контента сообщений на клиенте (`EncryptionService.encryptMessage/decryptMessage`).
2. **Как работает:** Симметричный AEAD; вход: ключ (256 бит из HKDF), plaintext, случайный nonce (CryptoKit генерирует), выход: ciphertext + auth tag; combined формат объединяет nonce+ciphertext+tag.
3. **Свойства:** Конфиденциальность и целостность/аутентичность (по ключу). Повтор nonce с тем же ключом опасен; CryptoKit генерирует уникальный nonce.
4. **Особенности:** Используются ключи из статического DH; подпись отправителя не добавляется. Данные кодируются Base64 для транспорта.

## 3.6. Base64 (кодирование бинарных данных)
1. **Назначение:** Передача бинарных ciphertext/ключей в JSON (клиент и сервер).
2. **Работает:** Преобразование байтов в текстовый алфавит A–Z, a–z, 0–9, +, /, =.
3. **Свойства:** Не даёт безопасности, только транспортное кодирование.
4. **Особенности:** AES-GCM combined → Base64 в `EncryptionService`; публичные ключи → Base64 при регистрации устройства.

## 3.7. Собственная схема установления сессий (статический DH с one-time prekeys)
1. **Назначение:** Организация E2E сессионного ключа без Double Ratchet: по возможности через одноразовый prekey, иначе через статический identity.
2. **Как работает:** Получатель публикует identity + OTPK. Отправитель для первого сообщения делает DH(ephemeral, OTPK) → HKDF (соль `"WhispreHKDFSalt_OTPK_v1"`) и шлёт ciphertext в envelope с handshake (ephemeralPub, OTPK pub). Приёмник извлекает handshake, находит свой OTPK, делает тот же DH+HKDF, создаёт сессию и расшифровывает. Если OTPK нет, обе стороны используют DH(identity, identity) + HKDF.
3. **Свойства:** Конфиденциальность; частичная forward secrecy для первого сообщения (ephemeral+OTPK). При компрометации статических identity — старые сообщения, зашифрованные по identity-DH, уязвимы. Нет защиты от MITM (нет проверки подписи бандла/пиннинга).
4. **Особенности:** Реализовано в `EncryptionService.createSessionUsingOneTimePrekey/tryBootstrapFromHandshake`, `ChatViewModel.send`, `EncryptionService.decryptMessageWithAutoSession`. Нет рачетов/ротации, нет проверки подписей бандла, допоставка OTPK на сервер не реализована.
