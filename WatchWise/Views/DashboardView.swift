//
//  DashboardView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var screenTimeManager = ScreenTimeManager()
    @StateObject private var pairingManager = PairingManager.shared
    @StateObject private var appRestrictionManager = AppRestrictionManager()
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var messagingManager = MessagingManager.shared
    @StateObject private var appDeletionManager = AppDeletionManager()
    @StateObject private var heartbeatManager = HeartbeatManager()
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
                        
                        // Real-time Status
                        RealTimeStatusView()
                        
                        // Daily Reset Info
                        DailyResetInfoView()
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
            setupStage3Features()
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
    
    // MARK: - Stage 3 Features Setup
    private func setupStage3Features() {
        guard let currentUser = authManager.currentUser else { return }
        
        // Setup notifications
        notificationManager.setup()
        notificationManager.connect(userId: currentUser.id)
        
        // Setup messaging
        if let childId = selectedDeviceId ?? pairingManager.pairedChildren.first?.childUserId {
            messagingManager.connect(parentId: currentUser.id, childId: childId)
        }
        
        // Setup app deletion monitoring
        appDeletionManager.loadDeletedApps()
        
        // Setup heartbeat monitoring
        heartbeatManager.startMonitoring(parentId: currentUser.id)
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
            
            // App Restrictions Card
            AppRestrictionsCard()
            
            // App Usage Timeline (only show if we have app data with usage ranges)
            if !screenTimeData.appUsages.isEmpty {
                AppUsageTimelineCard(appUsages: screenTimeData.appUsages)
            }
            
            // Notifications Card
            NotificationsCard()
            
            // Messages Card
            MessagesCard()
            
            // App Deletion Card
            AppDeletionCard()
            
            // Device Status Card
            DeviceStatusCard()
            
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
    let appUsages: [AppUsage]
    @State private var selectedApp: AppUsage?
    @State private var showingAppDetail = false
    
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
    
    // Get apps with usage ranges
    private var appsWithRanges: [AppUsage] {
        return appUsages.filter { $0.usageRanges != nil && !($0.usageRanges?.isEmpty ?? true) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.blue)
                Text("App Usage Timeline")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal)
            
            // Timeline Content
            if appsWithRanges.isEmpty {
                Text("No detailed usage data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(appsWithRanges, id: \.bundleIdentifier) { app in
                            AppTimelineRow(
                                app: app,
                                color: appColors[app.appName] ?? .gray,
                                onTap: {
                                    selectedApp = app
                                    showingAppDetail = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 400)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        .sheet(isPresented: $showingAppDetail) {
            if let app = selectedApp {
                AppDetailView(app: app, color: appColors[app.appName] ?? .gray)
            }
        }
    }
}

// MARK: - App Timeline Row
struct AppTimelineRow: View {
    let app: AppUsage
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // App Header
                HStack(spacing: 12) {
                    // App Icon/Color
                    Circle()
                        .fill(color)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "app.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 16))
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.appName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Total: \(formatDuration(app.duration))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                
                // Visual Timeline
                if let usageRanges = app.usageRanges, !usageRanges.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        // Time labels
                        HStack {
                            Text("6 AM")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("12 PM")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("6 PM")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("12 AM")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        // Timeline bar
                        ZStack(alignment: .leading) {
                            // Background timeline
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 20)
                                .cornerRadius(10)
                            
                            // Usage segments
                            ForEach(usageRanges, id: \.sessionId) { range in
                                TimelineSegment(range: range, color: color)
                            }
                        }
                        .frame(height: 20)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
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

// MARK: - Timeline Segment
struct TimelineSegment: View {
    let range: AppUsageRange
    let color: Color
    
    var body: some View {
        let startHour = Calendar.current.component(.hour, from: range.startTime)
        let startMinute = Calendar.current.component(.minute, from: range.startTime)
        let endHour = Calendar.current.component(.hour, from: range.endTime)
        let endMinute = Calendar.current.component(.minute, from: range.endTime)
        
        // Calculate position and width (18 hours from 6 AM to 12 AM)
        let startPosition = max(0, (Double(startHour) - 6.0 + Double(startMinute) / 60.0) / 18.0)
        let endPosition = min(1.0, (Double(endHour) - 6.0 + Double(endMinute) / 60.0) / 18.0)
        let width = endPosition - startPosition
        
        Rectangle()
            .fill(color)
            .frame(width: max(4, UIScreen.main.bounds.width * 0.7 * width))
            .offset(x: UIScreen.main.bounds.width * 0.35 * startPosition)
            .cornerRadius(8)
    }
}

// MARK: - App Detail View
struct AppDetailView: View {
    let app: AppUsage
    let color: Color
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // App Header
                    HStack(spacing: 16) {
                        Circle()
                            .fill(color)
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "app.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 24))
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.appName)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Total Usage: \(formatDuration(app.duration))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Usage Sessions
                    if let usageRanges = app.usageRanges, !usageRanges.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Usage Sessions")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            LazyVStack(spacing: 8) {
                                ForEach(usageRanges.sorted { $0.startTime > $1.startTime }, id: \.sessionId) { range in
                                    UsageSessionRow(range: range)
                                }
                            }
                            
                            // Session Summary
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Session Summary")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Total Sessions")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Text("\(usageRanges.count)")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Average Session")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Text(formatDuration(app.duration / Double(usageRanges.count)))
                                            .font(.title2)
                                            .fontWeight(.bold)
                                    }
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .padding(.horizontal)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Usage Sessions")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            Text("No detailed session data available")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("App Details")
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

// MARK: - Usage Session Row
struct UsageSessionRow: View {
    let range: AppUsageRange
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(range.formattedRange)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Duration: \(formatDuration(range.duration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "clock")
                .foregroundColor(.blue)
                .font(.caption)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
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

// MARK: - App Restrictions Card
struct AppRestrictionsCard: View {
    @StateObject private var appRestrictionManager = AppRestrictionManager()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.red)
                Text("App Restrictions")
                    .font(.headline)
                Spacer()
            }
            
            if appRestrictionManager.currentRestrictions.isEmpty {
                Text("No app restrictions set")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical)
            } else {
                ForEach(Array(appRestrictionManager.currentRestrictions.values.prefix(5)), id: \.id) { restriction in
                    AppRestrictionRow(restriction: restriction)
                }
                
                if appRestrictionManager.currentRestrictions.count > 5 {
                    Text("+ \(appRestrictionManager.currentRestrictions.count - 5) more restrictions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - App Restriction Row
struct AppRestrictionRow: View {
    let restriction: AppRestriction
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(restriction.bundleId.components(separatedBy: ".").last ?? restriction.bundleId)
                    .font(.body)
                    .fontWeight(.medium)
                
                HStack {
                    Text("Used: \(restriction.formattedDailyUsage)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Limit: \(restriction.formattedTimeLimit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Usage Progress Bar
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: restriction.usagePercentage)
                    .progressViewStyle(LinearProgressViewStyle(tint: restriction.usagePercentage > 0.8 ? .red : .blue))
                    .frame(width: 60, height: 4)
                
                Text("\(Int(restriction.usagePercentage * 100))%")
                    .font(.caption2)
                    .foregroundColor(restriction.usagePercentage > 0.8 ? .red : .secondary)
            }
            
            // Status Icon
            Image(systemName: restriction.isDisabled ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(restriction.isDisabled ? .red : .green)
                .font(.title3)
        }
        .padding(.vertical, 4)
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

// MARK: - Real-time Status View
struct RealTimeStatusView: View {
    @StateObject private var deviceActivityManager = DeviceActivityDataManager()
    @State private var isDataStale = false
    
    var body: some View {
        HStack {
            Image(systemName: isDataStale ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(isDataStale ? .orange : .green)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Real-time Monitoring")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(isDataStale ? "Data may be stale" : "Data updates in background")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let lastUpdate = deviceActivityManager.lastUpdateTime {
                Text("Updated \(formatTimeAgo(lastUpdate))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isDataStale ? .orange : .green)
            }
        }
        .padding()
        .background(Color(isDataStale ? .systemOrange : .systemGreen).opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
        .onAppear {
            checkDataStatus()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            checkDataStatus()
        }
    }
    
    private func checkDataStatus() {
        isDataStale = deviceActivityManager.isDataStale()
    }
    
    private func formatTimeAgo(_ date: Date) -> String {
        let timeInterval = Date().timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h ago"
        }
    }
}

// MARK: - Daily Reset Info View
struct DailyResetInfoView: View {
    var body: some View {
        HStack {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Reset")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Screen time resets daily at midnight")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(timeUntilReset)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.green)
        }
        .padding()
        .background(Color(.systemGreen).opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    private var timeUntilReset: String {
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        let timeInterval = tomorrow.timeIntervalSince(now)
        
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60
        
        return "\(hours)h \(minutes)m"
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

// MARK: - Stage 3 Dashboard Cards

// MARK: - Notifications Card
struct NotificationsCard: View {
    @StateObject private var notificationManager = NotificationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundColor(.orange)
                
                Text("Recent Notifications")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if notificationManager.unreadCount > 0 {
                    Text("\(notificationManager.unreadCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.red)
                        .clipShape(Circle())
                }
            }
            
            if notificationManager.notifications.isEmpty {
                Text("No notifications yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(notificationManager.notifications.prefix(3)) { notification in
                        HStack {
                            Image(systemName: notification.type.icon)
                                .foregroundColor(Color(notification.type.color))
                                .frame(width: 16)
                            
                            Text(notification.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            if !notification.isRead {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 6, height: 6)
                            }
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
}

// MARK: - Messages Card
struct MessagesCard: View {
    @StateObject private var messagingManager = MessagingManager.shared
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "message.fill")
                    .foregroundColor(.blue)
                
                Text("Recent Messages")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if let lastMessage = messagingManager.getLastMessage() {
                    Text(lastMessage.formattedTimestamp)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if messagingManager.messages.isEmpty {
                Text("No messages yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(messagingManager.messages.suffix(3)) { message in
                        HStack {
                            Image(systemName: message.isFromParent ? "person.fill" : "person.crop.circle")
                                .foregroundColor(message.isFromParent ? .blue : .green)
                                .frame(width: 16)
                            
                            Text(message.text)
                                .font(.subheadline)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            if !message.isRead && message.receiverId == authManager.currentUser?.id {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 6, height: 6)
                            }
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
}

// MARK: - App Deletion Card
struct AppDeletionCard: View {
    @StateObject private var appDeletionManager = AppDeletionManager()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "app.badge.minus")
                    .foregroundColor(.purple)
                
                Text("App Deletions")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if !appDeletionManager.deletedApps.isEmpty {
                    Text("\(appDeletionManager.deletedApps.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.purple)
                        .clipShape(Circle())
                }
            }
            
            if appDeletionManager.deletedApps.isEmpty {
                Text("No apps deleted recently")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(appDeletionManager.deletedApps.prefix(3)) { deletedApp in
                        HStack {
                            Image(systemName: "app.badge.minus")
                                .foregroundColor(.purple)
                                .frame(width: 16)
                            
                            Text(deletedApp.appName)
                                .font(.subheadline)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(deletedApp.formattedDeletedAt)
                                .font(.caption)
                                .foregroundColor(.secondary)
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
}

// MARK: - Device Status Card
struct DeviceStatusCard: View {
    @StateObject private var heartbeatManager = HeartbeatManager()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .foregroundColor(.blue)
                
                Text("Device Status")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if !heartbeatManager.childDevices.isEmpty {
                    let onlineCount = heartbeatManager.childDevices.filter { $0.status == .online }.count
                    let totalCount = heartbeatManager.childDevices.count
                    Text("\(onlineCount)/\(totalCount) Online")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            if heartbeatManager.childDevices.isEmpty {
                Text("No devices connected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(heartbeatManager.childDevices) { device in
                        HStack {
                            Circle()
                                .fill(device.status == .online ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            
                            Text(device.childName)
                                .font(.subheadline)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(device.statusDescription)
                                .font(.caption)
                                .foregroundColor(device.status == .online ? .green : .red)
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
}

#Preview {
    DashboardView()
        .environmentObject(AuthenticationManager())
}
