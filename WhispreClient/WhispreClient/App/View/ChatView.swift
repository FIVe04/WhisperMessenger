//
//  ChatView.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//

import SwiftUI

struct ChatView: View {
    @State var friend: Friend
    @State private var conversationID: String?
    @State private var newMessageText = ""
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    init(friend: Friend) {
        _friend = State(initialValue: friend)
    }
    
    var body: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 13, height: 13)
                        .padding(.trailing, 10)
                }
                
                Image("avatar")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                
                VStack(alignment: .leading) {
                    Text(friend.username)
                        .font(Font.custom("Inter", size: 15))
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                    Text(appState.realtimeStatus.title)
                        .font(Font.custom("Inter", size: 13))
                        .fontWeight(.regular)
                        .foregroundStyle(.colorTextGray)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(appState.messages(for: conversationID)) { message in
                            if message.isMine {
                                MessageSentComponent(
                                    messageText: message.text,
                                    timeText: message.createdAt
                                )
                                .id(message.id)
                            } else {
                                MessageReceivedComponent(
                                    messageText: message.text,
                                    timeText: message.createdAt
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding(.vertical, 20)
                }
                .onAppear {
                    appState.latestError = nil
                    Task {
                        do {
                            let resolved = try await appState.ensureConversation(with: friend)
                            friend = resolved
                            conversationID = resolved.conversationID
                            if let conversationID = resolved.conversationID {
                                try await appState.loadConversationHistory(conversationID: conversationID, limit: 200)
                            }
                            try await appState.refreshPendingMessages()
                        } catch {
                            appState.latestError = error.localizedDescription
                        }
                        scrollToBottom(proxy: proxy)
                    }
                }
                .onChange(of: appState.messages(for: conversationID).count) { _ in
                    withAnimation {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }

            if let error = appState.latestError, !error.isEmpty {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            
            MessageInputBarComponent(message: $newMessageText) { text in
                Task {
                    do {
                        try await appState.sendMessage(text: text, to: friend)
                        newMessageText = ""
                    } catch {
                        appState.latestError = error.localizedDescription
                    }
                }
            }
        }

        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastID = appState.messages(for: conversationID).last?.id {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}


//#Preview {
//    ChatView()
//}
