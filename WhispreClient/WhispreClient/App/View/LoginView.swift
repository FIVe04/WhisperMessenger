//
//  LoginView.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//

import SwiftUI

struct CustomTextFieldStyle: TextFieldStyle {
    var height: CGFloat = 50
    var cornerRadius: CGFloat = 12
    var backgroundColor: Color = Color(.systemGray6)
    var paddingH: CGFloat = 24

    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            
            .frame(height: height)
            .background(.white)
            .cornerRadius(cornerRadius)
            .padding(.horizontal, 14)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
            )
            .padding(.horizontal, paddingH)
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Rectangle()
                .fill(configuration.isOn ? Color.blue : Color.clear)
                .frame(width: 16, height: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray, lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .opacity(configuration.isOn ? 1 : 0)
                )
                .onTapGesture {
                    configuration.isOn.toggle()
                }
            configuration.label
        }
    }
}

struct LoginView: View {
    @State private var email: String = ""
    @State private var password: String = ""
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
                    Image("IconInApp")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50)
                        .padding(.top, 0)
                    
                    Text("Sign in to your \nAccount")
                        .font(Font.custom("Inter", size: 32))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 17)
                    
                    Text("Enter your email and password to log in")
                        .font(Font.custom("Inter", size: 12))
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                    
                    VStack {
                        TextField("Email", text: $email)
                            .textFieldStyle(CustomTextFieldStyle(height: 46))
                            .padding(.top, 50)
                            .textInputAutocapitalization(.never)
                        SecureField("Password", text: $password)
                            .textFieldStyle(CustomTextFieldStyle(height: 46))
                            .padding(.top, 10)
                            .textInputAutocapitalization(.never)
                        
                        HStack {
                            Toggle(isOn: $isOn) {
                                Text("Remember me")
                                    .font(Font.custom("Inter", size: 12))
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                    .foregroundStyle(.colorTextGray)
                            }
                            .toggleStyle(CheckboxToggleStyle())
                            Spacer()
                            Text("Forgot Password?")
                                .font(Font.custom("Inter", size: 12))
                                .fontWeight(.medium)
                                .foregroundStyle(.accentBlue)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        
                        Button(action: {
                            errorMessage = nil
                            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                            let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

                            guard !trimmedEmail.isEmpty, !trimmedPassword.isEmpty else {
                                errorMessage = "Please fill in email and password"
                                return
                            }

                            Task {
                                isLoading = true
                                do {
                                    try await appState.login(email: trimmedEmail, password: trimmedPassword)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                                isLoading = false
                            }
                        }) {
                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                Text("Log In")
                                    .foregroundColor(.white)
                                    .font(Font.custom("Inter", size: 14))
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .frame(height: 46)
                        .background(Color.accentBlue)
                        .cornerRadius(12)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        
                        if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.top, 8)
                        }
                        
                        HStack {
                            Text("Don't have an account?")
                                .foregroundColor(.colorTextGray)
                                .font(Font.custom("Inter", size: 12))
                                .fontWeight(.medium)
                            NavigationLink(destination: RegisterView()) {
                                Text("Sign Up")
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
    LoginView()
        .environmentObject(AppState())
}
