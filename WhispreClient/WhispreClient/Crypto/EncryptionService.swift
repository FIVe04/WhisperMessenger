//
//  Enc.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//


import Foundation
import CryptoKit

final class EncryptionService {
    static let shared = EncryptionService()
    private init() {}

    struct HandshakeMetadata: Codable {
        let ephemeralPub: String
        let recipientOneTimePrekey: String
    }

    private struct CipherEnvelope: Codable {
        let ciphertext: String
        let handshake: HandshakeMetadata?
    }
    
    enum EncryptionError: Error {
        case noSessionKey
        case invalidCiphertext
        case encryptionFailed
        case decryptionFailed
    }
    
    // MARK: - Шифрование
    

    func encryptMessage(_ text: String, recipientId: String, handshake: HandshakeMetadata? = nil) throws -> String {
        guard let session = SessionManager.shared.getSession(for: recipientId) else {
            throw EncryptionError.noSessionKey
        }
        
        let key = session.symmetricKey()
        let data = Data(text.utf8)
        
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            let combined = sealedBox.combined ?? Data()
            let base64Cipher = combined.base64EncodedString()
            if let handshake = handshake {
                let envelope = CipherEnvelope(ciphertext: base64Cipher, handshake: handshake)
                let jsonData = try JSONEncoder().encode(envelope)
                return String(data: jsonData, encoding: .utf8) ?? base64Cipher
            } else {
                return base64Cipher
            }
        } catch {
            throw EncryptionError.encryptionFailed
        }
    }
    
    // MARK: - Дешифрование
    

    func decryptMessage(_ ciphertextOrEnvelope: String, senderId: String) throws -> String {
        let envelope = decodeEnvelope(ciphertextOrEnvelope)
        guard let session = SessionManager.shared.getSession(for: senderId) else {
            throw EncryptionError.noSessionKey
        }

        let base64Cipher = envelope?.ciphertext ?? ciphertextOrEnvelope
        guard let data = Data(base64Encoded: base64Cipher) else {
            throw EncryptionError.invalidCiphertext
        }

        let key = session.symmetricKey()

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8) ?? ""
        } catch {
            throw EncryptionError.decryptionFailed
        }
    }

    private func decodeEnvelope(_ maybeJSON: String) -> CipherEnvelope? {
        if let data = maybeJSON.data(using: .utf8),
           let env = try? JSONDecoder().decode(CipherEnvelope.self, from: data) {
            return env
        }
        // Попробуем сначала base64-декодировать, если сервер вернул base64 от JSON
        if let raw = Data(base64Encoded: maybeJSON),
           let env = try? JSONDecoder().decode(CipherEnvelope.self, from: raw) {
            return env
        }
        return nil
    }

    private func deriveSymmetricKeyData(from sharedSecret: SharedSecret) -> Data {
        let salt = "WhispreHKDFSalt_OTPK_v1".data(using: .utf8)!
        let symKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data(),
            outputByteCount: 32
        )
        return symKey.withUnsafeBytes { Data($0) }
    }

    private func tryBootstrapFromHandshake(_ ciphertext: String, senderId: String) -> Bool {
        guard let envelope = decodeEnvelope(ciphertext),
              let handshake = envelope.handshake,
              let myUserId = UserDefaults.standard.string(forKey: "userId"),
              let ephData = Data(base64Encoded: handshake.ephemeralPub),
              let ephPub = try? P256.KeyAgreement.PublicKey(rawRepresentation: ephData),
              let otpkPriv = KeyManager.shared.consumeOneTimePreKey(for: myUserId, publicKeyBase64: handshake.recipientOneTimePrekey) else {
            return false
        }

        do {
            let shared = try otpkPriv.sharedSecretFromKeyAgreement(with: ephPub)
            let keyData = deriveSymmetricKeyData(from: shared)
            SessionManager.shared.createSessionFromSymmetricKey(recipientId: senderId, keyData: keyData)
            print("✅ Restored session from one-time prekey for \(senderId)")
            return true
        } catch {
            print("❌ Failed DH with one-time prekey:", error.localizedDescription)
            return false
        }
    }

    func createSessionUsingOneTimePrekey(recipientDeviceId: String, recipientOneTimePrekeyBase64: String) throws -> HandshakeMetadata {
        guard let otpkData = Data(base64Encoded: recipientOneTimePrekeyBase64) else {
            throw EncryptionError.invalidCiphertext
        }
        let otpkPub = try P256.KeyAgreement.PublicKey(rawRepresentation: otpkData)
        let ephPriv = P256.KeyAgreement.PrivateKey()
        let shared = try ephPriv.sharedSecretFromKeyAgreement(with: otpkPub)
        let keyData = deriveSymmetricKeyData(from: shared)
        SessionManager.shared.createSessionFromSymmetricKey(recipientId: recipientDeviceId, keyData: keyData)

        let ephPubBase64 = ephPriv.publicKey.rawRepresentation.base64EncodedString()
        return HandshakeMetadata(ephemeralPub: ephPubBase64, recipientOneTimePrekey: recipientOneTimePrekeyBase64)
    }
}

extension EncryptionService {
    
    func decryptMessageWithAutoSession(
        _ ciphertext: String,
        senderId: String,
        senderUserId: String,
        token: String
    ) async -> String {
        do {
            return try decryptMessage(ciphertext, senderId: senderId)
        } catch {
            print("⚠️ Decrypt failed for \(senderId). Trying to refresh session…")

            // 1) Попробуем восстановить сессию по one-time prekey из конверта
            if tryBootstrapFromHandshake(ciphertext, senderId: senderId) {
                do {
                    return try decryptMessage(ciphertext, senderId: senderId)
                } catch {
                    print("❌ Decrypt still failed after handshake bootstrap:", error.localizedDescription)
                }
            }

            // 2) Фоллбек: старый обмен через identity_key
            do {

                let keyBundles = try await APIService.shared.exchangeKeys(recipientId: senderUserId, token: token)
                for bundle in keyBundles {
                    if let identityKey = bundle["identity_key"] as? String {
                        let deviceId = bundle["device_id"] as? String ?? senderUserId
                        try SessionManager.shared.createSession(
                            withRecipientPublicKeyBase64: identityKey,
                            recipientId: deviceId
                        )
                        print("✅ Recreated session for \(deviceId)")
                    }
                }
                

                return try decryptMessage(ciphertext, senderId: senderId)
            } catch {
                print("❌ Failed to recover session for \(senderId): \(error.localizedDescription)")
                return "🔒"
            }
        }
    }
}
