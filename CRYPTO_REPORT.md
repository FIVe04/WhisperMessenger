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
  - [3.7. Собственная схема установления сессий (статический DH без рачетов)](#37-собственная-схема-установления-сессий-статический-dh-без-рачетов)

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
- `Crypto/` — KeyManager (Keychain), SessionManager (DH + HKDF + storage), EncryptionService (AES-GCM), EncryptionSessionHelper (получение ключей/сессий).
- `App/Initializers/SessionInitializer.swift` — регистрация устройства, старт WebSocket.
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
- `Crypto/KeyManager.swift` — генерация/хранение identity key (P256.KeyAgreement), signed prekey (P256.Signing), one-time prekeys; удаление ключей.
- `Crypto/SessionManager.swift` — хранение сессий (симметрические ключи) по deviceId, деривация через P256 DH + HKDF-SHA256; UserDefaults persistence.
- `Crypto/EncryptionService.swift` — шифрование/дешифрование AES.GCM (симметрический ключ из SessionManager).
- `Crypto/EncryptionSessionHelper.swift` — получение публичных ключей устройств с сервера и создание сессии.
- `App/Initializers/SessionInitializer.swift` — генерация ключей, регистрация устройства (identity, signed prekey, подпись), создание one-time prekeys, старт WebSocket.
- `Networking/APIService.swift` — REST вызовы (users, devices, messages, keys).
- `Networking/WebSocketService.swift` — WebSocket отправка/приём JSON сообщений.
- `App/ViewModel/ChatViewModel.swift`, `FriendsViewModel.swift` — создание сессий при необходимости, вызов шифрования/дешифрования.
- `App/View/WhispreClientApp.swift` — logout: сброс сессий, токенов, disconnect WebSocket (ключи теперь не удаляются).

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
- Протокол: статический Diffie–Hellman на P256 без рачетов (Signal‑подобные prekey’и не используются для вычисления ключа; берётся только identity key).
- Получение ключей другой стороны:
  - `SessionBootstrapper.ensureSession` → `APIService.getUserDevices` (список устройств с полями `identity_key`, `signed_prekey`, `signed_prekey_signature`).
  - `ChatViewModel.bootstrapIfNeeded` дополнительно вызывает `APIService.exchangeKeys` (`/keys/exchange/{recipient_id}`), получает bundles с identity/signed/one_time_prekey, но при создании сессии использует только `identity_key`.
- Деривация сессионного ключа:
  - `SessionManager.createSession`: P256.KeyAgreement (ECDH) между своим приватным identity ключом и публичным identity ключом собеседника → `sharedSecret`.
  - HKDF-SHA256 с солью `"WhispreHKDFSalt_v2"` и `outputByteCount: 32` → симметрический ключ (256 бит).
- Сохранение: SessionManager хранит `SessionModel` (recipientId -> symmetric key bytes) в памяти и UserDefaults (`com.whispre.sessions.v2`); привязка по `device_id` собеседника.
- Подписи/one-time prekeys из бандла не проверяются и не используются при вычислении ключа.

## 2.4. Отправка сообщения
1. Пользователь вводит текст в `ChatViewModel.send`.
2. Убеждается, что есть сессия: `SessionBootstrapper.ensureSession` (получает device_id, создаёт сессию при необходимости).
3. Шифрование: `EncryptionService.encryptMessage`:
   - Ключ: `SessionManager.getSession(recipientDeviceId).symmetricKey()`.
   - Алгоритм: `AES.GCM.seal` (CryptoKit), nonce автоматически генерируется; используется combined формат (nonce+ciphertext+tag).
   - Результат: combined → Base64 строка.
4. Отправка:
   - Через WebSocket: `WebSocketService.sendMessage` отправляет JSON с полями `ciphertext` (Base64), `recipient_user_id`, `recipient_device_id`, `sender_device_id`, `content_type`.
   - В коде закомментирован REST `/messages/send`, но WebSocket вариант активен.
5. Подпись сообщения не выполняется; аутентификация опирается только на AEAD‑tag AES-GCM и знание сессионного ключа.

## 2.5. Получение и расшифровка сообщения
- WebSocket: `WebSocketService` получает JSON `new_message` → делегаты (`FriendsViewModel`, `ChatViewModel`).
- Дешифрование: `EncryptionService.decryptMessage`:
  - Берёт сессионный ключ по `senderDeviceID` (если нет, выбрасывает `noSessionKey`).
  - Расшифровка `AES.GCM.open` с combined данными (Base64 → data).
- Автовосстановление сессии:
  - `EncryptionService.decryptMessageWithAutoSession` при ошибке вызывает `/keys/exchange/{senderUserId}`, создаёт сессии по identity keys, затем повторяет дешифрование; если не удалось — возвращает "🔒".
  - `ChatViewModel.didReceiveMessage` пытается bootstrap сессию по конкретному senderDeviceID через `SessionBootstrapper.ensureSession(forDeviceId:...)`.
- Проверка подписи отправителя отсутствует; проверяется только AES-GCM tag (целостность/аутентичность ключа).

## 2.6. Работа с вложениями/медиа
- По коду не реализовано.

## 2.7. Push-уведомления
- По коду не реализовано.

## 2.8. Хранение данных

**Локально (iOS):**
- Identity и signed prekey приватные ключи — Keychain (`KeyManager` использует `SecItemAdd` с `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- One-time prekeys хранятся в памяти при генерации; на диск не сохраняются.
- Сессионные ключи — UserDefaults (`SessionManager` сериализует в JSON по `com.whispre.sessions.v2`).
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
  - Ключи в Keychain теперь НЕ удаляются (строка `KeyManager.deleteAllKeys` закомментирована), поэтому при повторном входе используется тот же ключевой материал и device_id.
- Удаление аккаунта: по коду не реализовано.
- One-time prekeys: выдаются по `keys/exchange`, помечаются used=true, но клиент их не использует для расчёта сессионного ключа и не загружает новые.

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
4. **Особенности:** Реализация CryptoKit (`P256.KeyAgreement`), `SharedSecret.hkdfDerivedSymmetricKey`. Не использует one-time prekeys/подписи бандла — уязвимо к подмене публичного ключа при отсутствии TLS/пиннинга.

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

## 3.7. Собственная схема установления сессий (статический DH без рачетов)
1. **Назначение:** Организация E2E сессионного ключа между устройствами без полноценного Signal Double Ratchet.
2. **Как работает:** Каждое устройство публикует статический identity key. Клиент берёт публичный identity собеседника (по device_id) и делает один P256 DH + HKDF. Сессия фиксируется на device_id, не обновляется. One-time prekeys и подписи в бандле не участвуют.
3. **Свойства:** Обеспечивает конфиденциальность при отсутствии MITM и при сохранении приватных ключей. Нет forward secrecy (при компрометации приватного identity можно расшифровать все прошлые сообщения). Уязвимость к MITM из-за отсутствия проверки подписи бандла и отсутствия TLS/пиннинга.
4. **Особенности:** Реализовано в `SessionManager.createSession`, `SessionBootstrapper`, `ChatViewModel.bootstrapIfNeeded`. Нет рачета/ротации; нет верификации fingerprint’ов; нет использования one-time prekeys.

