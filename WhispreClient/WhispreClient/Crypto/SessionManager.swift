//
//  SessionManager.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//

import Foundation
import CryptoKit

public struct SessionModel: Codable {
    public let recipientId: String
    public let symmetricKeyData: Data
    public let createdAt: Date

    init(recipientId: String, symmetricKey: SymmetricKey, createdAt: Date = Date()) {
        self.recipientId = recipientId
        self.symmetricKeyData = symmetricKey.withUnsafeBytes { Data($0) }
        self.createdAt = createdAt
    }

    func symmetricKey() -> SymmetricKey {
        return SymmetricKey(data: symmetricKeyData)
    }
}

final class SessionManager {
    static let shared = SessionManager()
    private init() {
        loadFromStorage()
    }

    // MARK: - Сессии
    private var currentUserId: String?
    private var sessions: [String: SessionModel] = [:]              // recipientId -> SessionModel
    private var sessionsPerUser: [String: [String: SessionModel]] = [:] // userId -> sessions

    private let queue = DispatchQueue(label: "com.whispre.sessionmanager", attributes: .concurrent)
    private let storageKey = "com.whispre.sessions.v2"

    // MARK: - Активный пользователь
    func loginUser(userId: String) {
        queue.async(flags: .barrier) {
            self.saveCurrentUserSessions() // сохраняем предыдущего
            self.currentUserId = userId
            self.sessions = self.sessionsPerUser[userId] ?? [:]
        }
    }

    func logoutCurrentUser() {
        queue.async(flags: .barrier) {
            if let userId = self.currentUserId {
                self.sessionsPerUser[userId]?.removeAll()
            }
            self.sessions.removeAll()
            self.currentUserId = nil
            self.persistToStorage()
        }
    }
    
    func resetAll() {
            queue.async(flags: .barrier) {
                self.sessions.removeAll()
                self.sessionsPerUser.removeAll()
                self.currentUserId = nil
                UserDefaults.standard.removeObject(forKey: self.storageKey)
                print("🧹 SessionManager: fully reset and cleared from UserDefaults")
            }
        }

    private func saveCurrentUserSessions() {
        guard let userId = currentUserId else { return }
        self.sessionsPerUser[userId] = self.sessions
        persistToStorage()
    }

    // MARK: - Сессии
    @discardableResult
    func createSession(
        withRecipientPublicKeyBase64 recipientPublicKeyBase64: String,
        recipientId: String,
        myPrivateKey: P256.KeyAgreement.PrivateKey? = nil,
        salt: Data? = nil
    ) throws -> SessionModel {
        guard let pubData = Data(base64Encoded: recipientPublicKeyBase64) else {
            throw SessionError.invalidPublicKey
        }
        let recipientPubKey = try P256.KeyAgreement.PublicKey(rawRepresentation: pubData)

        // Текущий пользователь
        let currentUserId = self.currentUserId ?? "unknown"

        // Получаем private key
        let myPriv: P256.KeyAgreement.PrivateKey
        if let provided = myPrivateKey {
            myPriv = provided
        } else if let loaded = KeyManager.shared.loadIdentityKey(for: currentUserId) {
            myPriv = loaded
        } else {
            myPriv = KeyManager.shared.generateIdentityKey(for: currentUserId)
        }

        let sharedSecret = try myPriv.sharedSecretFromKeyAgreement(with: recipientPubKey)
        let saltData = salt ?? ("WhispreHKDFSalt_v2".data(using: .utf8)!)
        let sharedInfo = Data()
        let symKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: saltData,
            sharedInfo: sharedInfo,
            outputByteCount: 32
        )

        let sessionModel = SessionModel(recipientId: recipientId, symmetricKey: symKey)
        saveSession(sessionModel)
        return sessionModel
    }

    func getSession(for recipientId: String) -> SessionModel? {
        var result: SessionModel?
        queue.sync { result = sessions[recipientId] }
        return result
    }

    func hasSession(for recipientId: String) -> Bool {
        var exists = false
        queue.sync { exists = sessions[recipientId] != nil }
        return exists
    }

    func removeSession(for recipientId: String) {
        queue.async(flags: .barrier) {
            self.sessions.removeValue(forKey: recipientId)
            self.persistToStorage()
        }
    }

    func removeAllSessions() {
        queue.async(flags: .barrier) {
            self.sessions.removeAll()
            self.persistToStorage()
        }
    }

    private func saveSession(_ session: SessionModel) {
        queue.async(flags: .barrier) {
            self.sessions[session.recipientId] = session
            self.persistToStorage()
        }
    }

    // MARK: - Persistence
    private func persistToStorage() {
        queue.async(flags: .barrier) {
            do {
                let encoder = JSONEncoder()
                let wrapper = SessionsWrapper(userSessions: self.sessionsPerUser)
                let data = try encoder.encode(wrapper)
                UserDefaults.standard.set(data, forKey: self.storageKey)
            } catch {
                print("SessionManager: failed to persist sessions:", error)
            }
        }
    }

    private func loadFromStorage() {
        queue.async(flags: .barrier) {
            guard let data = UserDefaults.standard.data(forKey: self.storageKey) else { return }
            do {
                let decoder = JSONDecoder()
                let wrapper = try decoder.decode(SessionsWrapper.self, from: data)
                self.sessionsPerUser = wrapper.userSessions
                print("SessionManager: loaded \(self.sessionsPerUser.count) users' sessions")
            } catch {
                print("SessionManager: failed to load sessions:", error)
            }
        }
    }

    // MARK: - Utilities
    func exportSymmetricKeyBase64(for recipientId: String) -> String? {
        guard let model = getSession(for: recipientId) else { return nil }
        return model.symmetricKeyData.base64EncodedString()
    }

    // MARK: - Codable wrapper
    private struct SessionsWrapper: Codable {
        var userSessions: [String: [String: SessionModel]]
    }
}

// MARK: - Errors
enum SessionError: Error {
    case invalidPublicKey
    case keyAgreementFailed
    case noPrivateKey
}
