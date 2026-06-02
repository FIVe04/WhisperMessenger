//
//  WhispreClientApp.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//

import SwiftUI

@main
struct WhispreClientApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.isLoggedIn {
                MainTabView()
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
