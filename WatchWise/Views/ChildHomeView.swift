//
//  ChildHomeView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/6/25.
//

import SwiftUI
import FirebaseAuth
import FamilyControls
import DeviceActivity
import Foundation
import FirebaseFirestore

struct ChildHomeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var screenTimeDataManager = ScreenTimeDataManager()
    @StateObject private var pairingManager = PairingManager.shared
    @State private var currentView: ChildViewState = .generateCode
    @State private var isPaired = false
    @State private var devicePairCode: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    enum ChildViewState {
        case generateCode
        case permissionRequest
        case pairedConfirmation
        case mainInterface
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                // Header with Sign Out
                HStack {
                    Button("Sign Out") {
                        signOut()
                    }
                    .foregroundColor(.blue)
                    
                    Spacer()
                    
                    // Connection status indicator
                    if isPaired {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                // Error Alert
                if let errorMessage = errorMessage {
                    ErrorBanner(
                        message: errorMessage,
                        onDismiss: { self.errorMessage = nil }
                    )
                }
                
                // Content based on current state
                currentViewContent
                
                Spacer()
            }
            .navigationBarHidden(true)
            .alert("Error", isPresented: $showingError) {
                Button("OK") {
                    errorMessage = nil
                    showingError = false
                }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
        }
        .onAppear {
            checkInitialState()
        }
        .onChange(of: pairingManager.isPaired) { oldValue, newValue in
            isPaired = newValue
            if newValue && currentView == .generateCode {
                currentView = .pairedConfirmation
            }
        }
        .onChange(of: errorMessage) { oldValue, newValue in
            showingError = newValue != nil
        }
    }
    
    @ViewBuilder
    private var currentViewContent: some View {
        switch currentView {
        case .generateCode:
            GenerateCodeView(
                onCodeGenerated: handleCodeGenerated,
                onPermissionRequested: {
                    currentView = .permissionRequest
                }
            )
        case .permissionRequest:
            PermissionRequestView(
                onPermissionGranted: handlePermissionGranted
            )
        case .pairedConfirmation:
            PairedConfirmationView(
                isPaired: isPaired
            )
        case .mainInterface:
            ChildMainInterface(
                screenTimeManager: screenTimeDataManager,
                onUnpair: handleUnpair
            )
        }
    }
    
    // MARK: - Methods
    
    private func checkInitialState() {
        // Check if already paired
        if pairingManager.isPaired {
            isPaired = true
            currentView = screenTimeDataManager.isAuthorized ? .mainInterface : .permissionRequest
        }
        
        // Check Screen Time authorization
        screenTimeDataManager.checkAuthorizationStatus()
    }
    
    private func handleCodeGenerated(code: String) {
        devicePairCode = code
        Task {
            await waitForPairing(code: code)
        }
    }
    
    private func waitForPairing(code: String) async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            // Wait for parent to use the code for pairing
            let success = await waitForPairingComplete(code: code, timeout: 600)
            
            await MainActor.run {
                isLoading = false
                if success {
                    isPaired = true
                    currentView = screenTimeDataManager.isAuthorized ? .pairedConfirmation : .permissionRequest
                } else {
                    errorMessage = "Pairing timed out. Please generate a new code."
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = "Pairing failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func handlePermissionGranted() {
        Task {
            await requestScreenTimePermission()
        }
    }
    
    private func requestScreenTimePermission() async {
        await screenTimeDataManager.requestAuthorization()
        
        await MainActor.run {
            if screenTimeDataManager.isAuthorized {
                // Start screen time monitoring
                Task {
                    await startScreenTimeMonitoring()
                }
                
                // Mark onboarding as complete
                authManager.completeOnboarding()
                
                // Move to confirmation screen
                currentView = .pairedConfirmation
            } else {
                errorMessage = "Screen Time permission is required for the app to work properly."
            }
        }
    }
    
    private func startScreenTimeMonitoring() async {
        guard let deviceId = pairingManager.currentDeviceId else {
            await MainActor.run {
                errorMessage = "Device ID not found. Please try pairing again."
            }
            return
        }
        
        await screenTimeDataManager.startScreenTimeMonitoring(for: deviceId)
        
        // Set up real-time updates
        await MainActor.run {
            screenTimeDataManager.setupRealtimeUpdates(for: deviceId)
        }
    }
    
    private func handlePermissionDenied() {
        errorMessage = "Screen Time permission is required for the app to function. Please grant permission in Settings."
    }
    
    private func handleUnpair() {
        Task {
            await unpairDevice()
        }
    }
    
    private func unpairDevice() async {
        guard let deviceId = pairingManager.currentDeviceId else { return }
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            // Stop screen time monitoring
            screenTimeDataManager.stopMonitoring(for: deviceId)
            
            // Unpair from backend
            let _ = await pairingManager.unpairChild(relationshipId: deviceId)
            
            await MainActor.run {
                isLoading = false
                isPaired = false
                currentView = .generateCode
                
                // Clear onboarding status
                authManager.updateOnboardingStatus(false)
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = "Failed to unpair device: \(error.localizedDescription)"
            }
        }
    }
    
    private func waitForPairingComplete(code: String, timeout: TimeInterval) async -> Bool {
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < timeout {
            // Check if pairing is complete by querying Firestore
            do {
                let db = Firestore.firestore()
                let snapshot = try await db.collection("pairingRequests")
                    .whereField("pairCode", isEqualTo: code)
                    .whereField("isActive", isEqualTo: true)
                    .getDocuments()
                
                if !snapshot.documents.isEmpty {
                    return true
                }
                
                // Wait 2 seconds before checking again
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                print("Error checking pairing status: \(error)")
                return false
            }
        }
        
        return false
    }
    
    private func signOut() {
        // Stop any ongoing monitoring
        if let deviceId = pairingManager.currentDeviceId {
            screenTimeDataManager.stopMonitoring(for: deviceId)
        }
        
        // Clear user defaults
        UserDefaults.standard.removeObject(forKey: "isChildMode")
        UserDefaults.standard.removeObject(forKey: "userType")
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        
        // Sign out from Firebase
        authManager.signOut()
        
        // Reset state
        isPaired = false
        currentView = .generateCode
    }
}

