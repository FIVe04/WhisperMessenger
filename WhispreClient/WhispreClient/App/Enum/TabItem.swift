//
//  TabItem.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 08.11.2025.
//

enum TabItem: String, CaseIterable {
    case chats
    case calls
    case compose
    case groups
    case settings
    
    var iconName: String {
        switch self {
        case .chats: return "bubble.left.and.bubble.right.fill"
        case .calls: return "phone.fill"
        case .compose: return "pencil"
        case .groups: return "person.2.fill"
        case .settings: return "gearshape.fill"
        }
    }
    
    var title: String {
        switch self {
        case .chats: return "Chats"
        case .calls: return "Calls"
        case .compose: return "New chat"
        case .groups: return "Groups"
        case .settings: return "Settings"
        }
    }
}
