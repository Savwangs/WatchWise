//
//  DashboardView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//
import SwiftUI
import Charts
import FirebaseAuth

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
                ForEach(Array(appUsages.prefix(5).enumerated()), id: \.offset) { index, usage in
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption)
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.orange)
                            .clipShape(Circle())
                        
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.green)
                Text("Hourly Breakdown")
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
                    Chart {
                        ForEach(sortedHourlyData, id: \.hour) { data in
                            BarMark(
                                x: .value("Hour", data.hour),
                                y: .value("Minutes", data.minutes)
                            )
                            .foregroundStyle(Color.green.gradient)
                            .cornerRadius(4)
                        }
                    }
                    .frame(height: 200)
                    .chartXAxis {
                        AxisMarks(values: .automatic) { value in
                            if let hour = value.as(Int.self) {
                                AxisValueLabel {
                                    Text("\(hour):00")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let minutes = value.as(Double.self) {
                                    Text("\(Int(minutes))m")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Text("Hourly usage breakdown:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        ForEach(sortedHourlyData.prefix(5), id: \.hour) { data in
                            HStack {
                                Text("\(data.hour):00")
                                    .font(.caption)
                                    .frame(width: 50, alignment: .leading)
                                
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.green)
                                    .frame(width: CGFloat(data.minutes) * 2, height: 8)
                                
                                Spacer()
                                
                                Text("\(Int(data.minutes))m")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(height: 150)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var sortedHourlyData: [(hour: Int, minutes: Double)] {
        hourlyData.map { (hour: $0.key, minutes: $0.value / 60) }
            .sorted { $0.hour < $1.hour }
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
