//
//  ScreenTimeMonitoringManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/7/25.
//

import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings
import FirebaseFirestore

@MainActor
class ScreenTimeMonitoringManager: ObservableObject {
    @Published var isMonitoring = false
    @Published var lastActivityUpdate = Date()
    @Published var detectedNewApps: [NewAppDetection] = []
    @Published var errorMessage: String?
    
    private let deviceActivityCenter = DeviceActivityCenter()
    private let authorizationCenter = AuthorizationCenter.shared
    private let db = Firestore.firestore()
    private let databaseManager = DatabaseManager.shared
    
    // DeviceActivity names for different monitoring purposes
    private let dailyMonitoringName = DeviceActivityName("DailyScreenTime")
    private let newAppDetectionName = DeviceActivityName("NewAppDetection")
    private let appUsageTrackingName = DeviceActivityName("AppUsageTracking")
    
    // Store for managing app restrictions
    private let store = ManagedSettingsStore()
    
    // Track known apps to detect new ones
    private var knownApps: Set<String> = []
    
    init() {
        loadKnownApps()
    }
    
    // MARK: - Authorization
    
    func checkAuthorizationStatus() -> AuthorizationStatus {
        return authorizationCenter.authorizationStatus
    }
    
    func requestAuthorization() async throws {
        try await authorizationCenter.requestAuthorization(for: .individual)
    }
    
    // MARK: - Monitoring Setup
    
