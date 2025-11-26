//
//  EncryptionSessionHelper.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 09.11.2025.
//


import Foundation
import Combine

enum SessionBootstrapper {
    static func ensureSession(recipientUserID: String, token: String) async throws -> String {
        print("in SessionBootstrapper.ensureSession for user:", recipientUserID)
        let devices = try await APIService.shared.getUserDevices(userId: recipientUserID, token: token)
        print("SB: devices for user:", devices)

        guard let first = devices.first else { throw NSError(domain: "NoRecipientDevices", code: 0) }


        if SessionManager.shared.hasSession(for: first.device_id) {
            print("SB: session already exists for device:", first.device_id)
            return first.device_id
        } else {
 
            print("SB: creating session for device:", first.device_id)
            _ = try SessionManager.shared.createSession(
                withRecipientPublicKeyBase64: first.identity_key,
                recipientId: first.device_id // <- важно: сохраняем сессию под device_id
            )
            return first.device_id
        }
    }
    
    static func ensureSession(forDeviceId deviceId: String, userId: String, token: String) async throws -> String {

            print("ensure session 2")
            if SessionManager.shared.hasSession(for: deviceId) {
                return deviceId
            }


            let devices = try await APIService.shared.getUserDevices(userId: userId, token: token)
            if let match = devices.first(where: { $0.device_id == deviceId }) {

                try SessionManager.shared.createSession(
                    withRecipientPublicKeyBase64: match.identity_key,
                    recipientId: match.device_id
                )
                return match.device_id
            } else {

                throw NSError(domain: "SessionBootstrapper", code: 0, userInfo: [NSLocalizedDescriptionKey: "Device \(deviceId) not found for user \(userId)"])
            }
        }
}

