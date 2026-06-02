import Foundation

final class WebSocketManager {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
    }

    var onEvent: ((RealtimeEventDTO) -> Void)?
    var onError: ((String) -> Void)?
    var onStateChange: ((ConnectionState) -> Void)?

    private let baseURLString: String
    private let urlSession: URLSession

    private var socketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var staleWatchTask: Task<Void, Never>?

    private var currentToken: String?
    private var currentDeviceID: String?
    private var shouldReconnect = false
    private var reconnectAttempt = 0
    private var hasSeenMessageOnCurrentConnection = false
    private var lastActivityAt = Date()
    private var connectionState: ConnectionState = .disconnected {
        didSet {
            if oldValue != connectionState {
                onStateChange?(connectionState)
            }
        }
    }

    private let pingIntervalNanoseconds: UInt64 = 20_000_000_000
    private let staleTimeoutNanoseconds: UInt64 = 45_000_000_000

    init(baseURLString: String = "http://localhost:8006") {
        self.baseURLString = baseURLString
        self.urlSession = URLSession(configuration: .default)
    }

    func connect(accessToken: String, deviceID: String) {
        currentToken = accessToken
        currentDeviceID = deviceID
        shouldReconnect = true
        reconnectAttempt = 0
        openSocket()
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        pingTask?.cancel()
        staleWatchTask?.cancel()
        receiveTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        connectionState = .disconnected
    }

    private func openSocket() {
        guard let token = currentToken, let deviceID = currentDeviceID else { return }

        connectionState = reconnectAttempt == 0 ? .connecting : .reconnecting
        reconnectTask?.cancel()
        pingTask?.cancel()
        staleWatchTask?.cancel()
        receiveTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)

        guard let url = URL(string: "\(baseURLString)/v1/realtime/ws?device_id=\(deviceID)") else {
            onError?("Invalid WebSocket URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let task = urlSession.webSocketTask(with: request)
        socketTask = task
        task.resume()
        connectionState = .connected
        hasSeenMessageOnCurrentConnection = false
        lastActivityAt = Date()
        startPingLoop()
        startStaleWatchdog()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        guard let task = socketTask else { return }

        while shouldReconnect, !Task.isCancelled {
            do {
                let message = try await task.receive()
                if !hasSeenMessageOnCurrentConnection {
                    hasSeenMessageOnCurrentConnection = true
                    reconnectAttempt = 0
                    connectionState = .connected
                }
                lastActivityAt = Date()
                switch message {
                case let .string(text):
                    parseEvent(raw: text)
                case let .data(data):
                    if let text = String(data: data, encoding: .utf8) {
                        parseEvent(raw: text)
                    }
                @unknown default:
                    break
                }
            } catch {
                onError?("WebSocket receive error: \(error.localizedDescription)")
                scheduleReconnect()
                return
            }
        }
    }

    private func parseEvent(raw: String) {
        guard let data = raw.data(using: .utf8) else { return }
        guard let event = try? DateCodec.decoder.decode(RealtimeEventDTO.self, from: data) else { return }
        onEvent?(event)
    }

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            guard let self else { return }
            while self.shouldReconnect, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.pingIntervalNanoseconds)
                guard self.shouldReconnect, !Task.isCancelled else { return }
                guard let task = self.socketTask else {
                    self.scheduleReconnect()
                    return
                }
                do {
                    try await self.sendPing(task: task)
                    self.lastActivityAt = Date()
                } catch {
                    self.onError?("WebSocket ping error: \(error.localizedDescription)")
                    self.scheduleReconnect()
                    return
                }
            }
        }
    }

    private func startStaleWatchdog() {
        staleWatchTask?.cancel()
        staleWatchTask = Task { [weak self] in
            guard let self else { return }
            while self.shouldReconnect, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard self.shouldReconnect, !Task.isCancelled else { return }
                let inactiveFor = Date().timeIntervalSince(self.lastActivityAt)
                if inactiveFor >= Double(self.staleTimeoutNanoseconds) / 1_000_000_000 {
                    self.onError?("WebSocket stale connection detected")
                    self.scheduleReconnect()
                    return
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        connectionState = .reconnecting
        reconnectTask?.cancel()
        pingTask?.cancel()
        staleWatchTask?.cancel()
        receiveTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil

        let attempt = reconnectAttempt + 1
        reconnectAttempt = attempt
        let baseDelay = min(pow(2.0, Double(max(0, attempt - 1))), 30.0)
        let jitter = Double.random(in: 0...0.6)
        let delaySeconds = baseDelay + jitter
        let delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self, self.shouldReconnect else { return }
            self.openSocket()
        }
    }

    private func sendPing(task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
