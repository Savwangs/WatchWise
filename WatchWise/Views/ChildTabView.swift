//
//  ChildTabView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/7/25.
//

import SwiftUI

struct ChildTabView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ChildHomeContentView()
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                    Text("Home")
                }
                .tag(0)
            
            ChildMessagesView()
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "message.fill" : "message")
                    Text("Messages")
                }
                .tag(1)
            
            ChildSettingsView()
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

// Separate the home content from the main ChildHomeView
struct ChildHomeContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var currentView: ChildViewState = .generateCode
    @State private var isPaired = false
    @State private var devicePairCode: String = ""
    
    enum ChildViewState {
        case generateCode
        case permissionRequest
        case pairedConfirmation
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                // Header
                HStack {
                    Text("WatchWise Kids")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                // Content based on current state
                switch currentView {
                case .generateCode:
                    GenerateCodeView(
                        onCodeGenerated: { code in
                            devicePairCode = code
                        },
                        onPermissionRequested: {
                            currentView = .permissionRequest
                        }
                    )
                    
                case .permissionRequest:
                    PermissionRequestView(
                        onPermissionGranted: {
                            currentView = .pairedConfirmation
                            isPaired = true
                            authManager.completeOnboarding()
                        }
                    )
                    
                case .pairedConfirmation:
                    PairedConfirmationView(
                        isPaired: isPaired
                    )
                }
                
                Spacer()
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            if authManager.hasCompletedOnboarding {
                isPaired = true
                currentView = .pairedConfirmation
            }
        }
    }
}

// Simple settings view for child
struct ChildSettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Settings content
                VStack(spacing: 16) {
                    // User info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Account")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title2)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(authManager.currentUser?.email ?? "")
                                        .font(.body)
                                    Text("Child Account")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Connection status
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connection")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        HStack {
                            Image(systemName: "link.circle.fill")
                                .foregroundColor(authManager.hasCompletedOnboarding ? .green : .orange)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(authManager.hasCompletedOnboarding ? "Connected to Parent" : "Not Connected")
                                    .font(.body)
                                Text(authManager.hasCompletedOnboarding ? "Your parent can see your screen time" : "Complete setup to connect")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    // Sign out button
                    Button(action: {
                        authManager.signOut()
                        UserDefaults.standard.removeObject(forKey: "isChildMode")
                        UserDefaults.standard.removeObject(forKey: "userType")
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                
                Spacer()
            }
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    ChildTabView()
        .environmentObject(AuthenticationManager())
}
