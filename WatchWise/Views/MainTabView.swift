//
//  MainTabView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "chart.bar.fill" : "chart.bar")
                    Text("Dashboard")
                }
                .tag(0)
            
            MessagesView()
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "message.fill" : "message")
                    Text("Messages")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Image(systemName: selectedTab == 2 ? "gear.fill" : "gear")
                    Text("Settings")
                }
                .tag(2)
        }
        .accentColor(.blue)
        .onAppear {
            // Ensure proper tab bar styling
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthenticationManager())
}
