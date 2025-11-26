//
//  ChatView.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 17.10.2025.
//

import SwiftUI

struct ChatView: View {
    
    @StateObject var vm: ChatViewModel
    
    @State var username: String
    @State var status: String = "Online now"
    @State private var newMessageText = ""
    @Environment(\.dismiss) private var dismiss
    
    
    
    init(recipientUserID: String, username: String, friendsVM: FriendsViewModel) {
        _vm = StateObject(wrappedValue: ChatViewModel(recipientUserID: recipientUserID, friendsVM: friendsVM))
        self.username = username
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
                    Text(username)
                        .font(Font.custom("Inter", size: 15))
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                    Text(status)
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
                        ForEach(Array(vm.messages.enumerated()), id: \.element.id) { index, message in
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
                    vm.onAppear()
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: vm.messages.count) { _ in
                    withAnimation {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
            
            MessageInputBarComponent(message: $newMessageText) { text in
                vm.input = text
                vm.send()
                newMessageText = ""
            }
        }

        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastID = vm.messages.last?.id {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}


//#Preview {
//    ChatView()
//}
