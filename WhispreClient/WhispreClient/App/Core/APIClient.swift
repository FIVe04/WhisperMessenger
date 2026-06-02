import Foundation

enum APIClientError: LocalizedError {
    case invalidURL
    case transport(Error)
    case server(status: Int, message: String)
    case decoding(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case let .transport(error):
            return error.localizedDescription
        case let .server(_, message):
            return message
        case let .decoding(message):
            return "Decoding error: \(message)"
        }
    }
}

struct APIErrorPayload: Decodable {
    let detail: String?
}

final class APIClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURLString: String = "http://localhost:8000") {
        guard let url = URL(string: baseURLString) else {
            fatalError("Invalid base URL")
        }
        self.baseURL = url
        self.session = URLSession(configuration: .default)
    }

    func buildURL(path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw APIClientError.invalidURL
        }
        return url
    }

    func encodeBody<T: Encodable>(_ body: T) throws -> Data {
        try DateCodec.encoder.encode(body)
    }

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        token: String? = nil,
        headers: [String: String] = [:],
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> T {
        let url = try buildURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIClientError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.server(status: -1, message: "Invalid server response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message: String
            if let payload = try? DateCodec.decoder.decode(APIErrorPayload.self, from: data), let detail = payload.detail {
                message = detail
            } else if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                message = raw
            } else {
                message = "Server error \(httpResponse.statusCode)"
            }
            throw APIClientError.server(status: httpResponse.statusCode, message: message)
        }

        if T.self == EmptyResponseDTO.self, data.isEmpty {
            return EmptyResponseDTO() as! T
        }

        do {
            return try DateCodec.decoder.decode(T.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            let compactRaw = raw.count > 300 ? String(raw.prefix(300)) + "..." : raw
            throw APIClientError.decoding(message: "\(error.localizedDescription). Response: \(compactRaw)")
        }
    }
}
