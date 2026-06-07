import Foundation

struct Friend: Identifiable, Equatable {
    let id: String
    let username: String
    var lastMessage: String
    var lastMessageTime: String
    var conversationID: String?
    var recipientDeviceID: String?
}

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let text: String
    let createdAt: String
    let isMine: Bool
}

struct AuthTokensDTO: Decodable {
    let accessToken: String
    let refreshToken: String
}

struct RegisterRequestDTO: Encodable {
    let username: String
    let email: String
    let password: String
}

struct LoginRequestDTO: Encodable {
    let email: String
    let password: String
}

struct DeviceRegisterRequestDTO: Encodable {
    struct OneTimePrekeyDTO: Encodable {
        let prekeyID: Int
        let prekeyPub: String
    }

    let deviceName: String
    let platform: String
    let identityKeyPub: String
    let identitySigningKeyPub: String
    let signedPrekeyID: Int
    let signedPrekeyPub: String
    let signedPrekeySignature: String
    let oneTimePrekeys: [OneTimePrekeyDTO]
}

struct DeviceRegisterResponseDTO: Decodable {
    let deviceId: String
    let oneTimePrekeysUploaded: Int
}

struct UserSummaryDTO: Decodable {
    let id: String
    let username: String
}

struct ConversationDTO: Decodable {
    let id: String
    let type: String
    let createdAt: Date
}

struct ParticipantDTO: Decodable {
    let userId: String
    let username: String
    let role: String
}

struct CreateDirectConversationRequestDTO: Encodable {
    let peerUserId: String
}

struct KeyBundleDTO: Decodable {
    struct OneTimePrekeyDTO: Decodable {
        let prekeyId: Int
        let prekeyPub: String
    }

    let deviceId: String
    let identityKeyPub: String
    let identitySigningKeyPub: String
    let signedPrekeyId: Int
    let signedPrekeyPub: String
    let signedPrekeySignature: String
    let oneTimePrekey: OneTimePrekeyDTO?
}

struct RatchetHeaderDTO: Codable {
    let ratchetPub: String
    let pn: Int
    let n: Int
    let protocolVersion: Int?
    let senderEphemeralPub: String?
    let signedPrekeyId: Int?
    let oneTimePrekeyId: Int?
}

struct EnvelopeDTO: Codable {
    let envelopeId: String
    let conversationId: String
    let senderUserId: String
    let senderDeviceId: String
    let recipientUserId: String
    let recipientDeviceId: String
    let ciphertext: String
    let header: RatchetHeaderDTO
    let sentAtClient: Date
    let acceptedAtServer: Date?
    let deliveredAt: Date?
    let ackedAt: Date?
}

struct SendEnvelopesBatchRequestDTO: Encodable {
    let idempotencyKey: String
    let envelopes: [EnvelopeDTO]
}

struct SendEnvelopesBatchResponseDTO: Decodable {
    let accepted: Int
}

struct AckEnvelopeRequestDTO: Encodable {
    let deviceId: String
}

struct RealtimeEventDTO: Decodable {
    let type: String
    let envelopeId: String?
    let conversationId: String?
    let senderUserId: String?
    let recipientUserId: String?
    let recipientDeviceId: String?
}

struct EmptyResponseDTO: Decodable {}

enum DateCodec {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let formatterWithFrac = ISO8601DateFormatter()
            formatterWithFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatterWithFrac.date(from: value) {
                return date
            }

            let formatterNoFrac = ISO8601DateFormatter()
            formatterNoFrac.formatOptions = [.withInternetDateTime]
            if let date = formatterNoFrac.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO date: \(value)")
        }
        return decoder
    }()

    static let isoOut: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
