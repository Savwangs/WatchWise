//
//  DashboardView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//
import SwiftUI
import Charts
import FirebaseAuth

// DEMO DATA START - Extended app usage data to include Reddit
extension ScreenTimeManager {
    static let demoAppUsages: [AppUsage] = [
        AppUsage(appName: "Instagram", bundleIdentifier: "com.burbn.instagram", duration: 4500, timestamp: Date().addingTimeInterval(-3600), usageRanges: nil), // 1h 15m (30m + 45m from graph)
        AppUsage(appName: "TikTok", bundleIdentifier: "com.zhiliaoapp.musically", duration: 2700, timestamp: Date().addingTimeInterval(-7200), usageRanges: nil), // 45m (matches graph)
        AppUsage(appName: "YouTube", bundleIdentifier: "com.google.ios.youtube", duration: 3600, timestamp: Date().addingTimeInterval(-5400), usageRanges: nil), // 1h (20m + 40m from graph)
        AppUsage(appName: "Snapchat", bundleIdentifier: "com.toyopagroup.picaboo", duration: 1800, timestamp: Date().addingTimeInterval(-900), usageRanges: nil), // 30m (matches graph)
        AppUsage(appName: "Safari", bundleIdentifier: "com.apple.mobilesafari", duration: 1200, timestamp: Date().addingTimeInterval(-1800), usageRanges: nil), // 20m (matches graph)
        AppUsage(appName: "Reddit", bundleIdentifier: "com.reddit.Reddit", duration: 900, timestamp: Date().addingTimeInterval(-600), usageRanges: nil) // 15m (matches graph)
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
        // DEMO DATA - Use demo data for demonstration
        loadDemoData()
    }
    
    private func refreshData() {
        // DEMO DATA - Refresh demo data
        lastRefresh = Date()
        loadDemoData()
    }
    
