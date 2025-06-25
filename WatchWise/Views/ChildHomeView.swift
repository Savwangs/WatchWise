//
//  ChildHomeView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/6/25.
//

import SwiftUI
import FirebaseAuth

struct ChildHomeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var screenTimeDataManager = ScreenTimeDataManager()
    @State private var showSignOutAlert = false
    
    var body: some View {
        TabView {
            // Messages Tab (Default Tab)
            NavigationView {
                VStack(spacing: 20) {
                    // Welcome Header
                    VStack(spacing: 8) {
                        // DEMO DATA - START (Remove in production)
                        Text(authManager.isNewSignUp ? "Connection Successful!" : "Welcome back, Savir!")
                            .font(.title)
                            .fontWeight(.bold)
                            .padding(.top, 20)
                        
                        Text("Messages from Parent")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        // DEMO DATA - END (Remove in production)
                        
                        /* PRODUCTION CODE - Uncomment when ready for production
                        Text("Welcome back, \(authManager.currentUser?.name ?? "")!")
                            .font(.title)
                            .fontWeight(.bold)
                            .padding(.top, 20)
                        
                        Text("Messages from Parent")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        */
                    }
                    
                    // Messages List
                    ScrollView {
                        VStack(spacing: 12) {
                            // DEMO DATA - START (Remove in production)
                            MessageRow(
                                message: "Great job keeping your screen time low today! 👏",
                                timestamp: "2 hours ago",
                                isFromParent: true
                            )
                            
                            MessageRow(
                                message: "Don't forget to take breaks between study sessions",
                                timestamp: "Yesterday",
                                isFromParent: true
                            )
                            // DEMO DATA - END (Remove in production)
                            
                            /* PRODUCTION CODE - Uncomment when ready for production
                            ForEach(messagesManager.messages, id: \.id) { message in
                                MessageRow(
                                    message: message.content,
                                    timestamp: message.formattedDate,
                                    isFromParent: message.isFromParent
                                )
                            }
                            */
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer()
                }
                .navigationBarHidden(true)
            }
            .tabItem {
                Image(systemName: "message.fill")
                Text("Messages")
            }
            
            // Settings Tab
            NavigationView {
                List {
                    Section("Device Connection") {
                        HStack {
                            Image(systemName: "iphone")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                // DEMO DATA - START (Remove in production)
                                Text("Savir's iPhone")
                                    .font(.body)
                                Text("Connected to Parent Device")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                // DEMO DATA - END (Remove in production)
                                
                                /* PRODUCTION CODE - Uncomment when ready for production
                                Text(authManager.currentUser?.deviceName ?? "This Device")
                                    .font(.body)
                                Text("Connected to \(authManager.parentDeviceName ?? "Parent Device")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                */
                            }
                            Spacer()
                            
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Section("Account") {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.gray)
                            // DEMO DATA - START (Remove in production)
                            Text("Savir")
                            // DEMO DATA - END (Remove in production)
                            
                            /* PRODUCTION CODE - Uncomment when ready for production
                            Text(authManager.currentUser?.name ?? "Child User")
                            */
                        }
                        
                        Button(action: {
                            showSignOutAlert = true
                        }) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .foregroundColor(.red)
                                Text("Sign Out")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    Section("Bedtime Settings") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "moon.fill")
                                    .foregroundColor(.purple)
                                Text("Your Bedtime")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Current Bedtime Range")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Text("10:00 PM - 5:00 AM")
                                        .font(.title3)
                                        .fontWeight(.medium)
                                        .foregroundColor(.purple)
                                    Spacer()
                                }
                                .padding()
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(8)
                                
                                Text("During this time, your apps will be automatically disabled to help you get a good night's sleep.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Section("Privacy & Support") {
                        NavigationLink(destination: PrivacyPolicyView()) {
                            Label("Privacy Policy", systemImage: "hand.raised.fill")
                        }
                        
                        NavigationLink(destination: ChildSupportView()) {
                            Label("Help & Support", systemImage: "questionmark.circle.fill")
                        }
                    }
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.large)
            }
            .tabItem {
                Image(systemName: "gear")
                Text("Settings")
            }
        }
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                signOut()
            }
        } message: {
            Text("Are you sure you want to sign out? This will disconnect your device from your parent.")
        }
    }
    
    private func signOut() {
        // Clear user defaults
        UserDefaults.standard.removeObject(forKey: "isChildMode")
        UserDefaults.standard.removeObject(forKey: "userType")
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        
        // Sign out from Firebase
        authManager.signOut()
    }
}

// MARK: - Supporting Views

struct MessageRow: View {
    let message: String
    let timestamp: String
    let isFromParent: Bool
    
    var body: some View {
        HStack {
            if isFromParent {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.blue)
                        Text("Parent")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        Spacer()
                        Text(timestamp)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(message)
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                }
                Spacer(minLength: 50)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Placeholder Views

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Your privacy is important to us. This app only collects screen time data necessary for parental monitoring.")
                    .font(.body)
                
                Text("We do not share your data with third parties and all data is encrypted.")
                    .font(.body)
                
                Spacer()
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ChildSupportView: View {
    var body: some View {
        List {
            Section("Get Help") {
                Link("Email Support", destination: URL(string: "mailto:support@watchwise.com")!)
                Link("User Guide", destination: URL(string: "https://watchwise.com/help")!)
            }
            
            Section("App Info") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    ChildHomeView()
        .environmentObject(AuthenticationManager())
}
