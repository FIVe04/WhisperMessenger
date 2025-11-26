//
//  ChatViewModel.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 09.11.2025.

// ChatViewModel.swift
import Foundation
import Combine
import CryptoKit

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [MessageRow] = []
    
    private weak var friendsVM: FriendsViewModel?
    
    @Published var input: String = ""
    let recipientUserID: String
    private var recipientDeviceID: String?
    private let token: String
    private let myDeviceIdKey = "com.whispre.deviceId"

    struct MessageRow: Identifiable, Equatable {
        let id: String
        let text: String
        let isMine: Bool
        let createdAt: String
    }

    init(recipientUserID: String, friendsVM: FriendsViewModel) {
        self.friendsVM = friendsVM
        self.recipientUserID = recipientUserID
        self.token = UserDefaults.standard.string(forKey: "accessToken") ?? ""
        WebSocketService.shared.delegate = self
    }

    func onAppear() {
        WebSocketService.shared.addDelegate(self)
        Task { await bootstrapIfNeeded() }
        Task { await loadHistory() }
    }

    func onDisappear() {
        WebSocketService.shared.removeDelegate(self)
    }

    private func bootstrapIfNeeded() async {
        do {
            // 1️⃣ Сессия устройства (у тебя уже есть)
            let deviceId = try await SessionBootstrapper.ensureSession(recipientUserID: recipientUserID, token: token)
            self.recipientDeviceID = deviceId

            // 2️⃣ Получаем ключи собеседника
            let keyBundles = try await APIService.shared.exchangeKeys(recipientId: recipientUserID, token: token)

            // 3️⃣ Для каждого устройства создаём сессию
            for bundle in keyBundles {
                guard let identityKey = bundle["identity_key"] as? String else { continue }
                // попробуем достать device_id из bundle (если сервер возвращает)
                let bundleDeviceId = bundle["device_id"] as? String ?? recipientUserID // fallback (legacy)
                // создаём сессию, сохраняем под device_id (bundleDeviceId)
                try SessionManager.shared.createSession(
                    withRecipientPublicKeyBase64: identityKey,
                    recipientId: bundleDeviceId
                )
            }


        } catch {
            print("❌ bootstrapIfNeeded failed:", error.localizedDescription)
        }
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""

        Task {
            do {
                // убедимся, что есть recipientDeviceID
                if recipientDeviceID == nil {
                    recipientDeviceID = try await SessionBootstrapper.ensureSession(recipientUserID: recipientUserID, token: token)
                }
                guard let rDeviceId = recipientDeviceID else { return }

                // шифрование
                let cipher = try EncryptionService.shared.encryptMessage(text, recipientId: rDeviceId)


                // мои данные
                let myDeviceId = UserDefaults.standard.string(forKey: myDeviceIdKey) ?? "unknown-device"

                // отправка (через REST; можешь вместо этого вызвать WebSocketService.shared.sendMessage)
//                let resp = try await APIService.shared.sendMessage(
//                    token: token,
//                    senderDeviceId: myDeviceId,
//                    recipientUserId: recipientUserID,
//                    recipientDeviceId: rDeviceId,
//                    ciphertext: cipher,
//                    contentType: "text"
//                )
//
//                // локально отобразим
//                messages.append(
//                    .init(id: resp.id, text: text, isMine: true, createdAt: resp.created_at)
//                )

                // параллельно скажем WS (если хочешь именно WS-отправку — раскомментируй)
                
                let tempId = UUID().uuidString
                messages.append(
                    .init(id: tempId, text: text, isMine: true, createdAt: ISO8601DateFormatter().string(from: Date()))
                )
    
                await WebSocketService.shared.sendMessage(
                    recipientUserID: recipientUserID,
                    recipientDeviceID: rDeviceId,
                    senderDeviceID: myDeviceId,
                    ciphertext: cipher,
                    contentType: "text"
                )
                
                Task {
                        await friendsVM?.loadFriends()
                    }
                

            } catch {
                print("❌ send failed:", error.localizedDescription)
            }
        }
    }
    
    enum EncryptionError: Error {
        case noSessionKey
        case invalidCiphertext
        case encryptionFailed
        case decryptionFailed
    }
    

    @MainActor
    private func loadHistory() async {
        do {
            let all = try await APIService.shared.history(userId: recipientUserID, token: token)
            let myUserId = UserDefaults.standard.string(forKey: "userId") ?? ""


            let filtered = all.filter {
                ($0.sender_user_id == myUserId && $0.recipient_user_id == recipientUserID) ||
                ($0.sender_user_id == recipientUserID && $0.recipient_user_id == myUserId)
            }

            var rows: [MessageRow] = []

            for m in filtered {
                let isMine = (m.sender_user_id == myUserId)
                let senderDeviceId = m.sender_device_id
                let recipientDeviceId = m.recipient_device_id


                if isMine {

                    if !SessionManager.shared.hasSession(for: recipientDeviceId) {
                        do {
                            let devices = try await APIService.shared.getUserDevices(userId: m.recipient_user_id, token: token)
                            if let device = devices.first(where: { $0.device_id == recipientDeviceId }) {
                                try SessionManager.shared.createSession(
                                    withRecipientPublicKeyBase64: device.identity_key,
                                    recipientId: recipientDeviceId
                                )
                                print("✅ Created session for my message recipientDeviceId: \(recipientDeviceId)")
                            } else if let firstDevice = devices.first {
                                // fallback на первый девайс
                                try SessionManager.shared.createSession(
                                    withRecipientPublicKeyBase64: firstDevice.identity_key,
                                    recipientId: firstDevice.device_id
                                )
                                print("⚠️ Fallback: Created session for device: \(firstDevice.device_id)")
                            }
                        } catch {
                            print("❌ Failed to create session for recipient device \(recipientDeviceId):", error.localizedDescription)
                        }
                    }
                } else {

                    if !SessionManager.shared.hasSession(for: senderDeviceId) {
                        do {
                            let keyBundles = try await APIService.shared.exchangeKeys(recipientId: m.sender_user_id, token: token)
                            for bundle in keyBundles {
                                if let identityKey = bundle["identity_key"] as? String {
                                    let bundleDeviceId = bundle["device_id"] as? String ?? m.sender_user_id
                                    try SessionManager.shared.createSession(
                                        withRecipientPublicKeyBase64: identityKey,
                                        recipientId: bundleDeviceId
                                    )
                                    print("✅ Created session for sender device \(bundleDeviceId)")
                                }
                            }
                        } catch {
                            print("❌ Failed to create session for sender device \(senderDeviceId):", error.localizedDescription)
                        }
                    }
                }


                let decryptId = isMine ? recipientDeviceId : senderDeviceId
                let plain = await EncryptionService.shared.decryptMessageWithAutoSession(
                    m.ciphertext,
                    senderId: decryptId,
                    senderUserId: isMine ? m.recipient_user_id : m.sender_user_id,
                    token: token
                )

                rows.append(.init(id: m.id, text: plain, isMine: isMine, createdAt: m.created_at))
            }


            self.messages = rows.sorted(by: { $0.createdAt < $1.createdAt })

        } catch {
            print("❌ loadHistory failed:", error.localizedDescription)
        }
    }








}

