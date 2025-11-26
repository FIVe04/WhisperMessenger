//
//  WebSockerService.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//


import Foundation

protocol WebSocketServiceDelegate: AnyObject {
    func didReceiveMessage(_ message: ChatMessage)
    func didUpdateMessageStatus(messageID: String, status: String)
    func didDisconnect()
}

final class WebSocketService: NSObject, URLSessionDelegate {
    static let shared = WebSocketService()
    private override init() {}
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    weak var delegate: WebSocketServiceDelegate?
    
    private var delegates = NSHashTable<AnyObject>.weakObjects()
    
    private let baseURL = "ws://127.0.0.1:8000/ws/messages"
    private var token: String?
    private var isConnected = false
    
    func addDelegate(_ delegate: WebSocketServiceDelegate) {
        delegates.add(delegate)
    }

    func removeDelegate(_ delegate: WebSocketServiceDelegate) {
        delegates.remove(delegate)
    }
    
    // MARK: - Connect
    
    func connect(with token: String) {
        guard !isConnected else { return }
        self.token = token
        
        guard let url = URL(string: "\(baseURL)?token=\(token)") else {
            print("❌ Invalid WS URL")
            return
        }
        
        let sessionConfig = URLSessionConfiguration.default
        session = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: .main)
        
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()
        
        listen() // start listening immediately
        isConnected = true
        
        print("✅ WebSocket connected")
    }
    
    // MARK: - Disconnect
    
    func disconnect() {
        guard isConnected else { return }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session = nil
        isConnected = false
        delegate?.didDisconnect()
        print("🔌 WebSocket disconnected")
    }
    
    // MARK: - Listen
    
    private func listen() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                print("❌ WS receive error:", error)
                self.isConnected = false
                self.delegate?.didDisconnect()
                
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleIncomingMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncomingMessage(text)
                    }
                @unknown default:
                    print("⚠️ Unknown WS message type")
                }
                
                // continue listening
                self.listen()
            }
        }
    }
    
    // MARK: - Send Message
    
    func sendMessage(
        recipientUserID: String,
        recipientDeviceID: String,
        senderDeviceID: String,
        ciphertext: String,
        contentType: String = "text"
    ) async {
        let payload: [String: Any] = [
            "action": "send_message",
            "recipient_user_id": recipientUserID,
            "recipient_device_id": recipientDeviceID,
            "sender_device_id": senderDeviceID,
            "ciphertext": ciphertext,
            "content_type": contentType
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let message = URLSessionWebSocketTask.Message.string(jsonString)  // 👈 изменено
                try await webSocketTask?.send(message)
                print("📤 WS sent message to \(recipientUserID): \(jsonString)")
            } else {
                print("❌ Failed to encode payload to string")
            }
        } catch {
            print("❌ WS send failed:", error)
        }
    }

    
    // MARK: - Handle Incoming
    
    private func handleIncomingMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let action = json?["action"] as? String else { return }
            
            switch action {
            case "new_message":
                if let messageData = json?["message"] as? [String: Any],
                   let id = messageData["id"] as? String,
                   let senderId = messageData["sender_user_id"] as? String,
                   let ciphertext = messageData["ciphertext"] as? String,
                   let createdAt = messageData["created_at"] as? String {
                    
                    let chatMessage = ChatMessage(
                        id: id,
                        senderUserID: senderId,
                        recipientUserID: messageData["recipient_user_id"] as? String ?? "",
                        senderDeviceID: messageData["sender_device_id"] as? String,    // опционально
                        recipientDeviceID: messageData["recipient_device_id"] as? String,
                        ciphertext: ciphertext,
                        contentType: messageData["content_type"] as? String ?? "text",
                        createdAt: createdAt
                    )

                    
                    for case let delegate as WebSocketServiceDelegate in delegates.allObjects {
                        delegate.didReceiveMessage(chatMessage)
                    }
                }
                
            case "status_update":
                if let messageId = json?["message_id"] as? String,
                   let status = json?["status"] as? String {
                    for case let delegate as WebSocketServiceDelegate in delegates.allObjects {
                        delegate.didUpdateMessageStatus(messageID: messageId, status: status)
                    }
                }
                
            default:
                print("ℹ️ Unknown WS action: \(action)")
            }
        } catch {
            print("❌ WS message parse error:", error)
        }
    }

    
}
