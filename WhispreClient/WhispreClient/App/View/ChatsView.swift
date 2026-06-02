//
//  ContentView.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//

import SwiftUI

struct ChatsView: View {
    @State var areNewNotifications: Bool = true
    @State var searchText: String = ""
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Image("avatar")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())

                    HStack(spacing: 5) {
                        Text("Hello")
                            .font(Font.custom("Inter", size: 16))
                            .fontWeight(.medium)
                        Text("\(appState.currentUsername) 👋")
                            .font(Font.custom("Inter", size: 16))
                            .fontWeight(.bold)
                    }

                    Spacer()

                    Image(areNewNotifications ? "notifications" : "noNotifications")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 24, height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                HStack {
                    Text("Realtime: \(appState.realtimeStatus.title)")
                        .font(Font.custom("Inter", size: 12))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)


                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search", text: $searchText)
                        .foregroundColor(.black)
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(Color("ColorGraySearchBG"))
                .cornerRadius(46)
                .padding(.horizontal, 20)
                .padding(.top, 10)


                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(appState.chats.filter { $0.username.localizedCaseInsensitiveContains(searchText) || searchText.isEmpty }) { friend in
                            NavigationLink(destination: ChatView(friend: friend))
                                {
                                ChatPreviewComponent(
                                    username: friend.username,
                                    last_message: friend.lastMessage,
                                    last_message_time: friend.lastMessageTime,
                                    last_message_count: 0
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .onAppear {
            Task {
                do {
                    try await appState.refreshChats()
                    try await appState.refreshPendingMessages()
                } catch {
                    appState.latestError = error.localizedDescription
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}


#Preview {
    ChatsView()
        .environmentObject(AppState())
}
