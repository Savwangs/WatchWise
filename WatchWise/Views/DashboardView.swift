//
//  DashboardView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//
import SwiftUI
import Charts
import FirebaseAuth
import FirebaseFirestore

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var screenTimeManager = ScreenTimeManager()
    @StateObject private var pairingManager = PairingManager.shared
    @State private var showingError = false
    @State private var lastRefresh = Date()
    @State private var selectedDeviceId: String?
    @State private var showingOfflineAlert = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Header
                    HeaderView(
                        lastRefresh: lastRefresh,
                        isLoading: screenTimeManager.isLoading,
                        pairedDevices: pairingManager.pairedChildren,
                        selectedDeviceId: $selectedDeviceId,
                        onRefresh: refreshData,
                        isOffline: screenTimeManager.isOffline,
                        lastSyncTime: screenTimeManager.lastSyncTime
                    )
                    
                    // Offline Alert
                    if screenTimeManager.isOffline {
                        OfflineAlertView()
                    }
                    
                    // Error State
                    if let errorMessage = screenTimeManager.errorMessage {
                        ErrorView(
                            message: errorMessage,
                            onDismiss: {
                                screenTimeManager.clearError()
                            },
                            onRetry: refreshData
                        )
                    }
                    
                    // Loading State
                    if screenTimeManager.isLoading {
                        LoadingView()
                    }
                    // No Data State
                    else if screenTimeManager.todayScreenTime == nil && !screenTimeManager.isLoading {
                        NoDataView(onRefresh: refreshData)
                    }
                    // Data Display
                    else if let screenTimeData = screenTimeManager.todayScreenTime {
                        DataDisplayView(screenTimeData: screenTimeData)
                    }
                }
                .padding(.bottom, 100) // Tab bar clearance
            }
            .navigationBarHidden(true)
            .refreshable {
                await refreshDataAsync()
            }
        }
        .onAppear {
            Task {
                await pairingManager.loadPairedChildren()
            }
            // Load previously selected device
            if selectedDeviceId == nil {
                selectedDeviceId = UserDefaults.standard.string(forKey: "selectedDeviceId")
            }
            loadInitialData()
        }
        .onChange(of: selectedDeviceId) { newDeviceId in
            // Save selected device to UserDefaults for SettingsView
            if let deviceId = newDeviceId {
                UserDefaults.standard.set(deviceId, forKey: "selectedDeviceId")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedDeviceId")
            }
            loadInitialData()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                screenTimeManager.clearError()
            }
        } message: {
            Text(screenTimeManager.errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: screenTimeManager.errorMessage) { errorMessage in
            showingError = errorMessage != nil
        }
        .onDisappear {
            screenTimeManager.disconnect()
        }
    }
    
    // MARK: - Data Loading Methods
    private func loadInitialData() {
        guard let parentId = authManager.currentUser?.id else {
            screenTimeManager.errorMessage = "Authentication required. Please log in again."
            return
        }
        
        // If no device is selected and we have paired devices, select the first one
        if selectedDeviceId == nil && !pairingManager.pairedChildren.isEmpty {
            selectedDeviceId = pairingManager.pairedChildren.first?.childUserId
        }
        
        // Load data for selected device
        screenTimeManager.loadTodayScreenTime(parentId: parentId, childDeviceId: selectedDeviceId)
    }
    
    private func refreshData() {
        guard let parentId = authManager.currentUser?.id else {
            screenTimeManager.errorMessage = "Authentication required. Please log in again."
            return
        }
        
        lastRefresh = Date()
        
        screenTimeManager.refreshData(parentId: parentId, childDeviceId: selectedDeviceId)
    }
    
    private func refreshDataAsync() async {
        await MainActor.run {
            refreshData()
        }
    }
}

