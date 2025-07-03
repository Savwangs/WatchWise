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
    @StateObject private var activityManager = ActivityMonitoringManager.shared
    @State private var showSignOutAlert = false
    @State private var showPermissionAlert = false
    
    var body: some View {
        TabView {
            // Messages Tab (Default Tab)
            NavigationView {
                VStack(spacing: 20) {
                    // Welcome Header
                    VStack(spacing: 8) {
                        Text(authManager.isNewSignUp ? "Connection Successful!" : "Welcome back, \(authManager.currentUser?.name ?? "Child")!")
                            .font(.title)
                            .fontWeight(.bold)
                            .padding(.top, 20)
                        
                        Text("Messages from Parent")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
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
                                Text(authManager.currentUser?.deviceName ?? "This Device")
                                    .font(.body)
                                Text("Connected to Parent Device")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Section("Screen Time Monitoring") {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Screen Time Authorization")
                                    .font(.body)
                                Text(screenTimeDataManager.isAuthorized ? "Authorized" : "Not Authorized")
                                    .font(.caption)
                                    .foregroundColor(screenTimeDataManager.isAuthorized ? .green : .red)
                            }
                            Spacer()
                            
                            if !screenTimeDataManager.isAuthorized {
                                Button("Grant Access") {
                                    Task {
                                        await screenTimeDataManager.requestAuthorization()
                                    }
                                }
                                .foregroundColor(.blue)
                                .font(.caption)
                            }
                        }
                        
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .foregroundColor(.purple)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Monitoring Status")
                                    .font(.body)
                                Text(screenTimeDataManager.isMonitoring ? "Active" : "Inactive")
                                    .font(.caption)
                                    .foregroundColor(screenTimeDataManager.isMonitoring ? .green : .red)
                            }
                            Spacer()
                        }
                        
                        if !screenTimeDataManager.detectedNewApps.isEmpty {
                            HStack {
                                Image(systemName: "app.badge.plus")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("New Apps Detected")
                                        .font(.body)
                                    Text("\(screenTimeDataManager.detectedNewApps.count) new apps")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                                Spacer()
                            }
                        }
                        
                        if screenTimeDataManager.isAuthorized && !screenTimeDataManager.isMonitoring {
                            Button("Start Monitoring") {
                                Task {
                                    if let deviceId = authManager.currentUser?.id {
                                        await screenTimeDataManager.startScreenTimeMonitoring(for: deviceId)
                                    }
                                }
                            }
                            .foregroundColor(.green)
                        }
                    }
                    
                    Section("Account") {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.gray)
                            Text(authManager.currentUser?.name ?? "Child User")
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
                    
                    // Debug section for heartbeat testing
                    Section("Debug Info") {
                        HStack {
                            Label("Heartbeat Status", systemImage: "heart.fill")
                            Spacer()
                            Text(activityManager.isMonitoring ? "Active" : "Inactive")
                                .foregroundColor(activityManager.isMonitoring ? .green : .red)
                        }
                        
                        HStack {
                            Label("Missed Heartbeats", systemImage: "exclamationmark.triangle.fill")
                            Spacer()
                            Text("\(activityManager.missedHeartbeats)")
                                .foregroundColor(activityManager.missedHeartbeats > 0 ? .red : .green)
                        }
                        
                        HStack {
                            Label("User Type", systemImage: "person.fill")
                            Spacer()
                            Text(authManager.currentUser?.userType ?? "Unknown")
                                .foregroundColor(.secondary)
                        }
                        
                        if let lastActivity = activityManager.lastActivityTime {
                            HStack {
                                Label("Last Activity", systemImage: "clock.fill")
                                Spacer()
                                Text(lastActivity, style: .relative)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Button("Send Test Heartbeat") {
                            Task {
                                await activityManager.sendHeartbeat()
                            }
                        }
                        .foregroundColor(.blue)
                        
                        Button("Start Monitoring") {
                            activityManager.startMonitoring()
                        }
                        .foregroundColor(.green)
                        
                        Button("Debug: Trigger Background Heartbeat") {
                            activityManager.debugTriggerBackgroundHeartbeat()
                        }
                        .foregroundColor(.orange)
                        
                        Button("Debug: Show Background Status") {
                            activityManager.debugShowBackgroundTaskStatus()
                        }
                        .foregroundColor(.purple)
                        
                        // Screen Time Debug
                        Button("Detect New Apps") {
                            Task {
                                await screenTimeDataManager.detectNewApps()
                            }
                        }
                        .foregroundColor(.indigo)
                        
                        Button("Sync Screen Time Data") {
                            Task {
                                if let deviceId = authManager.currentUser?.id {
                                    await screenTimeDataManager.syncScreenTimeData(for: deviceId)
                                }
                            }
                        }
                        .foregroundColor(.teal)
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
        .alert("Permission Required", isPresented: $showPermissionAlert) {
            Button("Grant Permission") {
                Task {
                    await screenTimeDataManager.requestAuthorization()
                }
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("Screen Time monitoring requires Family Controls permission to track app usage and help your parent monitor your device usage.")
        }
        .onAppear {
            // Start heartbeat monitoring for child device
            activityManager.startMonitoring()
            
            // Check if screen time authorization is needed
            if !screenTimeDataManager.isAuthorized {
                showPermissionAlert = true
            } else if let deviceId = authManager.currentUser?.id {
                // Start screen time monitoring if authorized
                Task {
                    await screenTimeDataManager.startScreenTimeMonitoring(for: deviceId)
                }
            }
        }
        .onChange(of: screenTimeDataManager.errorMessage) { errorMessage in
            if let error = errorMessage {
                print("🔥 Screen Time Error: \(error)")
            }
        }
    }
    
    private func signOut() {
        // Stop monitoring
        screenTimeDataManager.stopMonitoring()
        activityManager.stopMonitoring()
        
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
