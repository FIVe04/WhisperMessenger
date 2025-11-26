//
//  Message.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//

import Foundation


struct MessageResponse: Codable {
    let id: String
    let sender_user_id: String
    let sender_device_id: String
    let recipient_user_id: String
    let recipient_device_id: String
    let ciphertext: String
    let content_type: String
    let status: String
    let created_at: String
}



struct ChatMessage: Identifiable, Codable {
    let id: String
    let senderUserID: String
    let recipientUserID: String
    let senderDeviceID: String?
    let recipientDeviceID: String?   
    let ciphertext: String
    let contentType: String
    let createdAt: String
}
