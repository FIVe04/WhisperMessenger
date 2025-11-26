//
//  ContentView.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//

import SwiftUI

struct ChatsView: View {
    @State var username: String = "David"
    @State var areNewNotifications: Bool = true
    @State var searchText: String = ""
    @EnvironmentObject var viewModel: FriendsViewModel

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
                        Text("\(username) 👋")
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
                        ForEach(viewModel.friends.filter { $0.username.contains(searchText) || searchText.isEmpty }) { friend in
                            NavigationLink(destination: ChatView(recipientUserID: friend.id, username: friend.username, friendsVM: viewModel))
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
        .onChange(of: viewModel.friends) { newFriends in
            print("🖌️ [ChatsView] friends changed:", newFriends)
        }
        .onAppear {
            viewModel.onAppear()
            Task {
                let myUserId = UserDefaults.standard.string(forKey: "userId") ?? ""
                do {
                    let user = try await APIService.shared.fetchUserProfile(id: myUserId)
                    username = user!.username
                } catch {
                    username = ""
                }
            }
            
        }
        .task {
            await viewModel.loadFriends()
        }
        .navigationBarBackButtonHidden(true)
    }
}


#Preview {
    ChatsView()
}
