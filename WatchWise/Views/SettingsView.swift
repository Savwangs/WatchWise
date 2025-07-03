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
    @StateObject private var pairingManager = PairingManager.shared
    @State private var alertSettings = AlertSettings.defaultSettings
    @State private var showSignOutAlert = false
    @State private var showUnlinkAlert = false
    @State private var deviceToUnlink: PairedChildDevice?
    @State private var showError = false
    @State private var errorMessage = ""
    
    // NEW: App deletion functionality
    @State private var deletedApps: [String] = [] // Bundle identifiers of deleted apps
    @State private var showUndoAlert = false
    @State private var appToUndo: String? // Bundle identifier of app to undo deletion
    @State private var undoTimeout: Timer?
    
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
                        
                        // Current Paired Device Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Current Paired Device")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                if pairingManager.isLoading {
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
                                } else if pairingManager.pairedChildren.isEmpty {
                                    HStack {
                                        Image(systemName: "iphone.slash")
                                            .foregroundColor(.gray)
                                        Text("No device currently paired")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                } else {
                                    // Show the currently selected device from Dashboard
                                    let selectedDeviceId = UserDefaults.standard.string(forKey: "selectedDeviceId")
                                    let currentDevice = selectedDeviceId != nil ? 
                                        pairingManager.pairedChildren.first { $0.childUserId == selectedDeviceId } :
                                        pairingManager.pairedChildren.first
                                    
                                    if let device = currentDevice {
                                        CurrentDeviceRow(device: device)
                                            .padding()
                                            .background(Color(.systemGray6))
                                            .cornerRadius(12)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 24)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Text("App Screen Time Limits")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            VStack(spacing: 16) {
                                // Enable Alerts Toggle
                                HStack {
                                    Text("Enable App Limits")
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
                                    // Individual App Limits
                                    ForEach(getTopAppsForLimits(), id: \.bundleIdentifier) { app in
                                        AppLimitSlider(
                                            appName: app.appName,
                                            bundleIdentifier: app.bundleIdentifier,
                                            currentUsage: app.duration,
                                            timeLimit: bindingForApp(app.bundleIdentifier),
                                            isDisabled: alertSettings.disabledApps.contains(app.bundleIdentifier),
                                            onDisableToggle: { isDisabled in
                                                if isDisabled {
                                                    alertSettings.disabledApps.append(app.bundleIdentifier)
                                                } else {
                                                    alertSettings.disabledApps.removeAll { $0 == app.bundleIdentifier }
                                                }
                                                saveAlertSettings()
                                            },
                                            onDelete: {
                                                deleteApp(app.bundleIdentifier)
                                            }
                                        )
                                    }
                                    
                                    // Show undo alert if there are deleted apps
                                    if !deletedApps.isEmpty {
                                        VStack(spacing: 8) {
                                            HStack {
                                                Image(systemName: "info.circle.fill")
                                                    .foregroundColor(.orange)
                                                Text("Recently Deleted Apps")
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                Spacer()
                                            }
                                            
                                            ForEach(deletedApps, id: \.self) { bundleId in
                                                if let appName = getAppName(for: bundleId) {
                                                    HStack {
                                                        Text(appName)
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                        Spacer()
                                                        Button("Undo") {
                                                            undoAppDeletion(bundleId)
                                                        }
                                                        .font(.caption)
                                                        .foregroundColor(.blue)
                                                    }
                                                    .padding(.vertical, 4)
                                                }
                                            }
                                        }
                                        .padding()
                                        .background(Color.orange.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 24)
                        
                        // Bedtime Settings Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Bedtime Settings")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            VStack(spacing: 16) {
                                // Enable Bedtime Toggle
                                HStack {
                                    Text("Enable Bedtime Mode")
                                        .font(.body)
                                    Spacer()
                                    Toggle("", isOn: $alertSettings.bedtimeSettings.isEnabled)
                                        .onChange(of: alertSettings.bedtimeSettings.isEnabled) { _ in
                                            saveAlertSettings()
                                        }
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .onAppear {
                                    print("🔍 Bedtime settings loaded - Enabled: \(alertSettings.bedtimeSettings.isEnabled), Range: \(alertSettings.bedtimeSettings.startTime) - \(alertSettings.bedtimeSettings.endTime)")
                                }
                                
                                if alertSettings.bedtimeSettings.isEnabled {
                                    // Current Bedtime Range Display
                                    VStack(spacing: 8) {
                                        HStack {
                                            Text("Current Bedtime Range")
                                                .font(.body)
                                                .fontWeight(.medium)
                                            Spacer()
                                        }
                                        
                                        HStack {
                                            Image(systemName: "moon.fill")
                                                .foregroundColor(.purple)
                                            Text(formatTimeForDisplay(alertSettings.bedtimeSettings.startTime) + " - " + formatTimeForDisplay(alertSettings.bedtimeSettings.endTime))
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                            Spacer()
                                        }
                                        .padding()
                                        .background(Color.purple.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                    
                                    // Bedtime Time Range
                                    VStack(spacing: 12) {
                                        HStack {
                                            Text("Bedtime Range")
                                                .font(.body)
                                                .fontWeight(.medium)
                                            Spacer()
                                        }
                                        
                                        HStack(spacing: 16) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Start Time")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                
                                                DatePicker("", selection: Binding(
                                                    get: { 
                                                        let formatter = DateFormatter()
                                                        formatter.dateFormat = "HH:mm"
                                                        return formatter.date(from: alertSettings.bedtimeSettings.startTime) ?? Date()
                                                    },
                                                    set: { newDate in
                                                        let formatter = DateFormatter()
                                                        formatter.dateFormat = "HH:mm"
                                                        alertSettings.bedtimeSettings.startTime = formatter.string(from: newDate)
                                                        saveAlertSettings()
                                                    }
                                                ), displayedComponents: .hourAndMinute)
                                                .labelsHidden()
                                            }
                                            
                                            Text("to")
                                                .font(.body)
                                                .foregroundColor(.secondary)
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("End Time")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                
                                                DatePicker("", selection: Binding(
                                                    get: { 
                                                        let formatter = DateFormatter()
                                                        formatter.dateFormat = "HH:mm"
                                                        return formatter.date(from: alertSettings.bedtimeSettings.endTime) ?? Date()
                                                    },
                                                    set: { newDate in
                                                        let formatter = DateFormatter()
                                                        formatter.dateFormat = "HH:mm"
                                                        alertSettings.bedtimeSettings.endTime = formatter.string(from: newDate)
                                                        saveAlertSettings()
                                                    }
                                                ), displayedComponents: .hourAndMinute)
                                                .labelsHidden()
                                            }
                                            
                                            Spacer()
                                        }
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                    
                                    // Days of Week Selection
                                    VStack(spacing: 12) {
                                        HStack {
                                            Text("Active Days")
                                                .font(.body)
                                                .fontWeight(.medium)
                                            Spacer()
                                        }
                                        
                                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                                            ForEach(1...7, id: \.self) { day in
                                                DayToggleButton(
                                                    day: day,
                                                    isSelected: alertSettings.bedtimeSettings.enabledDays.contains(day),
                                                    onToggle: { isSelected in
                                                        if isSelected {
                                                            alertSettings.bedtimeSettings.enabledDays.append(day)
                                                        } else {
                                                            alertSettings.bedtimeSettings.enabledDays.removeAll { $0 == day }
                                                        }
                                                        saveAlertSettings()
                                                    }
                                                )
                                            }
                                        }
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                    
                                    // Bedtime Info
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: "moon.fill")
                                                .foregroundColor(.purple)
                                            Text("Bedtime Mode Info")
                                                .font(.body)
                                                .fontWeight(.medium)
                                        }
                                        
                                        Text("During bedtime hours, monitored apps will be automatically disabled on your child's device to encourage healthy sleep habits.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(Color.purple.opacity(0.1))
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
                await pairingManager.loadPairedChildren()
            }
            .onAppear {
                Task {
                    await pairingManager.loadPairedChildren()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task {
                    await pairingManager.loadPairedChildren()
                }
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
                Task {
                    await pairingManager.loadPairedChildren()
                }
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
        .onDisappear {
            // Clean up timer when view disappears
            undoTimeout?.invalidate()
            undoTimeout = nil
        }
    }
    
    // MARK: - Data Loading Methods
    
    // This function is no longer needed since we're using PairingManager
    // The paired devices are now loaded through pairingManager.loadPairedChildren()
    
    // This function is no longer needed since we're using PairingManager
    // The paired devices are now loaded through pairingManager.loadPairedChildren()
    
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
    
    private func unlinkDevice(_ device: PairedChildDevice) {
        Task {
            let result = await pairingManager.unpairChild(relationshipId: device.id)
            
            await MainActor.run {
                switch result {
                case .success:
                    self.deviceToUnlink = nil
                    print("✅ Device unlinked successfully")
                case .failure(let error):
                    self.showErrorMessage("Failed to unlink device: \(error.localizedDescription)")
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
    
    // MARK: - App Limits Helper Methods
    private func getTopAppsForLimits() -> [AppUsage] {
        // Get the top apps from current screen time data
        // This would come from your actual screen time data source
        return []
    }

    private func loadAlertSettingsWithDefaults() async {
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
                        } else {
                            self.alertSettings = AlertSettings.defaultSettings
                        }
                        continuation.resume()
                    }
                }
        }
    }
    
    private func bindingForApp(_ bundleId: String) -> Binding<Double> {
        return Binding(
            get: { alertSettings.appLimits[bundleId] ?? 2.0 },
            set: { newValue in
                alertSettings.appLimits[bundleId] = newValue
                saveAlertSettings()
            }
        )
    }
    
    private func formatTimeForDisplay(_ time: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        if let date = formatter.date(from: time) {
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        }
        return time
    }
    
    // MARK: - App Deletion Functions
    private func deleteApp(_ bundleId: String) {
        // Add to deleted apps list
        if !deletedApps.contains(bundleId) {
            deletedApps.append(bundleId)
        }
        
        // Remove from app limits
        alertSettings.appLimits.removeValue(forKey: bundleId)
        
        // Remove from disabled apps if present
        alertSettings.disabledApps.removeAll { $0 == bundleId }
        
        // Save settings
        saveAlertSettings()
        
        // Set up undo timeout (5 minutes)
        undoTimeout?.invalidate()
        undoTimeout = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { _ in
            // Permanently remove from deleted apps after timeout
            deletedApps.removeAll { $0 == bundleId }
        }
        
        print("🗑️ App deleted from monitoring: \(bundleId)")
    }
    
    private func undoAppDeletion(_ bundleId: String) {
        // Remove from deleted apps
        deletedApps.removeAll { $0 == bundleId }
        
        // Restore default app limit
        alertSettings.appLimits[bundleId] = 2.0 // Default 2 hours
        
        // Save settings
        saveAlertSettings()
        
        // Cancel timeout for this app
        undoTimeout?.invalidate()
        
        print("↩️ App deletion undone: \(bundleId)")
    }
    
    private func getAppName(for bundleId: String) -> String? {
                                // Get app name from actual data source
        let demoApps = [
            "com.burbn.instagram": "Instagram",
            "com.zhiliaoapp.musically": "TikTok",
            "com.google.ios.youtube": "YouTube",
            "com.apple.mobilesafari": "Safari",
            "com.toyopagroup.picaboo": "Snapchat",
            "com.apple.MobileSMS": "Messages"
        ]
        
        return demoApps[bundleId]
    }
}

// MARK: - Clean App Limit Slider (for Settings)
struct AppLimitSlider: View {
    let appName: String
    let bundleIdentifier: String
    let currentUsage: TimeInterval
    @Binding var timeLimit: Double // in hours
    let isDisabled: Bool
    let onDisableToggle: (Bool) -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(appName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(isDisabled ? .secondary : .primary)
                
                Spacer()
                
                Text("Used: \(formatDuration(currentUsage))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // NEW: X button for app deletion
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if isDisabled {
                // Disabled State
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("App Disabled")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                        Spacer()
                    }
                    
                    Button(action: {
                        onDisableToggle(false)
                    }) {
                        Text("Enable App")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                }
            } else {
                // Enabled State
                VStack(spacing: 8) {
                    HStack {
                        Slider(value: $timeLimit, in: 0.25...8.0, step: 0.25)
                        
                        Text("Limit: \(formatLimitDuration(timeLimit))")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .frame(width: 80, alignment: .leading)
                    }
                    
                    Button(action: {
                        onDisableToggle(true)
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.red)
                            Text("Disable App")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(isDisabled ? Color(.systemGray5) : Color(.systemGray6))
        .cornerRadius(12)
        .opacity(isDisabled ? 0.7 : 1.0)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatLimitDuration(_ hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        
        if h > 0 {
            return "\(h)h \(m)m"
        } else {
            return "\(m)m"
        }
    }
}

struct CurrentDeviceRow: View {
    let device: PairedChildDevice
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.childName)
                    .font(.headline)
                
                Text(device.deviceName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Circle()
                        .fill(device.isOnline ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    
                    Text(device.isOnline ? "Online" : "Offline")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("• Last sync: \(formatLastSyncTime(device.lastSyncAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
    }
    
    private func formatLastSyncTime(_ timestamp: Timestamp) -> String {
        let date = timestamp.dateValue()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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

// MARK: - Day Toggle Button for Bedtime Settings
struct DayToggleButton: View {
    let day: Int
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    
    private var dayName: String {
        switch day {
        case 1: return "S"
        case 2: return "M"
        case 3: return "T"
        case 4: return "W"
        case 5: return "T"
        case 6: return "F"
        case 7: return "S"
        default: return ""
        }
    }
    
    var body: some View {
        Button(action: {
            onToggle(!isSelected)
        }) {
            Text(dayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(isSelected ? Color.purple : Color(.systemGray5))
                .cornerRadius(16)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthenticationManager())
}