    private func loadDemoData() {
        // Create demo screen time data
        let demoScreenTimeData = ScreenTimeData(
            id: "demo",
            deviceId: "demo-device",
            date: Date(),
            totalScreenTime: 14700, // 4h 5m total
            appUsages: ScreenTimeManager.demoAppUsages,
            hourlyBreakdown: [
                8: 1800,   // 8 AM: 30 min
                12: 3600,  // 12 PM: 1 hour
                14: 2400,  // 2 PM: 40 min
                16: 1200,  // 4 PM: 20 min
                18: 2700,  // 6 PM: 45 min
                20: 2700   // 8 PM: 45 min
            ]
        )
        
        screenTimeManager.todayScreenTime = demoScreenTimeData
        screenTimeManager.isLoading = false
        screenTimeManager.errorMessage = nil
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
                Text("Savir's Usage Today")
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

// MARK: - App Usage Timeline Card (REPLACES HourlyBreakdownCard)
struct AppUsageTimelineCard: View {
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
    
    // DEMO DATA START - Timeline app usage with specific time ranges
    private let timelineAppUsage: [(appName: String, color: Color, timeBlocks: [(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int)])] = [
        ("Instagram", .purple, [(8, 5, 8, 35), (18, 0, 18, 45)]), // 8:05 AM-8:35 AM and 6:00 PM-6:45 PM
        ("TikTok", .black, [(12, 5, 12, 22), (12, 50, 13, 18)]), // 12:05 PM-12:22 PM and 12:50 PM-1:18 PM
        ("YouTube", .red, [(12, 25, 12, 45), (14, 0, 14, 40)]), // 12:25 PM-12:45 PM and 2:00 PM-2:40 PM
        ("Safari", .blue, [(16, 0, 16, 20)]), // 4:00 PM-4:20 PM
        ("Messages", .green, [(20, 15, 20, 30)]), // 8:15 PM-8:30 PM
        ("Snapchat", .yellow, [(17, 15, 17, 45)]) // 5:15 PM-5:45 PM
    ]
    // DEMO DATA END
    // State for tap interaction
    @State private var selectedBlock: (appName: String, startTime: String, endTime: String, position: CGPoint)? = nil
    
    @ViewBuilder
    private var overlayContent: some View {
        if let block = selectedBlock {
            VStack(spacing: 8) {
                Text("\(block.appName) Usage:")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("\(block.startTime) - \(block.endTime)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button("OK") {
                    selectedBlock = nil
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            .offset(x: block.position.x - 60, y: block.position.y - 40)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedBlock != nil)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.blue)
                Text("App Usage Times")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal)
            
            // Timeline Container
            VStack(spacing: 0) {
                // Time axis labels (6 AM to 10 PM)
                HStack(spacing: 0) {
                    ForEach([6, 8, 10, 12, 14, 16, 18, 20, 22], id: \.self) { hour in
                        Text(formatTimeLabel(hour))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                
                // App usage bars
                VStack(spacing: 10) {
                    ForEach(timelineAppUsage, id: \.appName) { app in
                        AppTimelineRow(
                            appName: app.appName,
                            color: app.color,
                            timeBlocks: app.timeBlocks,
                            onBlockTap: handleBlockTap
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        // DEMO DATA START - Bubble overlay for showing app usage details
        .overlay(overlayContent)
    }
    
    private func formatTimeLabel(_ hour: Int) -> String {
        switch hour {
            case 6: return "6a"
            case 8: return "8"
            case 10: return "10"
            case 12: return "12p"
            case 14: return "2"
            case 16: return "4"
            case 18: return "6p"
            case 20: return "8"
            case 22: return "10p"
            default: return "\(hour)"
        }
    }
    
    // DEMO DATA START - Updated tap handling with position tracking
    private func handleBlockTap(appName: String, timeBlock: (startHour: Int, startMinute: Int, endHour: Int, endMinute: Int), at position: CGPoint) {
        let startTime = formatTime(hour: timeBlock.startHour, minute: timeBlock.startMinute)
        let endTime = formatTime(hour: timeBlock.endHour, minute: timeBlock.endMinute)
            
        selectedBlock = (appName: appName, startTime: startTime, endTime: endTime, position: position)
    }
    // DEMO DATA END
        
    private func formatTime(hour: Int, minute: Int) -> String {
        let period = hour < 12 ? "AM" : "PM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }
    // DEMO DATA END
}

// MARK: - App Timeline Row
struct AppTimelineRow: View {
    let appName: String
    let color: Color
    let timeBlocks: [(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int)]
    // DEMO DATA START - Updated callback to include tap position
    let onBlockTap: (String, (startHour: Int, startMinute: Int, endHour: Int, endMinute: Int), CGPoint) -> Void
    // DEMO DATA END
    
    // Timeline spans from 6 AM (hour 6) to 10 PM (hour 22) = 16 hours total
    private let startHour: Int = 6
    private let endHour: Int = 22
    private let totalHours: Int = 16
    
    var body: some View {
        HStack(spacing: 0) {
            // Timeline container
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background timeline
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 12)
                        .cornerRadius(6)
                    
                    // Usage bars - This is the problematic part
                    ForEach(Array(timeBlocks.enumerated()), id: \.offset) { index, block in
                        let startPosition = calculatePosition(hour: block.startHour, minute: block.startMinute, totalWidth: geometry.size.width)
                        let endPosition = calculatePosition(hour: block.endHour, minute: block.endMinute, totalWidth: geometry.size.width)
                        let blockWidth = endPosition - startPosition
                        
                        let rectangle = RoundedRectangle(cornerRadius: 6)
                            .fill(color)
                            .frame(width: max(blockWidth, 4), height: 12)
                            .offset(x: startPosition)
                        
                        // Break out the tap gesture logic into a separate function
                        rectangle
                            .onTapGesture {
                                handleTapGesture(
                                    appName: appName,
                                    block: block,
                                    startPosition: startPosition,
                                    blockWidth: blockWidth,
                                    geometry: geometry
                                )
                            }
                    }
                }
            }
            .frame(height: 12)
        }
    }

    // Add this new helper function inside AppTimelineRow
    private func handleTapGesture(
        appName: String,
        block: (startHour: Int, startMinute: Int, endHour: Int, endMinute: Int),
        startPosition: CGFloat,
        blockWidth: CGFloat,
        geometry: GeometryProxy
    ) {
        let screenWidth = geometry.size.width
        let bubbleWidth: CGFloat = 120
        let bubbleHeight: CGFloat = 80

        let (adjustedX, adjustedY): (CGFloat, CGFloat) = {
            let baseX = startPosition + (blockWidth / 2)
            
            switch appName {
            case "Instagram":
                return (baseX - 40, -30)
            case "Messages":
                return (baseX - 80, 35)
            case "Snapchat":
                return (baseX - 40, 60)
            default:
                var x = baseX
                if x + bubbleWidth/2 > screenWidth {
                    x = screenWidth - bubbleWidth/2 - 10
                } else if x - bubbleWidth/2 < 0 {
                    x = bubbleWidth/2 + 10
                }
                return (x, 0)
            }
        }()

        let globalPosition = CGPoint(x: adjustedX, y: adjustedY)
        onBlockTap(appName, block, globalPosition)
    }
    
    private func calculatePosition(hour: Int, minute: Int, totalWidth: CGFloat) -> CGFloat {
        // Convert time to minutes from start time (6 AM)
        let totalMinutesFromStart = (hour - startHour) * 60 + minute
        let totalTimelineMinutes = totalHours * 60
        
        // Calculate position as percentage of total width
        let percentage = CGFloat(totalMinutesFromStart) / CGFloat(totalTimelineMinutes)
        return percentage * totalWidth
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
