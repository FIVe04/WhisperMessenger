//
//  MainTabView.swift
//  WhispreClient
//
//  Created by Ivan Frolov on 08.11.2025.
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: TabItem = .chats
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatsView()
                .tabItem {
                    Image(systemName: TabItem.chats.iconName)
                    Text(TabItem.chats.title)
                }
                .tag(TabItem.chats)
            
            
            VStack{
                Text("Calls")
            }
            .tabItem {
                Image(systemName: TabItem.calls.iconName)
                Text(TabItem.calls.title)
            }
            .tag(TabItem.calls)
            
            NewChatView()
            .tabItem {
                Image(systemName: TabItem.compose.iconName)
                Text(TabItem.compose.title)
            }
            .tag(TabItem.compose)
            
            VStack{
                Text("Groups")
            }
            .tabItem {
                Image(systemName: TabItem.groups.iconName)
                Text(TabItem.groups.title)
            }
            .tag(TabItem.groups)

            

            SettingsView()
                .tabItem {
                    Image(systemName: TabItem.settings.iconName)
                    Text(TabItem.settings.title)
                }
                .tag(TabItem.settings)
                .environmentObject(appState) 
        }
        .accentColor(.accentBlue)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