// MARK: - Error Banner
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Button("✕", action: onDismiss)
                .foregroundColor(.red)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Privacy Item
struct PrivacyItem: View {
    let icon: String
    let text: String
    let isNegative: Bool
    
    init(icon: String, text: String, isNegative: Bool = false) {
        self.icon = icon
        self.text = text
        self.isNegative = isNegative
    }
    
    var body: some View {
        HStack {
            Image(systemName: isNegative ? "xmark.circle" : "checkmark.circle")
                .foregroundColor(isNegative ? .red : .green)
            
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Feature Item
struct FeatureItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
}

// MARK: - Child Main Interface
struct ChildMainInterface: View {
    let screenTimeManager: ScreenTimeDataManager
    let onUnpair: () -> Void
    
    @State private var showingSettings = false
    
    var body: some View {
        TabView {
            // Home Tab
            ChildDashboardTab(screenTimeManager: screenTimeManager)
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
            
            // Messages Tab
            ChildMessagesTab()
                .tabItem {
                    Image(systemName: "message.fill")
                    Text("Messages")
                }
            
            // Settings Tab
            ChildSettingsTab(onUnpair: onUnpair)
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }
    }
}

// MARK: - Child Dashboard Tab
struct ChildDashboardTab: View {
    let screenTimeManager: ScreenTimeDataManager
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Current Screen Time
                    if let screenTimeData = screenTimeManager.currentScreenTimeData {
                        VStack(spacing: 16) {
                            Text("Today's Screen Time")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(screenTimeManager.formatDuration(screenTimeData.totalScreenTime))
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        
                        // Top Apps
                        if !screenTimeData.appUsages.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Most Used Apps")
                                    .font(.headline)
                                
                                ForEach(Array(screenTimeData.appUsages.prefix(3).enumerated()), id: \.offset) { index, usage in
                                    HStack {
                                        Text("\(index + 1)")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .frame(width: 20, height: 20)
                                            .background(Color.blue)
                                            .clipShape(Circle())
                                        
                                        Text(usage.appName)
                                            .font(.body)
                                        
                                        Spacer()
                                        
                                        Text(screenTimeManager.formatDuration(usage.duration))
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    } else {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Loading your screen time data...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 200)
                    }
                }
                .padding()
            }
            .navigationTitle("My Usage")
        }
    }
}

// MARK: - Child Messages Tab
struct ChildMessagesTab: View {
    var body: some View {
        NavigationView {
            VStack {
                Text("Messages from Parent")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("No new messages")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .padding(.top, 50)
                
                Spacer()
            }
            .navigationTitle("Messages")
        }
    }
}

// MARK: - Child Settings Tab
struct ChildSettingsTab: View {
    let onUnpair: () -> Void
    
    var body: some View {
        NavigationView {
            List {
                Section("Connection") {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.green)
                        Text("Connected to Parent")
                        Spacer()
                        Text("Active")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    Button("Disconnect Device") {
                        onUnpair()
                    }
                    .foregroundColor(.red)
                }
                
                Section("Privacy") {
                    NavigationLink("Privacy Policy") {
                        Text("Privacy Policy Content")
                    }
                    
                    NavigationLink("Data Usage") {
                        Text("Data Usage Information")
                    }
                }
                
                Section("Support") {
                    NavigationLink("Help & Support") {
                        Text("Help Content")
                    }
                    
                    NavigationLink("Contact Us") {
                        Text("Contact Information")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    ChildHomeView()
        .environmentObject(AuthenticationManager())
}
