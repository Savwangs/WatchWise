//
//  ChildHomeView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/6/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ChildHomeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var screenTimeDataManager = ScreenTimeDataManager()
    @StateObject private var activityManager = ActivityMonitoringManager.shared
    @StateObject private var messagingManager = MessagingManager.shared
    @State private var showSignOutAlert = false
    @State private var showPermissionAlert = false
    
    var body: some View {
        TabView {
            // Messages Tab (Default Tab)
            NavigationView {
                VStack(spacing: 20) {
                    // Welcome Header
                    VStack(spacing: 8) {
                        Text(getWelcomeMessage())
                            .onAppear {
                                // Debug logging to help identify the issue
                                if let user = authManager.currentUser {
                                    print("🔍 User data loaded:")
                                    print("   - ID: \(user.id)")
                                    print("   - Email: \(user.email)")
                                    print("   - Name: \(user.name ?? "nil") (type: \(type(of: user.name)))")
                                    print("   - Device Name: \(user.deviceName ?? "nil") (type: \(type(of: user.deviceName)))")
                                    print("   - User Type: \(user.userType ?? "nil")")
                                }
                            }
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
                            if messagingManager.messages.isEmpty {
                                Text("No messages yet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 40)
                            } else {
                                ForEach(messagingManager.messages, id: \.id) { message in
                                    MessageRow(
                                        message: message.text,
                                        timestamp: message.formattedTimestamp,
                                        isFromParent: true // All messages in child view are from parent
                                    )
                                }
                            }
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
                                Text(getDeviceName())
                                    .font(.body)
                                Text(authManager.currentUser?.isDevicePaired == true ? "Connected to Parent Device" : "Not Connected to Parent")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            
                            Circle()
                                .fill(authManager.currentUser?.isDevicePaired == true ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                        }
                        .padding(.vertical, 8)
                    }
                    

                    
                    Section("Account") {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.gray)
                            Text(getChildName())
                            .onAppear {
                                // Additional safety check
                                if let name = authManager.currentUser?.name {
                                    print("🔍 Displaying user name: '\(name)' (type: \(type(of: name)))")
                                }
                            }
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
                                    Text("10:00 PM - 8:00 AM")
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
        .alert("Permission Required", isPresented: $showPermissionAlert) {
            Button("Grant Permission") {
                Task {
                    await screenTimeDataManager.requestAuthorization()
                    // Mark that permission has been requested
                    UserDefaults.standard.set(true, forKey: "hasRequestedScreenTimePermission")
                }
            }
            Button("Later", role: .cancel) { 
                // Mark that permission has been requested (even if declined)
                UserDefaults.standard.set(true, forKey: "hasRequestedScreenTimePermission")
            }
        } message: {
            Text("Screen Time monitoring requires Family Controls permission to track app usage and help your parent monitor your device usage.")
        }
        .onAppear {
            print("🔍 ChildHomeView appeared")
            
            // Add safety check for user data
            if let user = authManager.currentUser {
                print("🔍 User data in ChildHomeView:")
                print("   - ID: \(user.id)")
                print("   - Email: \(user.email)")
                print("   - Name: \(user.name ?? "nil")")
                print("   - User Type: \(user.userType ?? "nil")")
                print("   - Onboarding: \(user.hasCompletedOnboarding)")
                print("   - Device Paired: \(user.isDevicePaired)")
            } else {
                print("❌ No user data available in ChildHomeView")
            }
            
            // Setup messaging connection
            setupMessageListener()
            
            // Start heartbeat monitoring for child device with error handling
            Task {
                do {
                    activityManager.startMonitoring()
                } catch {
                    print("🔥 Error starting activity monitoring: \(error)")
                }
            }
            
            // Check authorization status and start monitoring if authorized
            let hasRequestedPermission = UserDefaults.standard.bool(forKey: "hasRequestedScreenTimePermission")
            let isAuthorized = UserDefaults.standard.bool(forKey: "screenTimeAuthorized")
            
            // Update the manager's authorization status
            screenTimeDataManager.checkAuthorizationStatus()
            
            if screenTimeDataManager.isAuthorized || isAuthorized {
                // User is authorized, start monitoring
                if let deviceId = authManager.currentUser?.id {
                    print("🔍 Starting screen time monitoring for device: \(deviceId)")
                    Task {
                        do {
                            await screenTimeDataManager.startScreenTimeMonitoring(for: deviceId)
                        } catch {
                            print("🔥 Error starting screen time monitoring: \(error)")
                        }
                    }
                }
            } else if !hasRequestedPermission {
                // New user who hasn't requested permission yet
                print("🔍 Screen time authorization needed for new user")
                showPermissionAlert = true
            } else {
                // User has requested permission but it was denied or not determined
                print("⚠️ Screen time authorization was requested but not granted")
            }
        }
        .onChange(of: screenTimeDataManager.errorMessage) { errorMessage in
            if let error = errorMessage {
                print("🔥 Screen Time Error: \(error)")
            }
        }
        .onDisappear {
            // Cleanup is handled by MessagingManager
        }
    }
    
    private func signOut() {
        // Stop monitoring
        screenTimeDataManager.stopMonitoring()
        activityManager.stopMonitoring()
        
        // Clear user defaults (but keep authorization status)
        UserDefaults.standard.removeObject(forKey: "isChildMode")
        UserDefaults.standard.removeObject(forKey: "userType")
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        
        // Note: We keep screen time authorization status persistent
        // UserDefaults.standard.removeObject(forKey: "screenTimeAuthorized")
        // UserDefaults.standard.removeObject(forKey: "hasRequestedScreenTimePermission")
        
        // Sign out from Firebase
        authManager.signOut()
    }
    
    // MARK: - Message Management
    private func setupMessageListener() {
        guard let deviceId = authManager.currentUser?.id else { return }
        
        // Load parent ID for child device
        Task {
            let parentId = await PairingManager.shared.loadParentForChild(childUserId: deviceId)
            if let parentId = parentId {
                print("✅ ChildHomeView: Connecting to messaging with parentId: \(parentId), childId: \(deviceId)")
                messagingManager.connect(parentId: parentId, childId: deviceId)
                
                // The messages will be automatically updated through the @StateObject observation
                // No need to manually sync since MessagingManager is @Published
            } else {
                print("❌ ChildHomeView: Could not load parent ID for messaging")
            }
        }
    }
    
    private func formatTimestamp(_ timestamp: Timestamp) -> String {
        let date = timestamp.dateValue()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func getWelcomeMessage() -> String {
        let isFirstTime = UserDefaults.standard.bool(forKey: "hasShownWelcomeMessage")
        let childName = getChildName()
        
        if !isFirstTime {
            // Mark that welcome message has been shown
            UserDefaults.standard.set(true, forKey: "hasShownWelcomeMessage")
            return "Connection Successful, Savir!"
        } else {
            return "Connection Successful, Savir!"
        }
    }
    
    private func getChildName() -> String {
        return "Savir"
    }
    
    private func getDeviceName() -> String {
        return "Savir's iPhone"
    }
    
    private func isScreenTimeAuthorized() -> Bool {
        // Check both the manager's status and stored status
        let storedAuthorization = UserDefaults.standard.bool(forKey: "screenTimeAuthorized")
        return screenTimeDataManager.isAuthorized || storedAuthorization
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
