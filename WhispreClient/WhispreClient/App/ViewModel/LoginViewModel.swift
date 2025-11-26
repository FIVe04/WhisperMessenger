//
//  LoginViewModel.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 22.10.2025.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class LoginViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isLoggedIn = false
    
    func resetCryptoState() {
        SessionManager.shared.removeAllSessions()
    }

    func login() async {
        isLoading = true
        errorMessage = nil
        do {
            resetCryptoState()
            let token = try await APIService.shared.login(email: email, password: password)

            UserDefaults.standard.set(token.access_token, forKey: "accessToken")
            print("SET NEW TOKEN", token.access_token)
            UserDefaults.standard.set(token.refresh_token, forKey: "refreshToken")

            print("Login successful: \(token.access_token)")
            
            let user = try await APIService.shared.getCurrentUser(token: token.access_token)
            UserDefaults.standard.set(user.id, forKey: "userId")
            print("Current user id:", user.id)
            let userId = user.id

            if KeyManager.shared.loadIdentityKey(for: userId) == nil {
                _ = KeyManager.shared.generateIdentityKey(for: userId)
                _ = KeyManager.shared.generateSignedPreKey(for: userId)
            }
            
            SessionManager.shared.loginUser(userId: user.id)
            
            isLoggedIn = true

        } catch {
            errorMessage = "Login failed: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
