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
    @State private var currentScreenTime = "4h 5m"
    
    var body: some View {
        TabView {
            // Dashboard Tab (Main View)
            NavigationView {
                ScrollView {
                    VStack(spacing: 24) {
                        // Welcome Header
                        VStack(spacing: 8) {
                            // DEMO DATA - START (Remove in production)
                            Text(authManager.isNewSignUp ? "Connection Successful!" : "Welcome back, Savir!")
                                .font(.title)
                                .fontWeight(.bold)
                                .padding(.top, 20)
                            
                            Text("Today's Screen Time")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            // DEMO DATA - END (Remove in production)
                            
                            /* PRODUCTION CODE - Uncomment when ready for production
                            Text("Welcome back, \(authManager.currentUser?.name ?? "")!")
                                .font(.title)
                                .fontWeight(.bold)
                                .padding(.top, 20)
                            
                            Text("Today's Screen Time")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            */
                        }
                        
                        // Screen Time Card
                        VStack(spacing: 16) {
                            Text(currentScreenTime)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.blue)
                            
                            HStack {
                                Image(systemName: "clock.fill")
                                    .foregroundColor(.blue)
                                Text("Total time today")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 32)
                        .padding(.horizontal, 24)
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                        
                        // Top Apps Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Top 3 Most Used Apps")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            
                            // DEMO DATA - START (Remove in production)
                            AppUsageRow(appName: "Instagram", duration: "1h 15m", icon: "camera.fill", color: .pink)
                            AppUsageRow(appName: "Youtube", duration: "1h", icon: "play.rectangle.fill", color: .red)
                            AppUsageRow(appName: "TikTok", duration: "45m", icon: "music.note", color: .black)
                            // DEMO DATA - END (Remove in production)
                            
                            /* PRODUCTION CODE - Uncomment when ready for production
                            ForEach(screenTimeDataManager.topApps, id: \.id) { app in
                                AppUsageRow(
                                    appName: app.name,
                                    duration: formatDuration(app.duration),
                                    icon: app.icon,
                                    color: app.color
                                )
                            }
                            */
                        }
                        .padding(.horizontal, 4)
                        
                        // Connection Status
                        HStack {
                            Image(systemName: "link.circle.fill")
                                .foregroundColor(.green)
                            // DEMO DATA - START (Remove in production)
                            Text("Connected to Parent Device")
                            // DEMO DATA - END (Remove in production)
                            
                            /* PRODUCTION CODE - Uncomment when ready for production
                            Text("Connected to \(authManager.parentDeviceName ?? "Parent Device")")
                            */
                            
                            Spacer()
                            
                            Text("Active")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(6)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .navigationBarHidden(true)
            }
            .tabItem {
                Image(systemName: "house.fill")
                Text("Dashboard")
            }
            
            // Messages Tab
            NavigationView {
                VStack(spacing: 20) {
                    Text("Messages from Parent")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.top, 20)
                    
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
        .onAppear {
            updateScreenTime()
        }
    }
    
    private func updateScreenTime() {
        // DEMO DATA - START (Remove in production)
        // Use demo data from ScreenTimeData for consistency
        let demoData = ScreenTimeData.demoData
        let hours = Int(demoData.totalScreenTime) / 3600
        let minutes = Int(demoData.totalScreenTime) % 3600 / 60
        currentScreenTime = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        // DEMO DATA - END (Remove in production)
        
        /* PRODUCTION CODE - Uncomment when ready for production
        Task {
            if let userId = authManager.currentUser?.id {
                let screenTimeData = try await databaseManager.getScreenTimeData(for: userId, date: Date())
                await MainActor.run {
                    let hours = Int(screenTimeData.totalScreenTime) / 3600
                    let minutes = Int(screenTimeData.totalScreenTime) % 3600 / 60
                    currentScreenTime = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
                }
            }
        }
        */
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

struct AppUsageRow: View {
    let appName: String
    let duration: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(duration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Simple usage bar
            Rectangle()
                .fill(color.opacity(0.3))
                .frame(width: 40, height: 4)
                .cornerRadius(2)
        }
        .padding(.vertical, 8)
    }
}

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
