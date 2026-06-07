import Foundation
import CryptoKit

final class CryptoService {
    private enum Constants {
        static let prefix = "e2e1:"
        static let sessionsStorageKey = "crypto.outbound.sessions.v1"
        static let keychainService = "com.whispre.client.crypto"
        static let signedPrekeyID = 1
        static let oneTimePrekeyBaseID = 100_000
        static let oneTimePrekeyBatchSize = 10
    }

    struct OutboundSession: Codable {
        let sessionID: String
        let senderUserID: String
        let senderDeviceID: String
        let recipientUserID: String
        let recipientDeviceID: String
        let recipientIdentityPub: String
        let recipientSignedPrekeyID: Int?
        let recipientSignedPrekeyPub: String?
        let recipientOneTimePrekeyPub: String?
        let senderEphemeralPrivateKey: String?
        let senderEphemeralPub: String?
        let conversationID: String
        let claimedOneTimePrekeyID: Int?
        let createdAt: Date
        var lastUsedAt: Date
    }

    struct EncryptedMessage {
        let ciphertext: String
        let senderEphemeralPub: String?
        let signedPrekeyID: Int?
        let oneTimePrekeyID: Int?
    }

    private struct CipherPayload: Codable {
        let v: Int
        let alg: String
        let sid: String
        let senderIdentityPub: String
        let senderEphemeralPub: String?
        let recipientIdentityPub: String
        let signedPrekeyID: Int?
        let oneTimePrekeyID: Int?
        let ct: String
    }

    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(service: Constants.keychainService)

    func registrationBundle(userID: String, deviceID: String) throws -> DeviceRegisterRequestDTO {
        let identityPublic = try identityPublicKeyBase64(userID: userID, deviceID: deviceID)
        let signingPrivate = try identitySigningPrivateKey(userID: userID, deviceID: deviceID)
        let signingPublic = signingPrivate.publicKey.rawRepresentation.base64EncodedString()

        let signedPrekeyPrivate = try signedPrekeyPrivateKey(
            userID: userID,
            deviceID: deviceID,
            prekeyID: Constants.signedPrekeyID
        )
        let signedPrekeyPublicData = signedPrekeyPrivate.publicKey.rawRepresentation
        let signedPrekeySignature = try signingPrivate.signature(for: signedPrekeyPublicData)

        let oneTime: [DeviceRegisterRequestDTO.OneTimePrekeyDTO] = try (1...Constants.oneTimePrekeyBatchSize).map { idx in
            let prekeyID = Constants.oneTimePrekeyBaseID + idx
            let privateKey = try oneTimePrekeyPrivateKey(userID: userID, deviceID: deviceID, prekeyID: prekeyID)
            return DeviceRegisterRequestDTO.OneTimePrekeyDTO(
                prekeyID: prekeyID,
                prekeyPub: privateKey.publicKey.rawRepresentation.base64EncodedString()
            )
        }

        return DeviceRegisterRequestDTO(
            deviceName: "iOS Device",
            platform: "ios",
            identityKeyPub: identityPublic,
            identitySigningKeyPub: signingPublic,
            signedPrekeyID: Constants.signedPrekeyID,
            signedPrekeyPub: signedPrekeyPublicData.base64EncodedString(),
            signedPrekeySignature: signedPrekeySignature.base64EncodedString(),
            oneTimePrekeys: oneTime
        )
    }

    func validateKeyBundle(_ bundle: KeyBundleDTO) throws {
        let identityKeyData = try decodeBase64(bundle.identityKeyPub, label: "identity key")
        _ = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: identityKeyData)

