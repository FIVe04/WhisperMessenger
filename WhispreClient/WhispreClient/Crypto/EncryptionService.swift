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
    
    enum EncryptionError: Error {
        case noSessionKey
        case invalidCiphertext
        case encryptionFailed
        case decryptionFailed
    }
    
    // MARK: - Шифрование
    

    func encryptMessage(_ text: String, recipientId: String) throws -> String {
        guard let session = SessionManager.shared.getSession(for: recipientId) else {
            throw EncryptionError.noSessionKey
        }
        
        let key = session.symmetricKey()
        let data = Data(text.utf8)
        
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            let combined = sealedBox.combined ?? Data()
            return combined.base64EncodedString()
        } catch {
            throw EncryptionError.encryptionFailed
        }
    }
    
    // MARK: - Дешифрование
    

    func decryptMessage(_ base64Ciphertext: String, senderId: String) throws -> String {
        guard let session = SessionManager.shared.getSession(for: senderId) else {
            print("error 1 dec")
            throw EncryptionError.noSessionKey
        }
        
        guard let data = Data(base64Encoded: base64Ciphertext) else {
            print("error 2 dec")
            throw EncryptionError.invalidCiphertext
        }
        
        let key = session.symmetricKey()
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8) ?? ""
        } catch {
            print("error 2 dec")
            throw EncryptionError.decryptionFailed
        }
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