    func startMonitoring(for deviceId: String) async {
        guard checkAuthorizationStatus() == .approved else {
            errorMessage = "Family Controls authorization required"
            return
        }
        
        do {
            // Start daily screen time monitoring
            try await startDailyMonitoring(deviceId: deviceId)
            
            // Start new app detection monitoring
            try await startNewAppDetection(deviceId: deviceId)
            
            // Start app usage tracking
            try await startAppUsageTracking(deviceId: deviceId)
            
            await MainActor.run {
                self.isMonitoring = true
                self.lastActivityUpdate = Date()
            }
            
            print("✅ Activity monitoring started successfully")
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to start monitoring: \(error.localizedDescription)"
            }
            print("🔥 Error starting monitoring: \(error)")
        }
    }
    
    func stopMonitoring() {
        deviceActivityCenter.stopMonitoring([
            dailyMonitoringName,
            newAppDetectionName,
            appUsageTrackingName
        ])
        
        Task { @MainActor in
            self.isMonitoring = false
        }
        
        print("✅ Activity monitoring stopped")
    }
    
    // MARK: - Daily Screen Time Monitoring
    
    private func startDailyMonitoring(deviceId: String) async throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        try deviceActivityCenter.startMonitoring(
            dailyMonitoringName,
            during: schedule
        )
    }
    
    // MARK: - New App Detection
    
    private func startNewAppDetection(deviceId: String) async throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        try deviceActivityCenter.startMonitoring(
            newAppDetectionName,
            during: schedule
        )
    }
    
    // MARK: - App Usage Tracking
    
    private func startAppUsageTracking(deviceId: String) async throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        try deviceActivityCenter.startMonitoring(
            appUsageTrackingName,
            during: schedule
        )
    }
    
    // MARK: - App Detection
    
    func detectNewApps() async {
        do {
            let currentApps = await getInstalledApps()
            let newApps = currentApps.filter { !knownApps.contains($0.bundleIdentifier) }
            
            if (!newApps.isEmpty) {
                await processNewApps(newApps)
                await updateKnownApps(currentApps)
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to detect new apps: \(error.localizedDescription)"
            }
        }
    }
    
    private func getInstalledApps() async -> [AppInfo] {
        // In a real implementation, this would use DeviceActivityReport
        // For now, we'll simulate getting installed apps
        let commonApps = [
            AppInfo(name: "Instagram", bundleIdentifier: "com.burbn.instagram", category: "Social Networking"),
            AppInfo(name: "TikTok", bundleIdentifier: "com.zhiliaoapp.musically", category: "Entertainment"),
            AppInfo(name: "YouTube", bundleIdentifier: "com.google.ios.youtube", category: "Entertainment"),
            AppInfo(name: "Safari", bundleIdentifier: "com.apple.mobilesafari", category: "Productivity"),
            AppInfo(name: "Messages", bundleIdentifier: "com.apple.MobileSMS", category: "Social Networking"),
            AppInfo(name: "Snapchat", bundleIdentifier: "com.toyopagroup.picaboo", category: "Social Networking"),
            AppInfo(name: "WhatsApp", bundleIdentifier: "net.whatsapp.WhatsApp", category: "Social Networking"),
            AppInfo(name: "Discord", bundleIdentifier: "com.hammerandchisel.discord", category: "Social Networking"),
            AppInfo(name: "Twitter", bundleIdentifier: "com.atebits.Tweetie2", category: "Social Networking"),
            AppInfo(name: "Facebook", bundleIdentifier: "com.facebook.Facebook", category: "Social Networking"),
            AppInfo(name: "Netflix", bundleIdentifier: "com.netflix.Netflix", category: "Entertainment"),
            AppInfo(name: "Spotify", bundleIdentifier: "com.spotify.client", category: "Entertainment"),
            AppInfo(name: "Minecraft", bundleIdentifier: "com.mojang.minecraftpe", category: "Games"),
            AppInfo(name: "Roblox", bundleIdentifier: "com.roblox.client", category: "Games"),
            AppInfo(name: "Fortnite", bundleIdentifier: "com.epicgames.fortnite", category: "Games")
        ]
        
        // Simulate some apps being newly installed
        let randomNewApps = Array(commonApps.shuffled().prefix(Int.random(in: 1...3)))
        
        return randomNewApps
    }
    
    private func processNewApps(_ newApps: [AppInfo]) async {
        for app in newApps {
            let detection = NewAppDetection(
                appName: app.name,
                bundleIdentifier: app.bundleIdentifier,
                category: app.category,
                detectedAt: Date()
            )
            
            await MainActor.run {
                self.detectedNewApps.append(detection)
            }
            
            // Save to Firestore
            await saveNewAppDetection(detection)
            
            // Send notification to parent
            await notifyParentOfNewApp(detection)
        }
    }
    
    private func saveNewAppDetection(_ detection: NewAppDetection) async {
        do {
            let data: [String: Any] = [
                "appName": detection.appName,
                "bundleIdentifier": detection.bundleIdentifier,
                "category": detection.category,
                "detectedAt": Timestamp(date: detection.detectedAt),
                "isNotified": false
            ]
            
            try await db.collection("newAppDetections").addDocument(data: data)
            print("✅ New app detection saved: \(detection.appName)")
            
        } catch {
            print("🔥 Error saving new app detection: \(error)")
        }
    }
    
    private func notifyParentOfNewApp(_ detection: NewAppDetection) async {
        // This would integrate with your notification system
        // For now, we'll just log it
        print("🔔 New app detected: \(detection.appName) (\(detection.bundleIdentifier))")
        
        // TODO: Send push notification to parent
        // TODO: Update parent's dashboard
    }
    
    // MARK: - Data Management
    
    private func loadKnownApps() {
        // Load known apps from UserDefaults or Firestore
        // For now, we'll start with an empty set
        knownApps = []
    }
    
    private func updateKnownApps(_ currentApps: [AppInfo]) async {
        let newKnownApps = Set(currentApps.map { $0.bundleIdentifier })
        
        await MainActor.run {
            self.knownApps = newKnownApps
        }
        
        // Save to UserDefaults for persistence
        UserDefaults.standard.set(Array(newKnownApps), forKey: "knownApps")
    }
    
    // MARK: - App Usage Collection
    
    func collectAppUsageData() async -> [AppUsage] {
        // In a real implementation, this would use DeviceActivityReport
        // to get actual app usage data from the system
        
        let commonApps = [
            ("Instagram", "com.burbn.instagram"),
            ("TikTok", "com.zhiliaoapp.musically"),
            ("YouTube", "com.google.ios.youtube"),
            ("Safari", "com.apple.mobilesafari"),
            ("Messages", "com.apple.MobileSMS"),
            ("Snapchat", "com.toyopagroup.picaboo")
        ]
        
        var appUsages: [AppUsage] = []
        
        for (name, bundleId) in commonApps {
            // Simulate realistic usage patterns
            let duration = TimeInterval.random(in: 300...7200) // 5 minutes to 2 hours
            let timestamp = Date().addingTimeInterval(-TimeInterval.random(in: 0...86400)) // Within last 24 hours
            
            let usage = AppUsage(
                appName: name,
                bundleIdentifier: bundleId,
                duration: duration,
                timestamp: timestamp
            )
            
            appUsages.append(usage)
        }
        
        // Sort by duration (most used first)
        return appUsages.sorted { $0.duration > $1.duration }
    }
    
    func getHourlyBreakdown() async -> [Int: TimeInterval] {
        // Generate realistic hourly breakdown
        var breakdown: [Int: TimeInterval] = [:]
        
        for hour in 0..<24 {
            // More activity during typical hours (8 AM - 10 PM)
            let baseActivity: TimeInterval = (hour >= 8 && hour <= 22) ? 1800 : 300 // 30 min vs 5 min
            let randomFactor = Double.random(in: 0.5...1.5)
            breakdown[hour] = baseActivity * randomFactor
        }
        
        return breakdown
    }
    
    // MARK: - Utility Methods
    
    func clearError() {
        errorMessage = nil
    }
    
    func clearNewAppDetections() {
        detectedNewApps.removeAll()
    }
}

// MARK: - Supporting Models

struct AppInfo {
    let name: String
    let bundleIdentifier: String
    let category: String
}

struct NewAppDetection: Identifiable, Codable {
    let id = UUID()
    let appName: String
    let bundleIdentifier: String
    let category: String
    let detectedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case appName, bundleIdentifier, category, detectedAt
    }
} 