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

    private func oneTimePreKeyStorageKey(for userId: String) -> String {
        return "com.whispre.\(userId).oneTimePreKeys"
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

    // MARK: - One-time Prekeys (храним приватные ключи локально)

    func storeOneTimePreKeys(for userId: String, keys: [P256.KeyAgreement.PrivateKey]) {
        let storageKey = oneTimePreKeyStorageKey(for: userId)
        var dict: [String: String] = [:] // pubBase64 -> privRawBase64
        for key in keys {
            let pub = key.publicKey.rawRepresentation.base64EncodedString()
            let priv = key.rawRepresentation.base64EncodedString()
            dict[pub] = priv
        }
        UserDefaults.standard.set(dict, forKey: storageKey)
    }

    func consumeOneTimePreKey(for userId: String, publicKeyBase64: String, remove: Bool = false) -> P256.KeyAgreement.PrivateKey? {
        let storageKey = oneTimePreKeyStorageKey(for: userId)
        guard var dict = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String],
              let privBase64 = dict[publicKeyBase64],
              let privData = Data(base64Encoded: privBase64),
              let priv = try? P256.KeyAgreement.PrivateKey(rawRepresentation: privData) else {
            return nil
        }
        if remove {
            dict.removeValue(forKey: publicKeyBase64)
            UserDefaults.standard.set(dict, forKey: storageKey)
        }
        return priv
    }

    func hasOneTimePreKey(for userId: String, publicKeyBase64: String) -> Bool {
        let storageKey = oneTimePreKeyStorageKey(for: userId)
        guard let dict = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] else { return false }
        return dict[publicKeyBase64] != nil
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
        let storageKey = oneTimePreKeyStorageKey(for: userId)
        UserDefaults.standard.removeObject(forKey: storageKey)
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
