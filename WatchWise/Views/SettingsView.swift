//
//  SettingsView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//

import SwiftUI
import FirebaseFirestore
import Foundation
import FirebaseFirestore

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var databaseManager = DatabaseManager.shared
    @State private var pairedDevices: [ChildDevice] = []
    @State private var alertSettings = AlertSettings.defaultSettings
    @State private var isLoading = false
    @State private var showSignOutAlert = false
    @State private var showUnlinkAlert = false
    @State private var deviceToUnlink: ChildDevice?
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    VStack(spacing: 0) {
                        // User Info Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Account")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            VStack(spacing: 0) {
                                HStack {
                                    Image(systemName: "person.circle.fill")
                                        .font(.title)
                                        .foregroundColor(.blue)
                                    
                                    VStack(alignment: .leading) {
                                        Text(authManager.currentUser?.email ?? "Unknown")
                                            .font(.headline)
                                        Text("Parent Account")
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
                        .padding(.bottom, 24)
                        
                        // Paired Devices Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Paired Devices")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                if isLoading {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Loading devices...")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                } else if pairedDevices.isEmpty {
                                    HStack {
                                        Image(systemName: "iphone.slash")
                                            .foregroundColor(.gray)
                                        Text("No devices paired")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        NavigationLink("Add Device") {
                                            DevicePairingView()
                                        }
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                } else {
                                    ForEach(pairedDevices) { device in
                                        DeviceRow(device: device) {
                                            deviceToUnlink = device
                                            showUnlinkAlert = true
                                        }
                                        .padding()
                                        .background(Color(.systemGray6))
                                        .cornerRadius(12)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 24)
                        
                        // Usage Alerts Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Usage Alerts")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            VStack(spacing: 16) {
                                // Enable Alerts Toggle
                                HStack {
                                    Text("Enable Alerts")
                                        .font(.body)
                                    Spacer()
                                    Toggle("", isOn: $alertSettings.isEnabled)
                                        .onChange(of: alertSettings.isEnabled) { _ in
                                            saveAlertSettings()
                                        }
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                
                                if alertSettings.isEnabled {
                                    // Daily Screen Time Limit
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Daily Screen Time Limit")
                                            .font(.body)
                                            .fontWeight(.medium)
                                        HStack {
                                            Slider(value: $alertSettings.dailyLimitHours, in: 1...12, step: 0.5)
                                                .onChange(of: alertSettings.dailyLimitHours) { _ in
                                                    saveAlertSettings()
                                                }
                                            Text("\(Int(alertSettings.dailyLimitHours))h \(Int((alertSettings.dailyLimitHours.truncatingRemainder(dividingBy: 1)) * 60))m")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .frame(width: 60)
                                        }
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                    
                                    // Social Media Limit
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Social Media Limit")
                                            .font(.body)
                                            .fontWeight(.medium)
                                        HStack {
                                            Slider(value: $alertSettings.socialMediaLimitHours, in: 0.25...6, step: 0.25)
                                                .onChange(of: alertSettings.socialMediaLimitHours) { _ in
                                                    saveAlertSettings()
                                                }
                                            Text("\(Int(alertSettings.socialMediaLimitHours))h \(Int((alertSettings.socialMediaLimitHours.truncatingRemainder(dividingBy: 1)) * 60))m")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .frame(width: 60)
                                        }
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 24)
                        
                        // Privacy & Support Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Privacy & Support")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            VStack(spacing: 1) {
                                NavigationLink(destination: PrivacyView()) {
                                    HStack {
                                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                }
                                .foregroundColor(.primary)
                                
                                NavigationLink(destination: SupportView()) {
                                    HStack {
                                        Label("Help & Support", systemImage: "questionmark.circle.fill")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                }
                                .foregroundColor(.primary)
                                
                                Link(destination: URL(string: "mailto:support@watchwise.app")!) {
                                    HStack {
                                        Label("Contact Us", systemImage: "envelope.fill")
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                }
                                .foregroundColor(.primary)
                            }
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 24)
                        
                        // Account Actions Section
                        VStack(spacing: 16) {
                            Button(action: { showSignOutAlert = true }) {
                                HStack {
                                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                        .foregroundColor(.red)
                                    Spacer()
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 100) // Extra padding for tab bar clearance
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await loadPairedDevices()
            }
            .task {
                await loadInitialData()
            }
        }
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                authManager.signOut()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Unlink Device", isPresented: $showUnlinkAlert) {
            Button("Cancel", role: .cancel) {
                deviceToUnlink = nil
            }
            Button("Unlink", role: .destructive) {
                if let device = deviceToUnlink {
                    unlinkDevice(device)
                }
            }
        } message: {
            Text("Are you sure you want to unlink this device? Screen time monitoring will stop.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Data Loading Methods
    
    @MainActor
    private func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await loadPairedDevices()
            }
            group.addTask {
                await loadAlertSettings()
            }
        }
    }
    
    @MainActor
    private func loadPairedDevices() async {
        guard let parentId = authManager.currentUser?.id else {
            showErrorMessage("User not authenticated")
            return
        }
        
        isLoading = true
        
        await withCheckedContinuation { continuation in
            databaseManager.getChildDevices(for: parentId) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    switch result {
                    case .success(let devices):
                        self.pairedDevices = devices
                        print("✅ Loaded \(devices.count) paired devices")
                    case .failure(let error):
                        self.showErrorMessage("Failed to load paired devices: \(error.localizedDescription)")
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    @MainActor
    private func loadAlertSettings() async {
        guard let userId = authManager.currentUser?.id else { return }
        
        await withCheckedContinuation { continuation in
            FirebaseManager.shared.usersCollection
                .document(userId)
                .collection("settings")
                .document("alerts")
                .getDocument { snapshot, error in
                    DispatchQueue.main.async {
                        if let data = snapshot?.data(),
                           let alertData = try? JSONSerialization.data(withJSONObject: data),
                           let settings = try? JSONDecoder().decode(AlertSettings.self, from: alertData) {
                            self.alertSettings = settings
                        }
                        continuation.resume()
                    }
                }
        }
    }
    
    // MARK: - Device Management
    
    private func unlinkDevice(_ device: ChildDevice) {
        guard let deviceId = device.id else {
            showErrorMessage("Invalid device")
            return
        }
        
        // Update the device status to inactive
        let updateData: [String: Any] = [
            "isActive": false,
            "unlinkedAt": Timestamp()
        ]
        
        FirebaseManager.shared.devicesCollection
            .document(deviceId)
            .updateData(updateData) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.showErrorMessage("Failed to unlink device: \(error.localizedDescription)")
                    } else {
                        // Remove from local array
                        self.pairedDevices.removeAll { $0.id == deviceId }
                        self.deviceToUnlink = nil
                        print("✅ Device unlinked successfully")
                    }
                }
            }
    }
    
    // MARK: - Settings Management
    
    private func saveAlertSettings() {
        guard let userId = authManager.currentUser?.id else { return }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(alertSettings)
            let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            
            FirebaseManager.shared.usersCollection
                .document(userId)
                .collection("settings")
                .document("alerts")
                .setData(dictionary, merge: true) { error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.showErrorMessage("Failed to save alert settings: \(error.localizedDescription)")
                        }
                    } else {
                        print("✅ Alert settings saved successfully")
                    }
                }
        } catch {
            showErrorMessage("Failed to encode alert settings")
        }
    }
    
    // MARK: - Error Handling
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
        print("🔥 Settings Error: \(message)")
    }
}

