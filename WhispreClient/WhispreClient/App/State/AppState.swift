import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    enum RealtimeStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting

        var title: String {
            switch self {
            case .disconnected:
                return "Offline"
            case .connecting:
                return "Connecting..."
            case .connected:
                return "Online"
            case .reconnecting:
                return "Reconnecting..."
            }
        }
    }

    @Published var isLoggedIn: Bool
    @Published var isRegistered: Bool
    @Published var currentUsername: String = ""
    @Published var chats: [Friend] = []
    @Published var messagesByConversation: [String: [ChatMessage]] = [:]
    @Published var latestError: String?
    @Published var realtimeStatus: RealtimeStatus = .disconnected

    let sessionStore = SessionStore()

    private let apiClient = APIClient()
    private let webSocket = WebSocketManager()
    private let cryptoService = CryptoService()
    private var isRefreshingPendingMessages = false

    init() {
        let loggedIn = sessionStore.accessToken != nil
        isLoggedIn = loggedIn
        isRegistered = sessionStore.hasRegistered || loggedIn
        currentUsername = sessionStore.username ?? ""

        webSocket.onEvent = { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                await self.handleRealtimeEvent(event)
            }
        }
        webSocket.onError = { [weak self] message in
            Task { @MainActor in
                self?.latestError = message
            }
        }
        webSocket.onStateChange = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .disconnected:
                    self?.realtimeStatus = .disconnected
                case .connecting:
                    self?.realtimeStatus = .connecting
                case .connected:
                    self?.realtimeStatus = .connected
                case .reconnecting:
                    self?.realtimeStatus = .reconnecting
                }
            }
        }

        if isLoggedIn {
            Task {
                await bootstrapAfterLogin()
            }
        }
    }

    func register(username: String, email: String, password: String) async throws {
        let body = RegisterRequestDTO(username: username, email: email, password: password)
        let encoded = try apiClient.encodeBody(body)
        _ = try await apiClient.request(
            path: "v1/auth/register",
            method: "POST",
            body: encoded
        ) as AuthTokensDTO

        sessionStore.markRegistered()
        isRegistered = true
    }

    func login(email: String, password: String) async throws {
        let body = LoginRequestDTO(email: email, password: password)
        let encoded = try apiClient.encodeBody(body)
        let tokens: AuthTokensDTO
        do {
            tokens = try await apiClient.request(
                path: "v1/auth/login",
                method: "POST",
                body: encoded
            )
        } catch {
            throw APIClientError.server(status: -1, message: "Login failed at /v1/auth/login: \(error.localizedDescription)")
        }

        sessionStore.saveTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
        sessionStore.markRegistered()
        isRegistered = true

        do {
            try await fetchAndSaveCurrentUser()
            try enforceSingleAccountPolicy()
        } catch {
            throw APIClientError.server(status: -1, message: "Login failed at /v1/users/me: \(error.localizedDescription)")
        }

        if let currentUserID = sessionStore.userID {
            sessionStore.activateDevice(for: currentUserID)
        }

        do {
            try await registerCurrentDevice()
        } catch {
            throw APIClientError.server(status: -1, message: "Login failed at /v1/auth/devices/register: \(error.localizedDescription)")
        }

        isLoggedIn = true
        connectWebSocketIfPossible()

        do {
            try await refreshChats()
            try await refreshPendingMessages()
        } catch {
            latestError = "Post-login sync warning: \(error.localizedDescription)"
        }
    }

    func logout() {
        webSocket.disconnect()
        sessionStore.clearSession()

        isLoggedIn = false
        isRegistered = true
        currentUsername = ""
        chats = []
        messagesByConversation = [:]
        latestError = nil
        realtimeStatus = .disconnected
    }

    func resetAppData() {
        webSocket.disconnect()
        cryptoService.resetLocalCryptoState()
        sessionStore.resetAllLocalData()

        isLoggedIn = false
        isRegistered = false
        currentUsername = ""
        chats = []
        messagesByConversation = [:]
        latestError = nil
        realtimeStatus = .disconnected
    }

    func searchUser(username: String) async throws -> Friend? {
        let token = try requireAccessToken()
        let users: [UserSummaryDTO] = try await apiClient.request(
            path: "v1/users/search",
            token: token,
            query: [URLQueryItem(name: "username", value: username)]
        )

        guard let me = sessionStore.userID else { return users.first.map { dto in
            Friend(id: dto.id, username: dto.username, lastMessage: "", lastMessageTime: DateCodec.isoOut.string(from: Date()), conversationID: nil, recipientDeviceID: nil)
        }}

        let candidate = users.first(where: { $0.id != me })
        guard let candidate else { return nil }

        return Friend(
            id: candidate.id,
            username: candidate.username,
            lastMessage: "",
            lastMessageTime: DateCodec.isoOut.string(from: Date()),
            conversationID: nil,
            recipientDeviceID: nil
        )
    }

    func ensureConversation(with friend: Friend) async throws -> Friend {
        var mutable = friend
        if mutable.conversationID == nil {
            let token = try requireAccessToken()
            let body = CreateDirectConversationRequestDTO(peerUserId: friend.id)
            let encoded = try apiClient.encodeBody(body)
            let conversation: ConversationDTO = try await apiClient.request(
                path: "v1/conversations/direct",
                method: "POST",
                token: token,
                body: encoded
            )
            mutable.conversationID = conversation.id
        }

        if mutable.recipientDeviceID == nil {
            mutable.recipientDeviceID = try await fetchPrimaryDeviceID(for: mutable.id)
        }

        upsertChat(mutable)
        return mutable
    }

    func messages(for conversationID: String?) -> [ChatMessage] {
        guard let conversationID else { return [] }
        return messagesByConversation[conversationID] ?? []
    }

    func sendMessage(text: String, to friend: Friend) async throws {
        latestError = nil
        let resolved = try await ensureConversation(with: friend)
        guard let conversationID = resolved.conversationID else { return }
        guard let senderUserID = sessionStore.userID, let senderDeviceID = sessionStore.deviceID else {
            throw APIClientError.server(status: 401, message: "Session is not initialized")
        }

        let token = try requireAccessToken()
        let session = try await ensureOutboundSession(
            senderUserID: senderUserID,
            senderDeviceID: senderDeviceID,
            recipientUserID: resolved.id,
            recipientDeviceIDHint: resolved.recipientDeviceID,
            conversationID: conversationID
        )
        let recipientDeviceID = session.recipientDeviceID
        let encrypted = try cryptoService.encryptMessage(
            plaintext: text,
            senderUserID: senderUserID,
            senderDeviceID: senderDeviceID,
            recipientDeviceID: recipientDeviceID,
            recipientIdentityPubBase64: session.recipientIdentityPub,
            recipientSignedPrekeyID: session.recipientSignedPrekeyID,
            recipientSignedPrekeyPubBase64: session.recipientSignedPrekeyPub,
            recipientOneTimePrekeyID: session.claimedOneTimePrekeyID,
            recipientOneTimePrekeyPubBase64: session.recipientOneTimePrekeyPub,
            senderEphemeralPrivateKeyBase64: session.senderEphemeralPrivateKey,
            conversationID: conversationID,
            sessionID: session.sessionID
        )
        cryptoService.touchOutboundSession(session)
        let senderIdentityPub = try cryptoService.identityPublicKeyBase64(
            userID: senderUserID,
            deviceID: senderDeviceID
        )

        let envelope = EnvelopeDTO(
            envelopeId: UUID().uuidString.lowercased(),
            conversationId: conversationID,
            senderUserId: senderUserID,
            senderDeviceId: senderDeviceID,
            recipientUserId: resolved.id,
            recipientDeviceId: recipientDeviceID,
            ciphertext: encrypted.ciphertext,
            header: RatchetHeaderDTO(
                ratchetPub: "sess:\(session.sessionID):\(senderIdentityPub)",
                pn: 0,
                n: 1,
                protocolVersion: 2,
                senderEphemeralPub: encrypted.senderEphemeralPub,
                signedPrekeyId: encrypted.signedPrekeyID,
                oneTimePrekeyId: encrypted.oneTimePrekeyID
            ),
            sentAtClient: Date(),
            acceptedAtServer: nil,
            deliveredAt: nil,
            ackedAt: nil
        )

        let batch = SendEnvelopesBatchRequestDTO(idempotencyKey: UUID().uuidString.lowercased(), envelopes: [envelope])
        let encoded = try apiClient.encodeBody(batch)
        _ = try await apiClient.request(
            path: "v1/messages/envelopes:batch",
            method: "POST",
            token: token,
            body: encoded
        ) as SendEnvelopesBatchResponseDTO

        appendMessage(
            ChatMessage(id: envelope.envelopeId, text: text, createdAt: DateCodec.isoOut.string(from: Date()), isMine: true),
            to: conversationID
        )
        updateChatPreview(conversationID: conversationID, message: text, createdAt: DateCodec.isoOut.string(from: Date()))
    }

    func refreshChats() async throws {
        let token = try requireAccessToken()
        guard let myID = sessionStore.userID else { return }

        let conversations: [ConversationDTO] = try await apiClient.request(path: "v1/conversations", token: token)

        var loaded: [Friend] = []
        for conversation in conversations {
            let participants: [ParticipantDTO] = try await apiClient.request(
                path: "v1/conversations/\(conversation.id)/participants",
                token: token
            )
            guard let peer = participants.first(where: { $0.userId != myID }) else { continue }
            try? await loadConversationHistory(conversationID: conversation.id, limit: 200)
            let lastMessage = messagesByConversation[conversation.id]?.last?.text ?? ""
            let lastTime = messagesByConversation[conversation.id]?.last?.createdAt ?? DateCodec.isoOut.string(from: conversation.createdAt)
            let recipientDeviceID = try? await fetchPrimaryDeviceID(for: peer.userId)

            loaded.append(
                Friend(
                    id: peer.userId,
                    username: peer.username,
                    lastMessage: lastMessage,
                    lastMessageTime: lastTime,
                    conversationID: conversation.id,
                    recipientDeviceID: recipientDeviceID
                )
            )
        }

        chats = loaded.sorted { $0.username.lowercased() < $1.username.lowercased() }
    }

    func loadConversationHistory(conversationID: String, limit: Int = 100) async throws {
        let token = try requireAccessToken()
        let history: [EnvelopeDTO] = try await apiClient.request(
            path: "v1/messages/conversations/\(conversationID)",
            token: token,
            query: [URLQueryItem(name: "limit", value: "\(limit)")]
        )

        let mapped = history.map { envelope in
            let decrypted = self.decryptEnvelopeText(envelope)
            return ChatMessage(
                id: envelope.envelopeId,
                text: decrypted,
                createdAt: DateCodec.isoOut.string(from: envelope.sentAtClient),
                isMine: envelope.senderUserId == sessionStore.userID
            )
        }
        mergeMessages(mapped, to: conversationID)
    }

    func refreshPendingMessages() async throws {
        if isRefreshingPendingMessages {
            return
        }
        isRefreshingPendingMessages = true
        defer { isRefreshingPendingMessages = false }

        let token = try requireAccessToken()
        guard let deviceID = sessionStore.deviceID else { return }

        let pending: [EnvelopeDTO] = try await apiClient.request(
            path: "v1/messages/envelopes/pending",
            token: token,
            query: [
                URLQueryItem(name: "device_id", value: deviceID),
                URLQueryItem(name: "limit", value: "100")
            ]
        )

        for envelope in pending {
            let isMine = envelope.senderUserId == sessionStore.userID
            let createdAt = DateCodec.isoOut.string(from: envelope.sentAtClient)
            let decrypted = decryptEnvelopeText(envelope)
            appendMessage(
                ChatMessage(
                    id: envelope.envelopeId,
                    text: decrypted,
                    createdAt: createdAt,
                    isMine: isMine
                ),
                to: envelope.conversationId
            )
            try? await ensureChatExistsForConversation(envelope.conversationId)
            updateChatPreview(conversationID: envelope.conversationId, message: decrypted, createdAt: createdAt)

            let ackBody = AckEnvelopeRequestDTO(deviceId: deviceID)
            let encoded = try apiClient.encodeBody(ackBody)
            _ = try await apiClient.request(
                path: "v1/messages/envelopes/\(envelope.envelopeId)/ack",
                method: "POST",
                token: token,
                body: encoded
            ) as EmptyResponseDTO
        }
    }

    private func bootstrapAfterLogin() async {
        do {
            try await fetchAndSaveCurrentUser()
            try enforceSingleAccountPolicy()
            if let currentUserID = sessionStore.userID {
                sessionStore.activateDevice(for: currentUserID)
            }
            try await registerCurrentDevice()
            connectWebSocketIfPossible()
            try await refreshChats()
            try await refreshPendingMessages()
        } catch {
            latestError = error.localizedDescription
        }
    }

    private func handleRealtimeEvent(_ event: RealtimeEventDTO) async {
        guard event.type == "new_envelope" else { return }
        do {
            try await refreshPendingMessages()
            if let conversationID = event.conversationId {
                try await loadConversationHistory(conversationID: conversationID, limit: 200)
                try? await ensureChatExistsForConversation(conversationID)
            }
        } catch {
            latestError = error.localizedDescription
        }
    }

    private func connectWebSocketIfPossible() {
        guard let token = sessionStore.accessToken, let deviceID = sessionStore.deviceID else { return }
        webSocket.connect(accessToken: token, deviceID: deviceID)
    }

    private func fetchAndSaveCurrentUser() async throws {
        let token = try requireAccessToken()
        let me: UserSummaryDTO = try await apiClient.request(path: "v1/users/me", token: token)
        sessionStore.saveUser(id: me.id, username: me.username)
        currentUsername = me.username
    }

    private func registerCurrentDevice() async throws {
        let token = try requireAccessToken()
        guard let deviceID = sessionStore.deviceID else { return }
        guard let currentUserID = sessionStore.userID else {
            throw APIClientError.server(status: 401, message: "Session user is not initialized")
        }

        let body = try cryptoService.registrationBundle(userID: currentUserID, deviceID: deviceID)

        let encoded = try apiClient.encodeBody(body)
        let registered: DeviceRegisterResponseDTO = try await apiClient.request(
            path: "v1/auth/devices/register",
            method: "POST",
            token: token,
            headers: ["X-Device-Id": deviceID],
            body: encoded
        )
        sessionStore.setActiveDevice(registered.deviceId, for: currentUserID)
    }

    private func fetchPrimaryDeviceID(for userID: String) async throws -> String? {
        return try await fetchPrimaryKeyBundle(for: userID)?.deviceId
    }

    private func fetchPrimaryKeyBundle(for userID: String) async throws -> KeyBundleDTO? {
        let token = try requireAccessToken()
        let bundles: [KeyBundleDTO] = try await apiClient.request(path: "v1/keys/users/\(userID)/bundles", token: token)
        return bundles.first
    }

    private func claimOneTimePrekeyBundle(for userID: String, deviceID: String?) async throws -> KeyBundleDTO {
        let token = try requireAccessToken()
        var query: [URLQueryItem] = []
        if let deviceID {
            query.append(URLQueryItem(name: "device_id", value: deviceID))
        }
        return try await apiClient.request(
            path: "v1/keys/users/\(userID)/one-time-prekey/claim",
            method: "POST",
            token: token,
            query: query
        )
    }

    private func ensureOutboundSession(
        senderUserID: String,
        senderDeviceID: String,
        recipientUserID: String,
        recipientDeviceIDHint: String?,
        conversationID: String
    ) async throws -> CryptoService.OutboundSession {
        if let recipientDeviceIDHint,
           let existing = cryptoService.getOutboundSession(
               senderUserID: senderUserID,
               senderDeviceID: senderDeviceID,
               recipientUserID: recipientUserID,
               recipientDeviceID: recipientDeviceIDHint,
               conversationID: conversationID
           ),
           existing.recipientSignedPrekeyID != nil,
           existing.recipientSignedPrekeyPub != nil,
           existing.senderEphemeralPrivateKey != nil {
            return existing
        }

        let claimed: KeyBundleDTO
        do {
            claimed = try await claimOneTimePrekeyBundle(for: recipientUserID, deviceID: recipientDeviceIDHint)
        } catch {
            guard let fallback = try await fetchPrimaryKeyBundle(for: recipientUserID) else {
                throw error
            }
            claimed = fallback
        }

        try cryptoService.validateKeyBundle(claimed)
        return cryptoService.createOrUpdateOutboundSession(
            senderUserID: senderUserID,
            senderDeviceID: senderDeviceID,
            recipientUserID: recipientUserID,
            recipientDeviceID: claimed.deviceId,
            recipientIdentityPub: claimed.identityKeyPub,
            recipientSignedPrekeyID: claimed.signedPrekeyId,
            recipientSignedPrekeyPub: claimed.signedPrekeyPub,
            recipientOneTimePrekeyPub: claimed.oneTimePrekey?.prekeyPub,
            conversationID: conversationID,
            claimedOneTimePrekeyID: claimed.oneTimePrekey?.prekeyId
        )
    }

    private func ensureChatExistsForConversation(_ conversationID: String) async throws {
        if chats.contains(where: { $0.conversationID == conversationID }) {
            return
        }
        guard let myID = sessionStore.userID else { return }
        let token = try requireAccessToken()
        let participants: [ParticipantDTO] = try await apiClient.request(
            path: "v1/conversations/\(conversationID)/participants",
            token: token
        )
        guard let peer = participants.first(where: { $0.userId != myID }) else { return }
        let recipientDeviceID = try? await fetchPrimaryDeviceID(for: peer.userId)
        let lastMessage = messagesByConversation[conversationID]?.last?.text ?? ""
        let lastMessageTime = messagesByConversation[conversationID]?.last?.createdAt ?? DateCodec.isoOut.string(from: Date())

        upsertChat(
            Friend(
                id: peer.userId,
                username: peer.username,
                lastMessage: lastMessage,
                lastMessageTime: lastMessageTime,
                conversationID: conversationID,
                recipientDeviceID: recipientDeviceID
            )
        )
    }

    private func requireAccessToken() throws -> String {
        guard let token = sessionStore.accessToken else {
            throw APIClientError.server(status: 401, message: "Session expired")
        }
        return token
    }

    private func enforceSingleAccountPolicy() throws {
        guard let currentUserID = sessionStore.userID else { return }
        if let ownerUserID = sessionStore.ownerUserID, ownerUserID != currentUserID {
            sessionStore.clearSession()
            throw APIClientError.server(
                status: 409,
                message: "Single-account mode: this app installation is already linked to another account. Reset app data to switch account."
            )
        }
        sessionStore.bindOwnerIfNeeded(currentUserID)
    }

    private func decryptEnvelopeText(_ envelope: EnvelopeDTO) -> String {
        guard let currentUserID = sessionStore.userID, let currentDeviceID = sessionStore.deviceID else {
            return envelope.ciphertext
        }
        let sessionID = extractSessionID(from: envelope.header.ratchetPub)
        return cryptoService.decryptMessage(
            ciphertext: envelope.ciphertext,
            currentUserID: currentUserID,
            currentDeviceID: currentDeviceID,
            senderDeviceID: envelope.senderDeviceId,
            recipientDeviceID: envelope.recipientDeviceId,
            senderUserID: envelope.senderUserId,
            recipientUserID: envelope.recipientUserId,
            conversationID: envelope.conversationId,
            sessionID: sessionID,
            senderEphemeralPub: envelope.header.senderEphemeralPub,
            signedPrekeyID: envelope.header.signedPrekeyId,
            oneTimePrekeyID: envelope.header.oneTimePrekeyId
        )
    }

    private func extractSessionID(from ratchetPub: String) -> String? {
        guard ratchetPub.hasPrefix("sess:") else { return nil }
        let payload = ratchetPub.dropFirst("sess:".count)
        return payload.split(separator: ":").first.map(String.init)
    }

    private func appendMessage(_ message: ChatMessage, to conversationID: String) {
        var existing = messagesByConversation[conversationID] ?? []
        if existing.contains(where: { $0.id == message.id }) {
            return
        }
        existing.append(message)
        existing.sort { $0.createdAt < $1.createdAt }
        messagesByConversation[conversationID] = existing
    }

    private func mergeMessages(_ messages: [ChatMessage], to conversationID: String) {
        var dictionary: [String: ChatMessage] = [:]
        for message in messagesByConversation[conversationID] ?? [] {
            dictionary[message.id] = message
        }
        for message in messages {
            dictionary[message.id] = message
        }
        let merged = dictionary.values.sorted { $0.createdAt < $1.createdAt }
        messagesByConversation[conversationID] = merged
    }

    private func upsertChat(_ friend: Friend) {
        if let index = chats.firstIndex(where: { $0.id == friend.id }) {
            chats[index] = friend
        } else {
            chats.append(friend)
            chats.sort { $0.username.lowercased() < $1.username.lowercased() }
        }
    }

    private func updateChatPreview(conversationID: String, message: String, createdAt: String) {
        guard let index = chats.firstIndex(where: { $0.conversationID == conversationID }) else { return }
        chats[index].lastMessage = message
        chats[index].lastMessageTime = createdAt
    }
}
