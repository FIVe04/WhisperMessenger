import Foundation
import CryptoKit

final class CryptoService {
    private enum Constants {
        static let prefix = "e2e1:"
        static let sessionsStorageKey = "crypto.outbound.sessions.v1"
        static let keychainService = "com.whispre.client.crypto"
    }

    struct OutboundSession: Codable {
        let sessionID: String
        let senderUserID: String
        let senderDeviceID: String
        let recipientUserID: String
        let recipientDeviceID: String
        let recipientIdentityPub: String
        let conversationID: String
        let claimedOneTimePrekeyID: Int?
        let createdAt: Date
        var lastUsedAt: Date
    }

    private struct CipherPayload: Codable {
        let v: Int
        let alg: String
        let sid: String
        let senderIdentityPub: String
        let recipientIdentityPub: String
        let ct: String
    }

    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(service: Constants.keychainService)

    func registrationBundle(userID: String, deviceID: String) throws -> DeviceRegisterRequestDTO {
        let senderPublic = try identityPublicKeyBase64(userID: userID, deviceID: deviceID)
        let oneTime: [DeviceRegisterRequestDTO.OneTimePrekeyDTO] = (1...10).map { idx in
            DeviceRegisterRequestDTO.OneTimePrekeyDTO(
                prekeyID: 100_000 + idx,
                prekeyPub: Self.randomBase64(32)
            )
        }

        return DeviceRegisterRequestDTO(
            deviceName: "iOS Device",
            platform: "ios",
            identityKeyPub: senderPublic,
            signedPrekeyID: 1,
            signedPrekeyPub: senderPublic,
            signedPrekeySignature: "dev_signature_v1",
            oneTimePrekeys: oneTime
        )
    }

    func encryptMessage(
        plaintext: String,
        senderUserID: String,
        senderDeviceID: String,
        recipientDeviceID: String,
        recipientIdentityPubBase64: String,
        conversationID: String,
        sessionID: String?
    ) throws -> String {
        let senderPrivate = try identityPrivateKey(userID: senderUserID, deviceID: senderDeviceID)
        let senderPublic = senderPrivate.publicKey.rawRepresentation.base64EncodedString()
        let recipientPublicData = try decodeBase64(recipientIdentityPubBase64, label: "recipient identity key")
        let recipientPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicData)

        let sharedSecret = try senderPrivate.sharedSecretFromKeyAgreement(with: recipientPublic)
        let key = deriveSymmetricKey(
            sharedSecret: sharedSecret,
            conversationID: conversationID,
            senderDeviceID: senderDeviceID,
            recipientDeviceID: recipientDeviceID,
            sessionID: sessionID
        )

        let plaintextData = Data(plaintext.utf8)
        let sealed = try ChaChaPoly.seal(plaintextData, using: key)
        let combined = sealed.combined

