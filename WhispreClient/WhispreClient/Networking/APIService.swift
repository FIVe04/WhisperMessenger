//
//  APIService.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//

import Foundation


class APIService {
    static let shared = APIService()
    private let baseURL = "http://127.0.0.1:8000"

    func login(email: String, password: String) async throws -> Token {
        guard let url = URL(string: "\(baseURL)/users/login") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "email": email,
            "password": password
        ]
        
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        

        if !(200..<300).contains(httpResponse.statusCode) {
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: apiError.detail])
            } else if let validationError = try? JSONDecoder().decode(APIValidationErrorResponse.self, from: data) {
                let messages = validationError.detail.map { "\($0.loc.joined(separator: ".")): \($0.msg)" }
                let combinedMessage = messages.joined(separator: "\n")
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: combinedMessage])
            } else if let errorString = String(data: data, encoding: .utf8) {
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorString])
            } else {
                throw URLError(.badServerResponse)
            }
        }
        
        
        let token = try JSONDecoder().decode(Token.self, from: data)
        return token
    }

    
    
    
    func register(email: String, username: String, password: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/users/register") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "username": username,
            "email": email,
            "password": password
        ]
        
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        

        if !(200..<300).contains(httpResponse.statusCode) {

            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: apiError.detail])
            }

            else if let validationError = try? JSONDecoder().decode(APIValidationErrorResponse.self, from: data) {
                let messages = validationError.detail.map { "\($0.loc.joined(separator: ".")): \($0.msg)" }
                let combinedMessage = messages.joined(separator: "\n")
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: combinedMessage])
            }

            else if let errorString = String(data: data, encoding: .utf8) {
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorString])
            } else {
                throw URLError(.badServerResponse)
            }
        }
        
        
        let decoded = try JSONDecoder().decode(UserRegisterResponseModel.self, from: data)
        return decoded.id
    }
    
    
    func getCurrentUser(token: String) async throws -> UserResponse {
            guard let url = URL(string: "\(baseURL)/users/me") else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            return try JSONDecoder().decode(UserResponse.self, from: data)
        }
    
    // MARK: - MESSAGES
    
    func sendMessage(
            token: String,
            senderDeviceId: String,
            recipientUserId: String,
            recipientDeviceId: String,
            ciphertext: String,
            contentType: String = "text"
        ) async throws -> MessageResponse {
            guard let url = URL(string: "\(baseURL)/messages/send") else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let body: [String: Any] = [
                "sender_device_id": senderDeviceId,
                "recipient_user_id": recipientUserId,
                "recipient_device_id": recipientDeviceId,
                "ciphertext": ciphertext,
                "content_type": contentType
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                    print("HTTP status:", httpResponse.statusCode)
                }
                print("Raw response:", String(data: data, encoding: .utf8) ?? "nil")

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if !(200..<300).contains(httpResponse.statusCode) {
                let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorString])
            }

            return try JSONDecoder().decode(MessageResponse.self, from: data)
        }
    
    func inbox(token: String) async throws -> [MessageResponse] {
            guard let url = URL(string: "\(baseURL)/messages/inbox") else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            return try JSONDecoder().decode([MessageResponse].self, from: data)
        }
    
    func history(userId: String, token: String) async throws -> [MessageResponse] {
        guard let url = URL(string: "\(baseURL)/messages/history/\(userId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            print("📡 History status:", httpResponse.statusCode)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) {
            print("📦 History JSON:", json)
        } else {
            print("⚠️ History raw:", String(data: data, encoding: .utf8) ?? "nil")
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([MessageResponse].self, from: data)
    }
    
    // MARK: - Device Registration

    func registerDevice(
        deviceId: String,
        deviceName: String,
        identityKey: String,
        signedPrekey: String,
        signedPrekeySignature: String,
        oneTimePrekeys: [String],
        token: String
    ) async throws -> DeviceResponse {
        
        guard let url = URL(string: "\(baseURL)/devices/register") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "device_id": deviceId,
            "device_name": deviceName,
            "identity_key": identityKey,
            "signed_prekey": signedPrekey,
            "signed_prekey_signature": signedPrekeySignature,
            "one_time_prekeys": oneTimePrekeys
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        print("📡 Device register status:", httpResponse.statusCode)
        

        if let json = try? JSONSerialization.jsonObject(with: data) {
            print("📦 Register device response JSON:", json)
        } else if !data.isEmpty {
            print("📦 Register device raw response:", String(data: data, encoding: .utf8) ?? "nil")
        } else {
            print("⚠️ Empty response data from registerDevice")
        }
        

        if httpResponse.statusCode == 400,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = json["detail"] as? String,
           detail.contains("already registered") {
            print("ℹ️ Device already registered — continuing normally.")
            return DeviceResponse(
                id: UUID(),
                device_id: deviceId,
                device_name: deviceName,
                identity_key: identityKey,
                signed_prekey: signedPrekey,
                signed_prekey_signature: signedPrekeySignature,
                created_at: Date()
            )
        }
        

        if (200..<300).contains(httpResponse.statusCode) {
            guard !data.isEmpty else {
                return DeviceResponse(
                    id: UUID(),
                    device_id: deviceId,
                    device_name: deviceName,
                    identity_key: identityKey,
                    signed_prekey: signedPrekey,
                    signed_prekey_signature: signedPrekeySignature,
                    created_at: Date()
                )
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(DeviceResponse.self, from: data)
        }
        

        throw URLError(.badServerResponse)
    }




    // MARK: - Fetch User Devices (to get their public keys)

    func getUserDevices(userId: String, token: String) async throws -> [DeviceResponse] {
        guard let url = URL(string: "\(baseURL)/devices/user/\(userId)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        print("getUserDevices", data, response)
        
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        

        let decoder = JSONDecoder()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        decoder.dateDecodingStrategy = .formatted(formatter)
        
        let devices = try decoder.decode([DeviceResponse].self, from: data)
        print(devices)
        return devices
    }
    
    // MARK: - keys exange
    
    func exchangeKeys(recipientId: String, token: String) async throws -> [[String: Any]] {

            guard let url = URL(string: "\(baseURL)/keys/exchange/\(recipientId)") else {
                throw APIError.invalidURL
            }
            

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            

            let (data, response) = try await URLSession.shared.data(for: request)
            

            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                throw APIError.invalidResponse
            }
            

            let json = try JSONSerialization.jsonObject(with: data)
            
            guard let array = json as? [[String: Any]] else {
                throw APIError.decodingFailed
            }
            
            return array
        }
    
    func fetchFriends(token: String) async throws -> [Friend] {
            guard let url = URL(string: "\(baseURL)/users/friends") else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            print("📡 Fetch friends status:", httpResponse.statusCode)


            if let json = try? JSONSerialization.jsonObject(with: data) {
                print("📦 Friends response JSON:", json)
            } else if !data.isEmpty {
                print("📦 Friends raw response:", String(data: data, encoding: .utf8) ?? "nil")
            } else {
                print("⚠️ Empty response data from fetchFriends")
            }


            if (200..<300).contains(httpResponse.statusCode) {
                guard !data.isEmpty else {
                    return []
                }
                let decoder = JSONDecoder()
                return try decoder.decode([Friend].self, from: data)
            }


            throw URLError(.badServerResponse)
        }
    
    func fetchAllUsers() async throws -> [Friend] {
        guard let url = URL(string: "\(baseURL)/users/all") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        let token = UserDefaults.standard.string(forKey: "accessToken") ?? ""
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        print("📡 Fetch all users status:", httpResponse.statusCode)


        if let json = try? JSONSerialization.jsonObject(with: data) {
            print("📦 Users response JSON:", json)
        } else if !data.isEmpty {
            print("📦 Users raw response:", String(data: data, encoding: .utf8) ?? "nil")
        } else {
            print("⚠️ Empty response data from fetchAllUsers")
        }


        if (200..<300).contains(httpResponse.statusCode) {
            guard !data.isEmpty else {
                return []
            }
            let decoder = JSONDecoder()
            return try decoder.decode([Friend].self, from: data)
        }


        throw URLError(.badServerResponse)
    }
    
    func fetchUserByUsername(username: String) async throws -> Friend? {

        guard var urlComponents = URLComponents(string: "\(baseURL)/users/by_username") else {
            throw URLError(.badURL)
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "username", value: username)
        ]
        
        guard let url = urlComponents.url else {
            throw URLError(.badURL)
        }

        let token = UserDefaults.standard.string(forKey: "accessToken") ?? ""
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(Friend.self, from: data)
        case 404:
            return nil 
        default:
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorString])
        }
    }
    
    func fetchUserProfile(id: String) async throws -> Friend? {
        guard var urlComponents = URLComponents(string: "\(baseURL)/users/by_id") else {
            throw URLError(.badURL)
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "uid", value: id)
        ]
        
        guard let url = urlComponents.url else {
            throw URLError(.badURL)
        }

        let token = UserDefaults.standard.string(forKey: "accessToken") ?? ""
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(Friend.self, from: data)
        case 404:
            return nil
        default:
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: errorString
            ])
        }
    }



}

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case decodingFailed
}
