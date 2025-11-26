//
//  SettingsView.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//

import SwiftUI

struct SettingsView: View {
    
    @State var username: String = "David"
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack {
            Image("avatar")
                .resizable()
                .scaledToFit()
                .frame(width: 130, height: 130)
                .padding(.top, 10)
            HStack {
                Text(username)
                    .font(Font.custom("Inter", size: 25))
                    .fontWeight(.bold)
                    .padding(.trailing, 10)
                Image(systemName: "pencil")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            }
            .padding(.leading, 40)
            
            Button(action: {
                
            }) {
                Text("Change password")
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color.accentBlue)
                    .cornerRadius(10)
                    .foregroundColor(.white)
                    .font(Font.custom("Inter", size: 18))
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 50)
            .padding(.top, 50)
            
            Button(action: {
                print("[SettingsView] logout click")
                appState.logout()
            }) {
                Text("Logout")
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color.accentRed)
                    .cornerRadius(10)
                    .foregroundColor(.white)
                    .font(Font.custom("Inter", size: 18))
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 50)
            .padding(.top, 20)
            
            Spacer()
        }
    }
}

#Preview {
    SettingsView()
}