        let sid = sessionID ?? "legacy"
        let payload = CipherPayload(
            v: 1,
            alg: "X25519+ChaCha20-Poly1305",
            sid: sid,
            senderIdentityPub: senderPublic,
            recipientIdentityPub: recipientIdentityPubBase64,
            ct: combined.base64EncodedString()
        )
        let encoded = try JSONEncoder().encode(payload)
        return Constants.prefix + encoded.base64EncodedString()
    }

    func decryptMessage(
        ciphertext: String,
        currentUserID: String,
        currentDeviceID: String,
        senderDeviceID: String,
        recipientDeviceID: String,
        senderUserID: String,
        conversationID: String,
        sessionID: String?
    ) -> String {
        guard ciphertext.hasPrefix(Constants.prefix) else {
            return ciphertext
        }

        do {
            let encodedPayload = String(ciphertext.dropFirst(Constants.prefix.count))
            let payloadData = try decodeBase64(encodedPayload, label: "cipher payload")
            let payload = try JSONDecoder().decode(CipherPayload.self, from: payloadData)

            let myPrivate = try identityPrivateKey(userID: currentUserID, deviceID: currentDeviceID)
            let peerPublicBase64 = senderUserID == currentUserID ? payload.recipientIdentityPub : payload.senderIdentityPub
            let peerPublicData = try decodeBase64(peerPublicBase64, label: "peer identity key")
            let peerPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicData)
            let sharedSecret = try myPrivate.sharedSecretFromKeyAgreement(with: peerPublic)
            let key = deriveSymmetricKey(
                sharedSecret: sharedSecret,
                conversationID: conversationID,
                senderDeviceID: senderDeviceID,
                recipientDeviceID: recipientDeviceID,
                sessionID: sessionID ?? payload.sid
            )

            let combined = try decodeBase64(payload.ct, label: "combined cipher")
            let sealed = try ChaChaPoly.SealedBox(combined: combined)
            let opened = try ChaChaPoly.open(sealed, using: key)
            return String(data: opened, encoding: .utf8) ?? ciphertext
        } catch {
            return "Encrypted message (unavailable on this device)"
        }
    }

    func identityPublicKeyBase64(userID: String, deviceID: String) throws -> String {
        let privateKey = try identityPrivateKey(userID: userID, deviceID: deviceID)
        return privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    func getOutboundSession(
        senderUserID: String,
        senderDeviceID: String,
        recipientUserID: String,
        recipientDeviceID: String,
        conversationID: String
    ) -> OutboundSession? {
        sessions()[sessionKey(
            senderUserID: senderUserID,
            senderDeviceID: senderDeviceID,
            recipientUserID: recipientUserID,
            recipientDeviceID: recipientDeviceID,
            conversationID: conversationID
        )]
    }

    func createOrUpdateOutboundSession(
        senderUserID: String,
        senderDeviceID: String,
        recipientUserID: String,
        recipientDeviceID: String,
        recipientIdentityPub: String,
        conversationID: String,
        claimedOneTimePrekeyID: Int?
    ) -> OutboundSession {
        let key = sessionKey(
            senderUserID: senderUserID,
            senderDeviceID: senderDeviceID,
            recipientUserID: recipientUserID,
            recipientDeviceID: recipientDeviceID,
            conversationID: conversationID
        )
        var all = sessions()
        let now = Date()
        let existingID = all[key]?.sessionID ?? UUID().uuidString.lowercased()
        let session = OutboundSession(
            sessionID: existingID,
            senderUserID: senderUserID,
            senderDeviceID: senderDeviceID,
            recipientUserID: recipientUserID,
            recipientDeviceID: recipientDeviceID,
            recipientIdentityPub: recipientIdentityPub,
            conversationID: conversationID,
            claimedOneTimePrekeyID: claimedOneTimePrekeyID,
            createdAt: all[key]?.createdAt ?? now,
            lastUsedAt: now
        )
        all[key] = session
        saveSessions(all)
        return session
    }

    func touchOutboundSession(_ session: OutboundSession) {
        let key = sessionKey(
            senderUserID: session.senderUserID,
            senderDeviceID: session.senderDeviceID,
            recipientUserID: session.recipientUserID,
            recipientDeviceID: session.recipientDeviceID,
            conversationID: session.conversationID
        )
        var all = sessions()
        var updated = session
        updated.lastUsedAt = Date()
        all[key] = updated
        saveSessions(all)
    }

    private func identityPrivateKey(userID: String, deviceID: String) throws -> Curve25519.KeyAgreement.PrivateKey {
        let key = storageKey(userID: userID, deviceID: deviceID)
        if let data = keychain.getData(account: key) {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }

        if let raw = defaults.string(forKey: key) {
            let data = try decodeBase64(raw, label: "identity private key")
            keychain.setData(data, account: key)
            defaults.removeObject(forKey: key)
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }

        let generated = Curve25519.KeyAgreement.PrivateKey()
        keychain.setData(generated.rawRepresentation, account: key)
        return generated
    }

    private func storageKey(userID: String, deviceID: String) -> String {
        "crypto.identity.\(userID).\(deviceID)"
    }

    private func sessionKey(
        senderUserID: String,
        senderDeviceID: String,
        recipientUserID: String,
        recipientDeviceID: String,
        conversationID: String
    ) -> String {
        "\(senderUserID)|\(senderDeviceID)|\(recipientUserID)|\(recipientDeviceID)|\(conversationID)"
    }

    private func sessions() -> [String: OutboundSession] {
        if let raw = keychain.getData(account: Constants.sessionsStorageKey),
           let decoded = try? JSONDecoder().decode([String: OutboundSession].self, from: raw) {
            return decoded
        }

        if let raw = defaults.data(forKey: Constants.sessionsStorageKey),
           let decoded = try? JSONDecoder().decode([String: OutboundSession].self, from: raw) {
            keychain.setData(raw, account: Constants.sessionsStorageKey)
            defaults.removeObject(forKey: Constants.sessionsStorageKey)
            return decoded
        }

        return [:]
    }

    private func saveSessions(_ sessions: [String: OutboundSession]) {
        guard let encoded = try? JSONEncoder().encode(sessions) else { return }
        keychain.setData(encoded, account: Constants.sessionsStorageKey)
        defaults.removeObject(forKey: Constants.sessionsStorageKey)
    }

    private func deriveSymmetricKey(
        sharedSecret: SharedSecret,
        conversationID: String,
        senderDeviceID: String,
        recipientDeviceID: String,
        sessionID: String?
    ) -> SymmetricKey {
        let salt = Data("whispre-e2e-v1".utf8)
        let sessionPart = sessionID ?? "legacy"
        let info = Data("\(conversationID)|\(senderDeviceID)|\(recipientDeviceID)|\(sessionPart)".utf8)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32
        )
    }

    private func decodeBase64(_ text: String, label: String) throws -> Data {
        guard let data = Data(base64Encoded: text) else {
            throw APIClientError.server(status: -1, message: "Invalid base64 for \(label)")
        }
        return data
    }

    func resetLocalCryptoState() {
        keychain.removeAll()

        defaults.removeObject(forKey: Constants.sessionsStorageKey)
        let keys = defaults.dictionaryRepresentation().keys
        for key in keys where key.hasPrefix("crypto.identity.") {
            defaults.removeObject(forKey: key)
        }
    }

    private static func randomBase64(_ count: Int) -> String {
        let bytes = (0..<count).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
    }
}