extension ChatViewModel: WebSocketServiceDelegate {
    func didReceiveMessage(_ message: ChatMessage) {
        // предпочитаем device id, если он есть
        let decryptId = message.senderDeviceID ?? message.senderUserID

        Task {
            do {
                let plain = try EncryptionService.shared.decryptMessage(message.ciphertext, senderId: decryptId)
                let row = MessageRow(id: message.id, text: plain, isMine: false, createdAt: message.createdAt)
                messages.append(row)
            } catch {
                // если нет сессии — попробуем создать её по senderDeviceID (если есть) и повторить
                print("❌ decrypt incoming failed:", error.localizedDescription)

                // Проверка на конкретную ошибку: noSessionKey
                if case EncryptionService.EncryptionError.noSessionKey = error {
                    if let senderDevice = message.senderDeviceID {
                        do {
                            // попытка создать сессию именно для senderDevice
                            try await SessionBootstrapper.ensureSession(forDeviceId: senderDevice, userId: message.senderUserID, token: token)
                            // повторная попытка дешифровки
                            let plain = try EncryptionService.shared.decryptMessage(message.ciphertext, senderId: senderDevice)
                            let row = MessageRow(id: message.id, text: plain, isMine: false, createdAt: message.createdAt)
                            messages.append(row)
                            return
                        } catch {
                            print("❌ failed to bootstrap session for senderDevice \(senderDevice):", error.localizedDescription)
                        }
                    } else {
                        // если нет senderDeviceID, можно попробовать bootstrap по userId (legacy)
                        do {
                            _ = try await SessionBootstrapper.ensureSession(recipientUserID: message.senderUserID, token: token)
                            let plain = try EncryptionService.shared.decryptMessage(message.ciphertext, senderId: message.senderUserID)
                            let row = MessageRow(id: message.id, text: plain, isMine: false, createdAt: message.createdAt)
                            messages.insert(row, at: 0)
                            return
                        } catch {
                            print("❌ fallback bootstrap by user failed:", error.localizedDescription)
                        }
                    }
                }
                // если всё не удалось — оставляем замочек (или можно вставить метку)
                let row = MessageRow(id: message.id, text: "🔒", isMine: false, createdAt: message.createdAt)
                messages.append(row)
            }
        }
    }



    func didUpdateMessageStatus(messageID: String, status: String) {
        // при желании — помечай «доставлено/прочитано»
        // здесь для краткости ничего не делаем
    }

    func didDisconnect() {
        // можно попытаться переподключиться или показать баннер
        print("ℹ️ WS disconnected")
    }
}
