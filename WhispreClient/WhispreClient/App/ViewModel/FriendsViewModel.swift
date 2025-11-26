//
//  FriendsViewModel.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 10.11.2025.
//
import Foundation
import Combine

import Foundation

@MainActor
final class FriendsViewModel: ObservableObject {
    @Published var friends: [FriendPreview] = []
    
    init() {
        print("🔥 FriendsViewModel init")
    }
    
    func onAppear() {
        WebSocketService.shared.addDelegate(self)
    }

    struct FriendPreview: Identifiable, Equatable {
        let id: String
        let username: String
        let lastMessage: String
        let lastMessageTime: String
    }

//    private let token = UserDefaults.standard.string(forKey: "accessToken") ?? ""
//    private let myUserId = UserDefaults.standard.string(forKey: "userId") ?? ""
    
    
    func refreshFriends() {
        var newFriends: [FriendPreview] = []
        for friend in friends {
            newFriends.append(friend)
        }
        friends = newFriends
    }
    
    @MainActor
    func updateFriendPreview(_ updated: FriendPreview) {
        if let index = friends.firstIndex(where: { $0.id == updated.id }) {
            var newFriends = friends
            newFriends[index] = updated
            friends = newFriends
        } else {
            friends.insert(updated, at: 0)
        }
    }

    func loadFriends() async {
        self.friends.removeAll()
        do {
            print("📡 Fetching friends...")
            let tkn = UserDefaults.standard.string(forKey: "accessToken") ?? ""
            let friendsList = try await APIService.shared.fetchFriends(token: tkn)
            var previews: [FriendPreview] = []

            for friend in friendsList {

                let history = try await APIService.shared.history(userId: friend.id, token: tkn)

                guard let last = history.last else {
                    previews.append(.init(id: friend.id, username: friend.username, lastMessage: "", lastMessageTime: ""))
                    continue
                }
                let myUserId = UserDefaults.standard.string(forKey: "userId") ?? ""
                let isMine = (last.sender_user_id == myUserId)
                let senderDeviceId = last.sender_device_id
                let recipientDeviceId = last.recipient_device_id

                
                let decryptId = isMine ? recipientDeviceId : senderDeviceId
                let decryptUserId = isMine ? last.recipient_user_id : last.sender_user_id


                let plain = await EncryptionService.shared.decryptMessageWithAutoSession(
                    last.ciphertext,
                    senderId: decryptId,
                    senderUserId: decryptUserId,
                    token: tkn
                )


                let time = String(last.created_at.prefix(16)).replacingOccurrences(of: "T", with: " ")

                previews.append(.init(
                    id: friend.id,
                    username: friend.username,
                    lastMessage: plain,
                    lastMessageTime: time
                ))
            }


            await MainActor.run {
                self.friends = previews
            }

            print("✅ Loaded friends with previews")

        } catch {
            print("❌ loadFriends failed:", error.localizedDescription)
        }
    }
    
    
}


extension FriendsViewModel: WebSocketServiceDelegate {
    func didReceiveMessage(_ message: ChatMessage) {
            let senderUserId = message.senderUserID
            let senderDeviceId = message.senderDeviceID ?? senderUserId
            let createdAt = message.createdAt

            print("📩 [FriendsViewModel] didReceiveMessage from \(senderDeviceId)")
            let tkn = UserDefaults.standard.string(forKey: "accessToken") ?? ""
            Task { @MainActor in

                print("📩 [FriendsViewModel] try decrypt via auto-session")

                let plain = await EncryptionService.shared.decryptMessageWithAutoSession(
                    message.ciphertext,
                    senderId: senderDeviceId,
                    senderUserId: senderUserId,
                    token: tkn
                )

                print("📩 [FriendsViewModel] decrypted text = \(plain)")


                var username = friends.first(where: { $0.id == senderUserId })?.username


                if username == nil {
                    do {
                        let user = try await APIService.shared.fetchUserProfile(id: senderUserId)
                        username = user?.username
                        print("🆕 [FriendsViewModel] Loaded username for new friend:", username ?? "?")
                    } catch {
                        print("⚠️ [FriendsViewModel] Failed to load username for \(senderUserId):", error.localizedDescription)
                        username = senderUserId
                    }
                }


                let preview = FriendPreview(
                    id: senderUserId,
                    username: username ?? senderUserId,
                    lastMessage: plain,
                    lastMessageTime: createdAt
                )

                updateFriendPreview(preview)
                print("📩 [FriendsViewModel] updated/inserted \(plain) for \(senderUserId)")


                friends.sort(by: { $0.lastMessageTime > $1.lastMessageTime })
                print("📩 [FriendsViewModel] current friends:", friends)
            }
        }

    func didUpdateMessageStatus(messageID: String, status: String) { }

    func didDisconnect() { }
    
    // MARK: - Вспомогательный форматтер
//    func formatDate(_ isoString: String) -> String {
//        let outputFormatter = DateFormatter()
//        outputFormatter.dateFormat = "HH:mm"
//        
//        let isoFormatterWithFrac = ISO8601DateFormatter()
//        isoFormatterWithFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
//        if let date = isoFormatterWithFrac.date(from: isoString) {
//            return outputFormatter.string(from: date)
//        }
//        
//        let isoFormatterNoFrac = ISO8601DateFormatter()
//        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]
//        if let date = isoFormatterNoFrac.date(from: isoString) {
//            return outputFormatter.string(from: date)
//        }
//        
//        let altFormatter = DateFormatter()
//        altFormatter.locale = Locale(identifier: "en_US_POSIX")
//        altFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSXXXXX"
//        if let date = altFormatter.date(from: isoString) {
//            return outputFormatter.string(from: date)
//        }
//        
//        return ""
//    }
}