// MARK: - Header View
struct HeaderView: View {
    let lastRefresh: Date
    let isLoading: Bool
    let pairedDevices: [PairedChildDevice]
    @Binding var selectedDeviceId: String?
    let onRefresh: () -> Void
    let isOffline: Bool
    let lastSyncTime: Date?
    
    @State private var showingDevicePicker = false
    
    var selectedDevice: PairedChildDevice? {
        pairedDevices.first { $0.childUserId == selectedDeviceId }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Device Selector
            if !pairedDevices.isEmpty {
                HStack {
                    Button(action: {
                        showingDevicePicker = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "iphone")
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedDevice?.childName ?? "Select Device")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text(selectedDevice?.deviceName ?? "No device selected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.down")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
            }
            
            // Usage Header
            HStack {
                VStack(alignment: .leading) {
                    Text("\(selectedDevice?.childName ?? "Child")'s Usage Today")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text(Date(), style: .date)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if !isLoading {
                            if isOffline {
                                Text("• Offline mode")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else if let syncTime = lastSyncTime {
                                Text("• Last updated: \(syncTime, style: .time)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("• Last updated: \(lastRefresh, style: .time)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .rotationEffect(.degrees(isLoading ? 360 : 0))
                        .animation(
                            isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                            value: isLoading
                        )
                }
                .disabled(isLoading)
            }
            .padding(.horizontal)
        }
        .padding(.top, 10)
        .sheet(isPresented: $showingDevicePicker) {
            DevicePickerView(
                pairedDevices: pairedDevices,
                selectedDeviceId: $selectedDeviceId
            )
        }
    }
}

// MARK: - Offline Alert View
struct OfflineAlertView: View {
    var body: some View {
        HStack {
            Image(systemName: "wifi.slash")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Offline Mode")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
                
                Text("Showing cached data. Connect to internet for live updates.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Error View
struct ErrorView: View {
    let message: String
    let onDismiss: () -> Void
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                
                VStack(alignment: .leading) {
                    Text("Unable to Load Data")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Button("✕", action: onDismiss)
                    .foregroundColor(.secondary)
            }
            
            Button("Try Again") {
                onRetry()
            }
            .foregroundColor(.blue)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Loading View
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading screen time data...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

// MARK: - No Data View
struct NoDataView: View {
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("No Screen Time Data")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Make sure your child's device is paired and actively collecting screen time data.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Refresh") {
                onRefresh()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding()
    }
}

// MARK: - Data Display View
struct DataDisplayView: View {
    let screenTimeData: ScreenTimeData
    
    var body: some View {
        VStack(spacing: 20) {
            // Total Screen Time Card
            ScreenTimeCard(
                title: "Total Screen Time",
                value: formatDuration(screenTimeData.totalScreenTime),
                icon: "clock.fill",
                color: .blue
            )
            
            // Top Apps Card (only show if we have app data)
            if !screenTimeData.appUsages.isEmpty {
                TopAppsCard(appUsages: screenTimeData.appUsages)
            }
            
            // Hourly Breakdown Chart (only show if we have hourly data)
            if !screenTimeData.hourlyBreakdown.isEmpty {
                AppUsageTimelineCard(hourlyData: screenTimeData.hourlyBreakdown)
            }
            
            // Data Collection Info
            DataInfoCard(lastUpdated: screenTimeData.date)
        }
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
}

// MARK: - Screen Time Card
struct ScreenTimeCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Top Apps Card
struct TopAppsCard: View {
    let appUsages: [AppUsage]
    
    // App colors for consistent visualization
    private let appColors: [String: Color] = [
        "Instagram": .purple,
        "TikTok": .black,
        "YouTube": .red,
        "Safari": .blue,
        "Messages": .green,
        "Snapchat": .yellow,
        "WhatsApp": .green,
        "Facebook": .blue,
        "Twitter": .blue,
        "Discord": .purple,
        "Reddit": .orange,
        "Netflix": .red,
        "Spotify": .green,
        "Minecraft": .green,
        "Roblox": .red,
        "Fortnite": .purple,
        "Call of Duty": .orange,
        "PUBG": .yellow,
        "Genshin Impact": .blue,
        "Among Us": .purple
    ]
    
    // Sort apps by duration to ensure all apps are shown
    private var sortedAppUsages: [AppUsage] {
        return appUsages.sorted { $0.duration > $1.duration }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "app.fill")
                    .foregroundColor(.orange)
                Text("Top Apps")
                    .font(.headline)
                Spacer()
            }
            
            if appUsages.isEmpty {
                Text("No app usage data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical)
            } else {
                ForEach(Array(sortedAppUsages.prefix(6).enumerated()), id: \.offset) { index, usage in
                    HStack {
                        Circle()
                            .fill(appColors[usage.appName] ?? .gray)
                            .frame(width: 12, height: 12)
                        
                        Text(usage.appName)
                            .font(.body)
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text(formatDuration(usage.duration))
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
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
}

// MARK: - App Usage Timeline Card
struct AppUsageTimelineCard: View {
    let hourlyData: [Int: TimeInterval]
    
    // App colors for consistent visualization
    private let appColors: [String: Color] = [
        "Instagram": .purple,
        "TikTok": .black,
        "YouTube": .red,
        "Safari": .blue,
        "Messages": .green,
        "Snapchat": .yellow,
        "WhatsApp": .green,
        "Facebook": .blue,
        "Twitter": .blue,
        "Discord": .purple,
        "Reddit": .orange,
        "Netflix": .red,
        "Spotify": .green,
        "Minecraft": .green,
        "Roblox": .red,
        "Fortnite": .purple,
        "Call of Duty": .orange,
        "PUBG": .yellow,
        "Genshin Impact": .blue,
        "Among Us": .purple
    ]
    
    // Generate timeline data from hourly breakdown
    private var timelineData: [(hour: Int, duration: TimeInterval)] {
        return hourlyData.sorted { $0.key < $1.key }.map { (hour: $0.key, duration: $0.value) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.blue)
                Text("Hourly Usage")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal)
            
            // Timeline Chart
            if timelineData.isEmpty {
                Text("No hourly data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                Chart {
                    ForEach(timelineData, id: \.hour) { item in
                        BarMark(
                            x: .value("Hour", formatHour(item.hour)),
                            y: .value("Duration", item.duration / 60) // Convert to minutes
                        )
                        .foregroundStyle(.blue.gradient)
                        .cornerRadius(4)
                    }
                }
                .frame(height: 200)
                .padding()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date).lowercased()
    }
}

// MARK: - Data Info Card
struct DataInfoCard: View {
    let lastUpdated: Date
    
    var body: some View {
        HStack {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Data Collection Active")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Last updated: \(lastUpdated, style: .time)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBlue).opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Device Picker View
struct DevicePickerView: View {
    let pairedDevices: [PairedChildDevice]
    @Binding var selectedDeviceId: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(pairedDevices) { device in
                    Button(action: {
                        selectedDeviceId = device.childUserId
                        dismiss()
                    }) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(device.isOnline ? Color.green : Color.gray)
                                    .frame(width: 12, height: 12)
                                
                                Image(systemName: "iphone")
                                    .font(.system(size: 20))
                                    .foregroundColor(.blue)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.childName)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text(device.deviceName)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 8) {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(device.isOnline ? Color.green : Color.gray)
                                            .frame(width: 6, height: 6)
                                        
                                        Text(device.connectionStatus)
                                            .font(.caption)
                                            .foregroundColor(device.isOnline ? .green : .gray)
                                    }
                                    
                                    Text("Last sync: \(formatLastSyncTime(device.lastSyncAt))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if device.childUserId == selectedDeviceId {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .navigationTitle("Select Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatLastSyncTime(_ timestamp: Timestamp) -> String {
        let date = timestamp.dateValue()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthenticationManager())
}
