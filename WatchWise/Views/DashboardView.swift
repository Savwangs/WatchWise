//
//  DashboardView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//
import SwiftUI
import Charts
import FirebaseAuth

// DEMO DATA START - Extended app usage data to include Messages
extension ScreenTimeManager {
    static let demoAppUsages: [AppUsage] = [
        AppUsage(appName: "Instagram", bundleIdentifier: "com.burbn.instagram", duration: 4500, timestamp: Date().addingTimeInterval(-3600)), // 1h 15m
        AppUsage(appName: "TikTok", bundleIdentifier: "com.zhiliaoapp.musically", duration: 2700, timestamp: Date().addingTimeInterval(-7200)), // 45m
        AppUsage(appName: "YouTube", bundleIdentifier: "com.google.ios.youtube", duration: 3600, timestamp: Date().addingTimeInterval(-5400)), // 1h
        AppUsage(appName: "Safari", bundleIdentifier: "com.apple.mobilesafari", duration: 1200, timestamp: Date().addingTimeInterval(-1800)), // 20m
        AppUsage(appName: "Snapchat", bundleIdentifier: "com.toyopagroup.picaboo", duration: 1800, timestamp: Date().addingTimeInterval(-900)), // 30m
        AppUsage(appName: "Messages", bundleIdentifier: "com.apple.MobileSMS", duration: 900, timestamp: Date().addingTimeInterval(-600)) // 15m
    ]
}
// DEMO DATA END

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var screenTimeManager = ScreenTimeManager()
    @State private var showingError = false
    @State private var lastRefresh = Date()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Header
                    HeaderView(
                        lastRefresh: lastRefresh,
                        isLoading: screenTimeManager.isLoading,
                        onRefresh: refreshData
                    )
                    
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
    }
    
    // MARK: - Data Loading Methods
    private func loadInitialData() {
        guard let parentId = authManager.currentUser?.id else {
            screenTimeManager.errorMessage = "Authentication required. Please log in again."
            return
        }
        
        screenTimeManager.loadTodayScreenTime(parentId: parentId)
    }
    
    private func refreshData() {
        guard let parentId = authManager.currentUser?.id else {
            screenTimeManager.errorMessage = "Authentication required. Please log in again."
            return
        }
        
        lastRefresh = Date()
        screenTimeManager.refreshData(parentId: parentId)
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
    let onRefresh: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Your Child's Usage Today")
                    .font(.title2)
                    .fontWeight(.bold)
                
                HStack {
                    Text(Date(), style: .date)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if !isLoading {
                        Text("• Last updated: \(lastRefresh, style: .time)")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
        .padding(.top, 10)
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
                HourlyBreakdownCard(hourlyData: screenTimeData.hourlyBreakdown)
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
    
    // DEMO DATA START - App colors for consistent visualization
    private let appColors: [String: Color] = [
        "Instagram": .purple,
        "TikTok": .black,
        "YouTube": .red,
        "Safari": .blue,
        "Messages": .green,
        "Snapchat": .yellow
    ]
    // DEMO DATA END
    
    // Sort apps by duration to ensure all apps including Messages are shown
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

// MARK: - Hourly Breakdown Card
struct HourlyBreakdownCard: View {
    let hourlyData: [Int: TimeInterval]
    
    // DEMO DATA START - App colors for consistent visualization
    private let appColors: [String: Color] = [
        "Instagram": .purple,
        "TikTok": .black,
        "YouTube": .red,
        "Safari": .blue,
        "Messages": .green,
        "Snapchat": .yellow
    ]
    
    // DEMO DATA - Top 6 apps for individual bar chart
    private let demoTopApps: [(name: String, duration: TimeInterval)] = [
        ("Instagram", 4500),    // 1h 15m
        ("YouTube", 3600),      // 1h
        ("TikTok", 2700),       // 45m
        ("Snapchat", 1800),     // 30m
        ("Safari", 1200),       // 20m
        ("Messages", 900)       // 15m
    ]
    // DEMO DATA END
    
    // DEMO DATA START - Time-based usage data for chart
    private var timeBasedAppData: [(timeRange: String, apps: [(appName: String, duration: TimeInterval)])] {
        return [
            (timeRange: "12a", apps: []),
            (timeRange: "4a", apps: []),
            (timeRange: "8a", apps: [
                (appName: "Instagram", duration: 1800) // 30m
            ]),
            (timeRange: "12p", apps: [
                (appName: "TikTok", duration: 2700),    // 45m
                (appName: "YouTube", duration: 3600),   // 1h
                (appName: "Safari", duration: 1200)     // 20m
            ]),
            (timeRange: "4p", apps: [
                (appName: "Instagram", duration: 2700), // 45m
                (appName: "Snapchat", duration: 1800)   // 30m
            ]),
            (timeRange: "8p", apps: [
                (appName: "Messages", duration: 900)    // 15m
            ]),
            (timeRange: "11:59p", apps: [])
        ]
    }
    // DEMO DATA END
    
    // DEMO DATA START - Flattened data for Chart performance
    private var flattenedTimeData: [(id: String, timeRange: String, appName: String, duration: TimeInterval)] {
        var result: [(id: String, timeRange: String, appName: String, duration: TimeInterval)] = []
        
        for timeData in timeBasedAppData {
            for (index, app) in timeData.apps.enumerated() {
                result.append((
                    id: "\(timeData.timeRange)-\(app.appName)-\(index)",
                    timeRange: timeData.timeRange,
                    appName: app.appName,
                    duration: app.duration
                ))
            }
        }
        
        return result
    }
    // DEMO DATA END
    
    @State private var selectedHour: Int? = nil
    @State private var hoveredData: (hour: Int, apps: [String: TimeInterval])? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.green)
                Text("App Usage Overview")
                    .font(.headline)
                Spacer()
            }
            
            if hourlyData.isEmpty {
                Text("No hourly data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical)
            } else {
                if #available(iOS 16.0, *) {
                    Chart(flattenedTimeData, id: \.id) { data in
                        BarMark(
                            x: .value("Time", data.timeRange),
                            y: .value("Minutes", data.duration / 60.0)
                        )
                        .foregroundStyle(appColors[data.appName] ?? .gray)
                        .cornerRadius(4)
                    }
                    .frame(height: 200)
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let timeRange = value.as(String.self) {
                                    Text(timeRange)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                            }
                            AxisTick()
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: [0, 30, 60, 90, 120]) { value in
                            AxisValueLabel {
                                if let minutes = value.as(Double.self) {
                                    if minutes >= 60 {
                                        let hours = Int(minutes / 60)
                                        Text("\(hours)h")
                                            .font(.caption2)
                                    } else if minutes == 0 {
                                        Text("0m")
                                            .font(.caption2)
                                    } else {
                                        Text("\(Int(minutes))m")
                                            .font(.caption2)
                                    }
                                }
                            }
                            AxisTick()
                            AxisGridLine()
                        }
                    }
                    .chartYScale(domain: 0...120) // 0 to 2 hours (120 minutes)
                    .chartBackground { chartProxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { location in
                                    // Tap gesture preserved for future functionality
                                    selectedHour = selectedHour == nil ? 0 : nil
                                }
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Text("App usage breakdown:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // DEMO DATA START - iOS 15 fallback time-based view
                        ForEach(timeBasedAppData.filter { !$0.apps.isEmpty }, id: \.timeRange) { timeData in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(timeData.timeRange)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                
                                ForEach(Array(timeData.apps.enumerated()), id: \.offset) { index, app in
                                    HStack {
                                        Circle()
                                            .fill(appColors[app.appName] ?? .gray)
                                            .frame(width: 6, height: 6)
                                        
                                        Text(app.appName)
                                            .font(.caption2)
                                            .frame(width: 60, alignment: .leading)
                                        
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(appColors[app.appName] ?? .gray)
                                            .frame(width: CGFloat(app.duration / 60.0) * 1.5, height: 6)
                                        
                                        Spacer()
                                        
                                        Text(formatDuration(app.duration))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        // DEMO DATA END
                    }
                    .frame(height: 200)
                }
            }
            
            // App legend
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                // DEMO DATA START - Legend showing all apps used throughout the day
                ForEach(Array(demoTopApps.enumerated()), id: \.offset) { index, app in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(appColors[app.name] ?? .gray)
                            .frame(width: 8, height: 8)
                        Text(app.name)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
                // DEMO DATA END
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // Convert location to hour for tap gesture - PRESERVED FROM ORIGINAL
    private func getHourFromLocation(_ location: CGPoint, geometry: GeometryProxy, chartProxy: ChartProxy) -> Int? {
        let xPosition = location.x
        let chartWidth = geometry.size.width
        let hourWidth = chartWidth / 24
        let hour = Int(xPosition / hourWidth)
        return hour >= 0 && hour <= 23 ? hour : nil
    }
    
    // PRESERVED FROM ORIGINAL - Show all 24 hours (0-23) with data or 0 minutes
    // Create stacked bar data for each hour with per-app breakdown
    private var fullDayHourlyData: [(hour: Int, apps: [(app: String, minutes: Double)])] {
        var result: [(hour: Int, apps: [(app: String, minutes: Double)])] = []
        
        // DEMO DATA START - Sample per-app hourly data (Remove in production)
        let demoAppHourlyData: [Int: [String: TimeInterval]] = [
            8: ["Instagram": 1800, "Messages": 600], // 30min Instagram, 10min Messages
            9: ["TikTok": 2700, "Safari": 900], // 45min TikTok, 15min Safari
            10: ["YouTube": 3600, "Messages": 300], // 1h YouTube, 5min Messages
            11: ["Instagram": 900, "Snapchat": 1200], // 15min Instagram, 20min Snapchat
            12: ["Safari": 1800], // 30min Safari
            13: ["TikTok": 1800, "Messages": 600], // 30min TikTok, 10min Messages
            14: ["YouTube": 2700], // 45min YouTube
            15: ["Instagram": 3600], // 1h Instagram
            16: ["Safari": 1200, "Messages": 300], // 20min Safari, 5min Messages
            17: ["TikTok": 2400], // 40min TikTok
            18: ["YouTube": 1800, "Instagram": 1200], // 30min YouTube, 20min Instagram
            19: ["Messages": 900, "Snapchat": 600], // 15min Messages, 10min Snapchat
            20: ["TikTok": 1800], // 30min TikTok
            21: ["Instagram": 2400, "Messages": 300] // 40min Instagram, 5min Messages
        ]
        // DEMO DATA END
        
        for hour in 0...23 {
            var apps: [(app: String, minutes: Double)] = []
            
            if let appData = demoAppHourlyData[hour] {
                var runningTotal = 0.0
                for (app, duration) in appData.sorted(by: { $0.value > $1.value }) {
                    let minutes = duration / 60.0
                    apps.append((app: app, minutes: runningTotal + minutes))
                    runningTotal += minutes
                }
            }
            
            // If no data for this hour, add empty entry
            if apps.isEmpty {
                apps.append((app: "None", minutes: 0))
            }
            
            result.append((hour: hour, apps: apps))
        }
        
        return result
    }
    
    // PRESERVED FROM ORIGINAL - For iOS 15 fallback - only show hours with data
    private var nonZeroHourlyData: [(hour: Int, minutes: Double)] {
        return hourlyData
            .map { (hour: $0.key, minutes: $0.value / 60.0) }
            .filter { $0.minutes > 0 }
            .sorted { $0.hour < $1.hour }
    }
    
    // PRESERVED FROM ORIGINAL - Format hour labels
    private func formatHourLabel(_ hour: Int) -> String {
        if hour == 0 {
            return "12a"
        } else if hour < 12 {
            return "\(hour)a"
        } else if hour == 12 {
            return "12p"
        } else {
            return "\(hour - 12)p"
        }
    }
    
    // PRESERVED FROM ORIGINAL - Format minutes labels
    private func formatMinutesLabel(_ minutes: Double) -> String {
        if minutes >= 60 {
            let hours = Int(minutes / 60)
            let remainingMinutes = Int(minutes) % 60
            if remainingMinutes > 0 {
                return "\(hours)h \(remainingMinutes)m"
            } else {
                return "\(hours)h"
            }
        } else {
            return "\(Int(minutes))m"
        }
    }
    
    // Duration formatting function
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

#Preview {
    DashboardView()
        .environmentObject(AuthenticationManager())
}
