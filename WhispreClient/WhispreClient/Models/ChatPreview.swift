//
//  ChatPreview.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 08.11.2025.
//

struct ChatPreview: Codable, Identifiable {
    let user_id: String
    let username: String
    let last_message: String
    let last_message_time: String
    let last_message_count: Int
    
    var id: String { user_id }
}