        let signedPrekeyData = try decodeBase64(bundle.signedPrekeyPub, label: "signed prekey")
        _ = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: signedPrekeyData)

        let signingKeyData = try decodeBase64(bundle.identitySigningKeyPub, label: "identity signing key")
        let signingKey = try Curve25519.Signing.PublicKey(rawRepresentation: signingKeyData)

        let signature = try decodeBase64(bundle.signedPrekeySignature, label: "signed prekey signature")
        guard signingKey.isValidSignature(signature, for: signedPrekeyData) else {
            throw APIClientError.server(status: 400, message: "Invalid signed prekey signature")
        }

        if let oneTimePrekey = bundle.oneTimePrekey {
            let oneTimeData = try decodeBase64(oneTimePrekey.prekeyPub, label: "one-time prekey")
            _ = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: oneTimeData)
        }
    }

    func encryptMessage(
        plaintext: String,
        senderUserID: String,
        senderDeviceID: String,
        recipientDeviceID: String,
        recipientIdentityPubBase64: String,
        recipientSignedPrekeyID: Int?,
        recipientSignedPrekeyPubBase64: String?,
        recipientOneTimePrekeyID: Int?,
        recipientOneTimePrekeyPubBase64: String?,
        senderEphemeralPrivateKeyBase64: String?,
        conversationID: String,
        sessionID: String?
    ) throws -> EncryptedMessage {
        let senderPrivate = try identityPrivateKey(userID: senderUserID, deviceID: senderDeviceID)
        let senderPublic = senderPrivate.publicKey.rawRepresentation.base64EncodedString()
        let sid = sessionID ?? "legacy"
        let key: SymmetricKey
        let senderEphemeralPub: String?
        let oneTimePrekeyID: Int?

        if let recipientSignedPrekeyID,
           let recipientSignedPrekeyPubBase64,
           let senderEphemeralPrivateKeyBase64 {
            let senderEphemeralPrivateData = try decodeBase64(
                senderEphemeralPrivateKeyBase64,
                label: "sender ephemeral private key"
            )
            let senderEphemeralPrivate = try Curve25519.KeyAgreement.PrivateKey(
                rawRepresentation: senderEphemeralPrivateData
            )
            senderEphemeralPub = senderEphemeralPrivate.publicKey.rawRepresentation.base64EncodedString()
            oneTimePrekeyID = recipientOneTimePrekeyPubBase64 == nil ? nil : recipientOneTimePrekeyID
            key = try deriveSenderPrekeySymmetricKey(
                senderIdentityPrivate: senderPrivate,
                senderEphemeralPrivate: senderEphemeralPrivate,
                recipientIdentityPubBase64: recipientIdentityPubBase64,
                recipientSignedPrekeyPubBase64: recipientSignedPrekeyPubBase64,
                recipientOneTimePrekeyPubBase64: recipientOneTimePrekeyPubBase64,
                conversationID: conversationID,
                senderDeviceID: senderDeviceID,
                recipientDeviceID: recipientDeviceID,
                sessionID: sid,
                signedPrekeyID: recipientSignedPrekeyID,
                oneTimePrekeyID: oneTimePrekeyID
            )
        } else {
            let recipientPublicData = try decodeBase64(recipientIdentityPubBase64, label: "recipient identity key")
            let recipientPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicData)
            let sharedSecret = try senderPrivate.sharedSecretFromKeyAgreement(with: recipientPublic)
            senderEphemeralPub = nil
            oneTimePrekeyID = nil
            key = deriveLegacySymmetricKey(
                sharedSecret: sharedSecret,
                conversationID: conversationID,
                senderDeviceID: senderDeviceID,
                recipientDeviceID: recipientDeviceID,
                sessionID: sessionID
            )
        }

        let plaintextData = Data(plaintext.utf8)
        let sealed = try ChaChaPoly.seal(plaintextData, using: key)
        let combined = sealed.combined

        let payload = CipherPayload(
            v: senderEphemeralPub == nil ? 1 : 2,
            alg: "X25519+ChaCha20-Poly1305",
            sid: sid,
            senderIdentityPub: senderPublic,
            senderEphemeralPub: senderEphemeralPub,
            recipientIdentityPub: recipientIdentityPubBase64,
            signedPrekeyID: recipientSignedPrekeyID,
            oneTimePrekeyID: oneTimePrekeyID,
            ct: combined.base64EncodedString()
        )
        let encoded = try JSONEncoder().encode(payload)
        return EncryptedMessage(
            ciphertext: Constants.prefix + encoded.base64EncodedString(),
            senderEphemeralPub: senderEphemeralPub,
            signedPrekeyID: recipientSignedPrekeyID,
            oneTimePrekeyID: oneTimePrekeyID
        )
    }

    func decryptMessage(
        ciphertext: String,
        currentUserID: String,
        currentDeviceID: String,
        senderDeviceID: String,
        recipientDeviceID: String,
        senderUserID: String,
        recipientUserID: String,
        conversationID: String,
        sessionID: String?,
        senderEphemeralPub: String?,
        signedPrekeyID: Int?,
        oneTimePrekeyID: Int?
    ) -> String {
        guard ciphertext.hasPrefix(Constants.prefix) else {
            return ciphertext
        }

        do {
            let encodedPayload = String(ciphertext.dropFirst(Constants.prefix.count))
            let payloadData = try decodeBase64(encodedPayload, label: "cipher payload")
            let payload = try JSONDecoder().decode(CipherPayload.self, from: payloadData)
            let resolvedSessionID = sessionID ?? payload.sid
            let resolvedSenderEphemeralPub = senderEphemeralPub ?? payload.senderEphemeralPub
            let resolvedSignedPrekeyID = signedPrekeyID ?? payload.signedPrekeyID
            let resolvedOneTimePrekeyID = oneTimePrekeyID ?? payload.oneTimePrekeyID

            let key: SymmetricKey
            if payload.v >= 2,
               let resolvedSenderEphemeralPub,
               let resolvedSignedPrekeyID {
                if senderUserID == currentUserID {
                    guard let session = getOutboundSession(
                        senderUserID: currentUserID,
                        senderDeviceID: currentDeviceID,
                        recipientUserID: recipientUserID,
                        recipientDeviceID: recipientDeviceID,
                        conversationID: conversationID
                    ),
                          let senderEphemeralPrivateKey = session.senderEphemeralPrivateKey,
                          let recipientSignedPrekeyPub = session.recipientSignedPrekeyPub else {
                        throw APIClientError.server(status: -1, message: "Missing local outbound session")
                    }
                    let senderIdentityPrivate = try identityPrivateKey(userID: currentUserID, deviceID: currentDeviceID)
                    let senderEphemeralPrivateData = try decodeBase64(
                        senderEphemeralPrivateKey,
                        label: "sender ephemeral private key"
                    )
                    let senderEphemeralPrivate = try Curve25519.KeyAgreement.PrivateKey(
                        rawRepresentation: senderEphemeralPrivateData
                    )
                    key = try deriveSenderPrekeySymmetricKey(
                        senderIdentityPrivate: senderIdentityPrivate,
                        senderEphemeralPrivate: senderEphemeralPrivate,
                        recipientIdentityPubBase64: payload.recipientIdentityPub,
                        recipientSignedPrekeyPubBase64: recipientSignedPrekeyPub,
                        recipientOneTimePrekeyPubBase64: session.recipientOneTimePrekeyPub,
                        conversationID: conversationID,
                        senderDeviceID: senderDeviceID,
                        recipientDeviceID: recipientDeviceID,
                        sessionID: resolvedSessionID,
                        signedPrekeyID: resolvedSignedPrekeyID,
                        oneTimePrekeyID: resolvedOneTimePrekeyID
                    )
                } else {
                    let myIdentityPrivate = try identityPrivateKey(userID: currentUserID, deviceID: currentDeviceID)
                    let mySignedPrekeyPrivate = try signedPrekeyPrivateKey(
                        userID: currentUserID,
                        deviceID: currentDeviceID,
                        prekeyID: resolvedSignedPrekeyID
                    )
                    let myOneTimePrekeyPrivate: Curve25519.KeyAgreement.PrivateKey?
                    if let resolvedOneTimePrekeyID {
                        myOneTimePrekeyPrivate = try oneTimePrekeyPrivateKey(
                            userID: currentUserID,
                            deviceID: currentDeviceID,
                            prekeyID: resolvedOneTimePrekeyID
                        )
                    } else {
                        myOneTimePrekeyPrivate = nil
                    }
                    key = try deriveRecipientPrekeySymmetricKey(
                        recipientIdentityPrivate: myIdentityPrivate,
                        recipientSignedPrekeyPrivate: mySignedPrekeyPrivate,
                        recipientOneTimePrekeyPrivate: myOneTimePrekeyPrivate,
                        senderIdentityPubBase64: payload.senderIdentityPub,
                        senderEphemeralPubBase64: resolvedSenderEphemeralPub,
                        conversationID: conversationID,
                        senderDeviceID: senderDeviceID,
                        recipientDeviceID: recipientDeviceID,
                        sessionID: resolvedSessionID,
                        signedPrekeyID: resolvedSignedPrekeyID,
                        oneTimePrekeyID: resolvedOneTimePrekeyID
                    )
                }
            } else {
                let myPrivate = try identityPrivateKey(userID: currentUserID, deviceID: currentDeviceID)
                let peerPublicBase64 = senderUserID == currentUserID ? payload.recipientIdentityPub : payload.senderIdentityPub
                let peerPublicData = try decodeBase64(peerPublicBase64, label: "peer identity key")
                let peerPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicData)
                let sharedSecret = try myPrivate.sharedSecretFromKeyAgreement(with: peerPublic)
                key = deriveLegacySymmetricKey(
                    sharedSecret: sharedSecret,
                    conversationID: conversationID,
                    senderDeviceID: senderDeviceID,
                    recipientDeviceID: recipientDeviceID,
                    sessionID: resolvedSessionID
                )
            }

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
        recipientSignedPrekeyID: Int?,
        recipientSignedPrekeyPub: String?,
        recipientOneTimePrekeyPub: String?,
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
        let existingEphemeralPrivate = all[key]?.senderEphemeralPrivateKey
        let ephemeralPrivate: Curve25519.KeyAgreement.PrivateKey
        if let existingEphemeralPrivate,
           let existingEphemeralData = Data(base64Encoded: existingEphemeralPrivate),
           let existing = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: existingEphemeralData) {
            ephemeralPrivate = existing
        } else {
            ephemeralPrivate = Curve25519.KeyAgreement.PrivateKey()
        }
        let session = OutboundSession(
            sessionID: existingID,
            senderUserID: senderUserID,
            senderDeviceID: senderDeviceID,
            recipientUserID: recipientUserID,
            recipientDeviceID: recipientDeviceID,
            recipientIdentityPub: recipientIdentityPub,
            recipientSignedPrekeyID: recipientSignedPrekeyID,
            recipientSignedPrekeyPub: recipientSignedPrekeyPub,
            recipientOneTimePrekeyPub: recipientOneTimePrekeyPub,
            senderEphemeralPrivateKey: ephemeralPrivate.rawRepresentation.base64EncodedString(),
            senderEphemeralPub: ephemeralPrivate.publicKey.rawRepresentation.base64EncodedString(),
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

    private func identitySigningPrivateKey(userID: String, deviceID: String) throws -> Curve25519.Signing.PrivateKey {
        let key = signingStorageKey(userID: userID, deviceID: deviceID)
        if let data = keychain.getData(account: key) {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        }

        let generated = Curve25519.Signing.PrivateKey()
        keychain.setData(generated.rawRepresentation, account: key)
        return generated
    }

    private func signedPrekeyPrivateKey(
        userID: String,
        deviceID: String,
        prekeyID: Int
    ) throws -> Curve25519.KeyAgreement.PrivateKey {
        let key = signedPrekeyStorageKey(userID: userID, deviceID: deviceID, prekeyID: prekeyID)
        if let data = keychain.getData(account: key) {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }

        let generated = Curve25519.KeyAgreement.PrivateKey()
        keychain.setData(generated.rawRepresentation, account: key)
        return generated
    }

    private func oneTimePrekeyPrivateKey(
        userID: String,
        deviceID: String,
        prekeyID: Int
    ) throws -> Curve25519.KeyAgreement.PrivateKey {
        let key = oneTimePrekeyStorageKey(userID: userID, deviceID: deviceID, prekeyID: prekeyID)
        if let data = keychain.getData(account: key) {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }

        let generated = Curve25519.KeyAgreement.PrivateKey()
        keychain.setData(generated.rawRepresentation, account: key)
        return generated
    }

    private func storageKey(userID: String, deviceID: String) -> String {
        "crypto.identity.\(userID).\(deviceID)"
    }

    private func signingStorageKey(userID: String, deviceID: String) -> String {
        "crypto.identity.signing.\(userID).\(deviceID)"
    }

    private func signedPrekeyStorageKey(userID: String, deviceID: String, prekeyID: Int) -> String {
        "crypto.signedPrekey.\(userID).\(deviceID).\(prekeyID)"
    }

    private func oneTimePrekeyStorageKey(userID: String, deviceID: String, prekeyID: Int) -> String {
        "crypto.oneTimePrekey.\(userID).\(deviceID).\(prekeyID)"
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

    private func deriveLegacySymmetricKey(
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

    private func deriveSenderPrekeySymmetricKey(
        senderIdentityPrivate: Curve25519.KeyAgreement.PrivateKey,
        senderEphemeralPrivate: Curve25519.KeyAgreement.PrivateKey,
        recipientIdentityPubBase64: String,
        recipientSignedPrekeyPubBase64: String,
        recipientOneTimePrekeyPubBase64: String?,
        conversationID: String,
        senderDeviceID: String,
        recipientDeviceID: String,
        sessionID: String,
        signedPrekeyID: Int,
        oneTimePrekeyID: Int?
    ) throws -> SymmetricKey {
        let recipientIdentityData = try decodeBase64(recipientIdentityPubBase64, label: "recipient identity key")
        let recipientIdentityPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientIdentityData)
        let recipientSignedData = try decodeBase64(recipientSignedPrekeyPubBase64, label: "recipient signed prekey")
        let recipientSignedPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientSignedData)

        var components: [Data] = []
        components.append(try deriveComponent(
            senderIdentityPrivate.sharedSecretFromKeyAgreement(with: recipientSignedPublic),
            label: "dh1-identity-signed"
        ))
        components.append(try deriveComponent(
            senderEphemeralPrivate.sharedSecretFromKeyAgreement(with: recipientIdentityPublic),
            label: "dh2-ephemeral-identity"
        ))
        components.append(try deriveComponent(
            senderEphemeralPrivate.sharedSecretFromKeyAgreement(with: recipientSignedPublic),
            label: "dh3-ephemeral-signed"
        ))

        if let recipientOneTimePrekeyPubBase64 {
            let recipientOneTimeData = try decodeBase64(recipientOneTimePrekeyPubBase64, label: "recipient one-time prekey")
            let recipientOneTimePublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientOneTimeData)
            components.append(try deriveComponent(
                senderEphemeralPrivate.sharedSecretFromKeyAgreement(with: recipientOneTimePublic),
                label: "dh4-ephemeral-onetime"
            ))
        }

        return derivePrekeySymmetricKey(
            components: components,
            conversationID: conversationID,
            senderDeviceID: senderDeviceID,
            recipientDeviceID: recipientDeviceID,
            sessionID: sessionID,
            signedPrekeyID: signedPrekeyID,
            oneTimePrekeyID: oneTimePrekeyID
        )
    }

    private func deriveRecipientPrekeySymmetricKey(
        recipientIdentityPrivate: Curve25519.KeyAgreement.PrivateKey,
        recipientSignedPrekeyPrivate: Curve25519.KeyAgreement.PrivateKey,
        recipientOneTimePrekeyPrivate: Curve25519.KeyAgreement.PrivateKey?,
        senderIdentityPubBase64: String,
        senderEphemeralPubBase64: String,
        conversationID: String,
        senderDeviceID: String,
        recipientDeviceID: String,
        sessionID: String,
        signedPrekeyID: Int,
        oneTimePrekeyID: Int?
    ) throws -> SymmetricKey {
        let senderIdentityData = try decodeBase64(senderIdentityPubBase64, label: "sender identity key")
        let senderIdentityPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderIdentityData)
        let senderEphemeralData = try decodeBase64(senderEphemeralPubBase64, label: "sender ephemeral key")
        let senderEphemeralPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderEphemeralData)

        var components: [Data] = []
        components.append(try deriveComponent(
            recipientSignedPrekeyPrivate.sharedSecretFromKeyAgreement(with: senderIdentityPublic),
            label: "dh1-identity-signed"
        ))
        components.append(try deriveComponent(
            recipientIdentityPrivate.sharedSecretFromKeyAgreement(with: senderEphemeralPublic),
            label: "dh2-ephemeral-identity"
        ))
        components.append(try deriveComponent(
            recipientSignedPrekeyPrivate.sharedSecretFromKeyAgreement(with: senderEphemeralPublic),
            label: "dh3-ephemeral-signed"
        ))

        if let recipientOneTimePrekeyPrivate {
            components.append(try deriveComponent(
                recipientOneTimePrekeyPrivate.sharedSecretFromKeyAgreement(with: senderEphemeralPublic),
                label: "dh4-ephemeral-onetime"
            ))
        }

        return derivePrekeySymmetricKey(
            components: components,
            conversationID: conversationID,
            senderDeviceID: senderDeviceID,
            recipientDeviceID: recipientDeviceID,
            sessionID: sessionID,
            signedPrekeyID: signedPrekeyID,
            oneTimePrekeyID: oneTimePrekeyID
        )
    }

    private func deriveComponent(_ sharedSecret: SharedSecret, label: String) throws -> Data {
        let key = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("whispre-x3dh-component-v1".utf8),
            sharedInfo: Data(label.utf8),
            outputByteCount: 32
        )
        return keyData(key)
    }

    private func derivePrekeySymmetricKey(
        components: [Data],
        conversationID: String,
        senderDeviceID: String,
        recipientDeviceID: String,
        sessionID: String,
        signedPrekeyID: Int,
        oneTimePrekeyID: Int?
    ) -> SymmetricKey {
        var input = Data()
        for component in components {
            input.append(component)
        }
        let inputMaterial = SymmetricKey(data: input)
        let oneTimePart = oneTimePrekeyID.map(String.init) ?? "none"
        let info = Data(
            "v2|\(conversationID)|\(senderDeviceID)|\(recipientDeviceID)|\(sessionID)|spk:\(signedPrekeyID)|otk:\(oneTimePart)".utf8
        )
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputMaterial,
            salt: Data("whispre-e2e-prekey-v1".utf8),
            info: info,
            outputByteCount: 32
        )
    }

    private func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
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
}
