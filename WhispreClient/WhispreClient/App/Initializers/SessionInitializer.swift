// SessionInitializer.swift
import Foundation
import UIKit
import CryptoKit

@MainActor
final class SessionInitializer {
    static let shared = SessionInitializer()

    func startSession() async {
        guard let accessToken = UserDefaults.standard.string(forKey: "accessToken") else {
            print("❌ No access token")
            return
        }

        do {

            let currentUserId = UserDefaults.standard.string(forKey: "userId") ?? "unknown"
            let identityKey = KeyManager.shared.loadIdentityKey(for: currentUserId) ?? KeyManager.shared.generateIdentityKey(for: currentUserId)
            let signedPreKey = KeyManager.shared.loadSignedPreKey(for: currentUserId) ?? KeyManager.shared.generateSignedPreKey(for: currentUserId)
            let signedPreKeySignature = try signedPreKey.signature(for: signedPreKey.publicKey.rawRepresentation)

            let oneTimePreKeys = KeyManager.shared.generateOneTimePreKeys(count: 10)
            let oneTimePreKeyPublics = oneTimePreKeys.map { $0.publicKey.rawRepresentation.base64EncodedString() }

            // Сохраняем приватные one-time prekeys локально, чтобы уметь их расходовать при входящих сессиях
            KeyManager.shared.storeOneTimePreKeys(for: currentUserId, keys: oneTimePreKeys)


            let deviceIdKey = "com.whispre.deviceId"
            let deviceId = UserDefaults.standard.string(forKey: deviceIdKey) ?? UUID().uuidString
            UserDefaults.standard.set(deviceId, forKey: deviceIdKey)
            let deviceName = UIDevice.current.name


            let deviceResponse = try await APIService.shared.registerDevice(
                deviceId: deviceId,
                deviceName: deviceName,
                identityKey: identityKey.publicKey.rawRepresentation.base64EncodedString(),
                signedPrekey: signedPreKey.publicKey.rawRepresentation.base64EncodedString(),
                signedPrekeySignature: signedPreKeySignature.derRepresentation.base64EncodedString(),
                oneTimePrekeys: oneTimePreKeyPublics,
                token: accessToken
            )

            print("✅ Device registered successfully — id:", deviceResponse.id)

            do {
                try await WebSocketService.shared.connect(with: accessToken)
                print("✅ WebSocket connected")
            } catch {
                print("⚠️ WebSocket connection failed:", error.localizedDescription)
            }

        } catch {
            print("❌ Session initialization failed:", error.localizedDescription)
        }
    }
}
