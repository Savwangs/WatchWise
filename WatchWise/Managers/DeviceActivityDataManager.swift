//
//  DeviceActivityDataManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 7/2/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class DeviceActivityDataManager: ObservableObject {
    @Published var isDataAvailable = false
    @Published var lastUpdateTime: Date?
    @Published var errorMessage: String?
    
    private let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
    private let db = Firestore.firestore()
    private var updateTimer: Timer?
    
    // App name mapping for better display
    private let appNameMapping: [String: String] = [
        "com.burbn.instagram": "Instagram",
        "com.zhiliaoapp.musically": "TikTok",
        "com.google.ios.youtube": "YouTube",
        "com.apple.mobilesafari": "Safari",
        "com.apple.MobileSMS": "Messages",
        "com.toyopagroup.picaboo": "Snapchat",
        "com.whatsapp.WhatsApp": "WhatsApp",
        "com.facebook.Facebook": "Facebook",
        "com.twitter.ios": "Twitter",
        "com.hammerandchisel.discord": "Discord",
        "com.reddit.Reddit": "Reddit",
        "com.netflix.Netflix": "Netflix",
        "com.spotify.client": "Spotify",
        "com.mojang.minecraftpe": "Minecraft",
        "com.roblox.client": "Roblox",
        "com.epicgames.fortnite": "Fortnite",
        "com.activision.callofduty.shooter": "Call of Duty",
        "com.tencent.ig": "PUBG",
        "com.mihoyo.genshinimpact": "Genshin Impact",
        "com.innersloth.spacemafia": "Among Us"
    ]
    
    init() {
        startPeriodicUpdates()
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    // MARK: - Data Retrieval
    
    func getCurrentScreenTimeData(for deviceId: String) -> ScreenTimeData? {
        guard let userDefaults = userDefaults else {
            errorMessage = "Unable to access shared data"
            return nil
        }
        
        // Get app usage data
        guard let appUsageData = userDefaults.array(forKey: "detailed_app_usage_data") as? [[String: Any]],
              let hourlyBreakdown = userDefaults.dictionary(forKey: "hourly_breakdown_data") as? [String: TimeInterval],
              let appUsageRanges = userDefaults.dictionary(forKey: "app_usage_ranges") as? [String: [[String: Any]]],
              let lastUpdate = userDefaults.object(forKey: "last_activity_update") as? TimeInterval else {
            errorMessage = "No screen time data available"
            return nil
        }
        
        // Process app usage data
        var appUsages: [AppUsage] = []
        var totalScreenTime: TimeInterval = 0
        
        // Group by bundle identifier
        var appUsageByBundle: [String: (duration: TimeInterval, ranges: [[String: Any]])] = [:]
        
        for appData in appUsageData {
            guard let bundleId = appData["bundleIdentifier"] as? String,
                  let duration = appData["duration"] as? TimeInterval else { continue }
            
            appUsageByBundle[bundleId, default: (0, [])].duration += duration
            totalScreenTime += duration
        }
        
        // Create AppUsage objects with usage ranges
        for (bundleId, data) in appUsageByBundle {
            let appName = appNameMapping[bundleId] ?? bundleId.components(separatedBy: ".").last ?? bundleId
            let usageRanges = processUsageRanges(appUsageRanges[bundleId] ?? [])
            
            let appUsage = AppUsage(
                appName: appName,
                bundleIdentifier: bundleId,
                duration: data.duration,
                timestamp: Date(),
                usageRanges: usageRanges
            )
            appUsages.append(appUsage)
        }
        
        // Sort by duration
        appUsages.sort { $0.duration > $1.duration }
        
        // Process hourly breakdown
        var processedHourlyBreakdown: [Int: TimeInterval] = [:]
        for (hourString, duration) in hourlyBreakdown {
            if let hour = Int(hourString) {
                processedHourlyBreakdown[hour] = duration
            }
        }
        
        // Update state
        lastUpdateTime = Date(timeIntervalSince1970: lastUpdate)
        isDataAvailable = true
        errorMessage = nil
        
        return ScreenTimeData(
            deviceId: deviceId,
            date: Date(),
            totalScreenTime: totalScreenTime,
            appUsages: appUsages,
            hourlyBreakdown: processedHourlyBreakdown
        )
    }
    
    private func processUsageRanges(_ ranges: [[String: Any]]) -> [AppUsageRange] {
        return ranges.compactMap { rangeData in
            guard let startTimeInterval = rangeData["startTime"] as? TimeInterval,
                  let endTimeInterval = rangeData["endTime"] as? TimeInterval,
                  let duration = rangeData["duration"] as? TimeInterval,
                  let sessionId = rangeData["sessionId"] as? String else {
                return nil
            }
            
            return AppUsageRange(
                startTime: Date(timeIntervalSince1970: startTimeInterval),
                endTime: Date(timeIntervalSince1970: endTimeInterval),
                duration: duration,
                sessionId: sessionId
            )
        }
    }
    
    // MARK: - Data Synchronization
    
    func syncDataToFirebase(for deviceId: String, parentId: String) async {
        guard let screenTimeData = getCurrentScreenTimeData(for: deviceId) else {
            print("❌ No screen time data to sync")
            return
        }
        
        do {
            // Create document ID for today's data
            let today = Calendar.current.startOfDay(for: Date())
            let documentId = "\(deviceId)_\(Int(today.timeIntervalSince1970))"
            
            // Convert to Firestore data
            let data: [String: Any] = [
                "deviceId": screenTimeData.deviceId,
                "date": Timestamp(date: screenTimeData.date),
                "totalScreenTime": screenTimeData.totalScreenTime,
                "appUsages": screenTimeData.appUsages.map { appUsage in
                    [
                        "appName": appUsage.appName,
                        "bundleIdentifier": appUsage.bundleIdentifier,
                        "duration": appUsage.duration,
                        "timestamp": Timestamp(date: appUsage.timestamp),
                        "usageRanges": appUsage.usageRanges?.map { range in
                            [
                                "startTime": Timestamp(date: range.startTime),
                                "endTime": Timestamp(date: range.endTime),
                                "duration": range.duration,
                                "sessionId": range.sessionId
                            ]
                        } ?? []
                    ]
                },
                "hourlyBreakdown": screenTimeData.hourlyBreakdown,
                "lastUpdated": Timestamp(),
                "parentId": parentId
            ]
            
            // Save to Firestore
            try await db.collection("screenTimeData").document(documentId).setData(data, merge: true)
            
            print("✅ Screen time data synced to Firebase for device: \(deviceId)")
            
        } catch {
            print("❌ Error syncing screen time data: \(error)")
            errorMessage = "Failed to sync data: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Periodic Updates
    
    private func startPeriodicUpdates() {
        // Update every 30 seconds to check for new data
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForNewData()
            }
        }
    }
    
    private func checkForNewData() {
        guard let userDefaults = userDefaults,
              let lastUpdate = userDefaults.object(forKey: "last_activity_update") as? TimeInterval else {
            return
        }
        
        let lastUpdateDate = Date(timeIntervalSince1970: lastUpdate)
        let timeSinceUpdate = Date().timeIntervalSince(lastUpdateDate)
        
        // If data is older than 5 minutes, mark as stale
        if timeSinceUpdate > 300 {
            isDataAvailable = false
            errorMessage = "Screen time data may be stale. Please check child device connection."
        }
    }
    
    // MARK: - New App Detection
    
    func getNewAppDetections() -> [String] {
        guard let userDefaults = userDefaults else { return [] }
        return userDefaults.array(forKey: "new_app_detections") as? [String] ?? []
    }
    
    func clearNewAppDetections() {
        userDefaults?.removeObject(forKey: "new_app_detections")
    }
    
    // MARK: - Data Validation
    
    func validateDataIntegrity() -> Bool {
        guard let userDefaults = userDefaults else { return false }
        
        let requiredKeys = [
            "detailed_app_usage_data",
            "hourly_breakdown_data",
            "app_usage_ranges",
            "last_activity_update"
        ]
        
        for key in requiredKeys {
            if userDefaults.object(forKey: key) == nil {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Utility Methods
    
    func getAppName(for bundleId: String) -> String {
        return appNameMapping[bundleId] ?? bundleId.components(separatedBy: ".").last ?? bundleId
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    func isDataStale() -> Bool {
        guard let lastUpdate = lastUpdateTime else { return true }
        return Date().timeIntervalSince(lastUpdate) > 300 // 5 minutes
    }
} 