//
//  RegisterViewModel.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 22.10.2025.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class RegisterViewModel: ObservableObject {
    @Published var username: String = ""
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var repeatPassword: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isRegistered = false

    func register() async {
        isLoading = true
        errorMessage = nil
        do {
            if (password != repeatPassword) {
                errorMessage = "Passwords sould be equal!"
                isLoading = false
                return
            }
            
            if (password.count < 3) {
                errorMessage = "Password length sould be 3 or more symbols!"
                isLoading = false
                return
            }
            
            let id = try await APIService.shared.register(email: email, username: username, password: password)

            print("Register successful: \(id)")
            isRegistered = true
        } catch {
            errorMessage = "Register failed: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
