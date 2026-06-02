//
//  RegisterView.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//

import SwiftUI


struct RegisterView: View {
    @State private var username: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var repeatPassword: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State var isOn: Bool = false
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationStack {
            
            ZStack {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.accentBlue)
                        .frame(width: geometry.size.width, height: geometry.size.height / 2)
                        .ignoresSafeArea(edges: .top)
                }
                ScrollView {
                    
                }
                ScrollView {
                    Image("IconInApp")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50)
                        .padding(.top, 0)
                    
                    Text("Sign Up")
                        .font(Font.custom("Inter", size: 32))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 17)
                    
                    Text("Enter a username, email and password\nto sign up")
                        .font(Font.custom("Inter", size: 12))
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                    
                    VStack {
                        TextField("Username", text: $username)
                            .textFieldStyle(CustomTextFieldStyle(height: 46))
                            .padding(.top, 50)
                            .textInputAutocapitalization(.never)
                        TextField("Email", text: $email)
                            .textFieldStyle(CustomTextFieldStyle(height: 46))
                            .padding(.top,  10)
                            .textInputAutocapitalization(.never)
                        SecureField("Password", text: $password)
                            .textFieldStyle(CustomTextFieldStyle(height: 46))
                            .padding(.top, 10)
                            .textInputAutocapitalization(.never)
                        SecureField("Repeat password", text: $repeatPassword)
                            .textFieldStyle(CustomTextFieldStyle(height: 46))
                            .padding(.top, 10)
                            .textInputAutocapitalization(.never)
                        
                        
                        Button(action: {
                            errorMessage = nil
                            let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
                            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                            let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

                            guard !trimmedUsername.isEmpty, !trimmedEmail.isEmpty, !trimmedPassword.isEmpty else {
                                errorMessage = "Please fill in all fields"
                                return
                            }
                            guard password == repeatPassword else {
                                errorMessage = "Passwords do not match"
                                return
                            }

                            Task {
                                isLoading = true
                                do {
                                    try await appState.register(
                                        username: trimmedUsername,
                                        email: trimmedEmail,
                                        password: trimmedPassword
                                    )
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                                isLoading = false
                            }
                        }) {
                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.accentBlue)
                                    .cornerRadius(12)
                            } else {
                                Text("Register ")
                                    .foregroundColor(.white)
                                    .font(Font.custom("Inter", size: 14))
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.accentBlue)
                                    .cornerRadius(12)
                            }
                        }
                        .frame(height: 46)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.top, 8)
                        }
                        
                        HStack {
                            Text("Already have an account?")
                                .foregroundColor(.colorTextGray)
                                .font(Font.custom("Inter", size: 12))
                                .fontWeight(.medium)
                            NavigationLink(destination: LoginView()) {
                                Text("Sign In")
                                    .foregroundColor(.accentBlue)
                                    .font(Font.custom("Inter", size: 12))
                                    .fontWeight(.semibold)
                            }
                            
                        }
                        .padding(.horizontal, 24)
                        
                        .padding(.top, 24)
                        .padding(.bottom, 80)
                    }
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white)
                    )
                    .padding(.top, 20)
                    .padding(.leading, 33)
                    .padding(.trailing, 33)
                    Spacer()
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                
                
            }
            .background(.colorGrayBG)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .navigationBarBackButtonHidden(true)
    }
    
}

#Preview {
    RegisterView()
        .environmentObject(AppState())
}
