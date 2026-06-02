//
//  NewChatView.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 10.11.2025.
//

import SwiftUI

struct NewChatView: View {
    
    @State var searchText: String = ""
    @State var foundUser: Friend? = nil
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationStack {
            
            VStack {
                HStack(alignment: .center) {
                    HStack {
                        TextField("Search", text: $searchText)
                            .foregroundColor(.black)
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .background(Color("ColorGraySearchBG"))
                    .cornerRadius(46)
                    .padding(.trailing, 10)
                    .padding(.top, 10)
                    
                    Button(action: {
                        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !query.isEmpty else {
                            foundUser = nil
                            return
                        }
                        Task {
                            do {
                                foundUser = try await appState.searchUser(username: query)
                            } catch {
                                appState.latestError = error.localizedDescription
                                foundUser = nil
                            }
                        }
                            
                    }, label: {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 42, height: 42)
                            .foregroundStyle(.accentBlue)
                            .padding(.top, 6)
                    })
                    
                }
                .padding(.horizontal, 20)

                
                if let foundUser {
                    NavigationLink(destination: ChatView(friend: foundUser)) {
                        HStack(spacing: 10) {
                            Image("avatar")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 54, height: 54)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 5) {
                                Text(foundUser.username)
                                    .font(Font.custom("Inter", size: 20))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.black)
                                    .multilineTextAlignment(.center)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                    }

                } else {
                    Text("No user found")
                        .font(Font.custom("Inter", size: 20))
                        .fontWeight(.semibold)
                        .foregroundStyle(.colorTextGray)
                        .padding(.top, 20)
                }
                

                
                
                
                
                Spacer()
            }
            
        }
    }
}

#Preview {
    NewChatView()
        .environmentObject(AppState())
}
