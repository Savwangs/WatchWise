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
            
            DeviceManagementView()
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "iphone.radiowaves.left.and.right.fill" : "iphone.radiowaves.left.and.right")
                    Text("Devices")
                }
                .tag(1)
            
            MessagesView()
                .tabItem {
                    Image(systemName: selectedTab == 2 ? "message.fill" : "message")
                    Text("Messages")
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Image(systemName: selectedTab == 3 ? "gear.fill" : "gear")
                    Text("Settings")
                }
                .tag(3)
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
