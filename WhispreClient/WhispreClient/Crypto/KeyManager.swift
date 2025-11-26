//
//  KeyManager.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//

import Foundation
import CryptoKit

final class KeyManager {
    static let shared = KeyManager()
    private init() {}
    
    // MARK: - Tag генераторы для разных пользователей
    private func identityKeyTag(for userId: String) -> String {
        return "com.whispre.\(userId).identityKey"
    }
    
    private func signedPreKeyTag(for userId: String) -> String {
        return "com.whispre.\(userId).signedPreKey"
    }
    
    // MARK: - Identity Key
    
    func generateIdentityKey(for userId: String) -> P256.KeyAgreement.PrivateKey {
        let key = P256.KeyAgreement.PrivateKey()
        savePrivateKey(data: key.rawRepresentation, tag: identityKeyTag(for: userId))
        return key
    }
    
    func loadIdentityKey(for userId: String) -> P256.KeyAgreement.PrivateKey? {
        guard let data = loadPrivateKey(tag: identityKeyTag(for: userId)) else { return nil }
        return try? P256.KeyAgreement.PrivateKey(rawRepresentation: data)
    }
    
    func deleteIdentityKey(for userId: String) {
        deletePrivateKey(tag: identityKeyTag(for: userId))
    }

    func deleteSignedPreKey(for userId: String) {
        deletePrivateKey(tag: signedPreKeyTag(for: userId))
    }
    
    // MARK: - Signed Prekey
    
    func generateSignedPreKey(for userId: String) -> P256.Signing.PrivateKey {
        let key = P256.Signing.PrivateKey()
        savePrivateKey(data: key.rawRepresentation, tag: signedPreKeyTag(for: userId))
        return key
    }
    
    func loadSignedPreKey(for userId: String) -> P256.Signing.PrivateKey? {
        guard let data = loadPrivateKey(tag: signedPreKeyTag(for: userId)) else { return nil }
        return try? P256.Signing.PrivateKey(rawRepresentation: data)
    }
    
    
    // MARK: - Полное удаление всех ключей пользователя
    func deleteAllKeys(for userId: String) {
        deleteIdentityKey(for: userId)
        deleteSignedPreKey(for: userId)
    }
    
    // MARK: - One-time Prekeys (опционально)
    func generateOneTimePreKeys(count: Int = 10) -> [P256.KeyAgreement.PrivateKey] {
        return (0..<count).map { _ in P256.KeyAgreement.PrivateKey() }
    }
    
    // MARK: - Storage
    
    private func savePrivateKey(data: Data, tag: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]


        SecItemDelete(query as CFDictionary)

        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadPrivateKey(tag: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deletePrivateKey(tag: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag
        ]
        SecItemDelete(query as CFDictionary)
    }

}