struct DeviceRow: View {
    let device: ChildDevice
    let onUnlink: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.childName.isEmpty ? "Child's Device" : device.childName)
                    .font(.headline)
                
                Text(device.deviceName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Circle()
                        .fill(device.isActive ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(device.isActive ? "Active" : "Inactive")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if !device.isActive {
                        Text("• Paired \(formatPairDate(device.pairedAt.dateValue()))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if device.isActive {
                Button("Unlink", action: onUnlink)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    private func formatPairDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Last updated: \(Date().formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Group {
                    Text("Data Collection")
                        .font(.headline)
                        .padding(.top)
                    
                    Text("WatchWise collects only the screen time data that is already available to you through iOS Screen Time settings. This includes:")
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• App usage duration and frequency")
                        Text("• Screen time totals per day")
                        Text("• Device pairing information")
                        Text("• Messages sent between parent and child devices")
                    }
                    .padding(.leading)
                    
                    Text("Data Usage")
                        .font(.headline)
                        .padding(.top)
                    
                    Text("Your family's data is used solely to provide screen time insights and messaging functionality between paired devices. We never share your data with third parties or use it for advertising purposes.")
                    
                    Text("Data Security")
                        .font(.headline)
                        .padding(.top)
                    
                    Text("All data is encrypted in transit and at rest using industry-standard security measures. Data is stored securely on Firebase servers with enterprise-grade security.")
                    
                    Text("Your Rights")
                        .font(.headline)
                        .padding(.top)
                    
                    Text("You have the right to access, modify, or delete your family's data at any time. Contact us at support@watchwise.app for assistance with data requests.")
                }
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SupportView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Getting Started")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Install WatchWise Kids on your child's device")
                        Text("2. Open the child app and tap 'Generate Code'")
                        Text("3. Enter the 6-digit code in this parent app")
                        Text("4. Grant Screen Time permissions on the child device")
                        Text("5. Start monitoring and communicating!")
                    }
                    .font(.subheadline)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Common Issues")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Q: Screen time data not showing up?")
                                .fontWeight(.medium)
                            Text("A: Ensure the child app has Screen Time permissions enabled in iOS Settings > Screen Time > Share Across Devices.")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Q: Can't pair devices?")
                                .fontWeight(.medium)
                            Text("A: Check that both devices have internet connection and the pairing code hasn't expired (codes expire after 10 minutes).")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Q: Messages not being delivered?")
                                .fontWeight(.medium)
                            Text("A: Ensure both devices have notifications enabled for WatchWise in iOS Settings > Notifications.")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Contact Support")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Link("Email: support@watchwise.app", destination: URL(string: "mailto:support@watchwise.app")!)
                            .foregroundColor(.blue)
                        
                        Text("We typically respond within 24 hours during business days.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("App Version")
                        .font(.headline)
                    
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            }
            .padding()
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthenticationManager())
}
