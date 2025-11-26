//
//  WhispreClientApp.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//

import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var isRegistered: Bool = false
    
    func logout() {
        SessionManager.shared.resetAll()
        
        guard let uid = UserDefaults.standard.string(forKey: "userId") else { return }
//        KeyManager.shared.deleteAllKeys(for: uid)
        

        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "accessToken")
        UserDefaults.standard.removeObject(forKey: "refreshToken")
        
        WebSocketService.shared.disconnect()
    
        SessionManager.shared.logoutCurrentUser()
    
        isLoggedIn = false
        isRegistered = true
    }
    
}

@main
struct WhispreClientApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var friendsVM = FriendsViewModel()

    var body: some Scene {
        WindowGroup {
            if appState.isLoggedIn {
                MainTabView()
                    .environmentObject(friendsVM)
                    .environmentObject(appState) 
            }
            else if appState.isRegistered {
                LoginView()
                    .environmentObject(appState)
            }
            else {
                RegisterView()
                    .environmentObject(appState)
            }
        }
    }
}
