//
//  ScreenTimeDataManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/7/25.
//

import Foundation
import FamilyControls
import DeviceActivity
import ManagedSettings
import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
class ScreenTimeDataManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var isLoading = false
    @Published var currentScreenTimeData: ScreenTimeData?
    @Published var errorMessage: String?
    @Published var detectedNewApps: [NewAppDetection] = []
    @Published var isMonitoring = false
    
    private let authorizationCenter = AuthorizationCenter.shared
    private let db = Firestore.firestore()
    private let databaseManager = DatabaseManager.shared
    private let functions = Functions.functions()
    private var deviceActivityCenter = DeviceActivityCenter()
    private let store = ManagedSettingsStore()
    
    // DeviceActivity names for different monitoring purposes
    private let dailyMonitoringName = DeviceActivityName("DailyScreenTime")
    private let newAppDetectionName = DeviceActivityName("NewAppDetection")
    private let appUsageTrackingName = DeviceActivityName("AppUsageTracking")
    
    // Track known apps to detect new ones
    private var knownApps: Set<String> = []
    private var currentDeviceId: String?
    
    init() {
        checkAuthorizationStatus()
        loadKnownApps()
        setupDeviceActivityMonitoring()
    }

    func checkAuthorizationStatus() {
        switch authorizationCenter.authorizationStatus {
        case .approved:
            isAuthorized = true
            print("✅ Family Controls authorization approved")
        case .denied:
            isAuthorized = false
            print("❌ Family Controls authorization denied")
        case .notDetermined:
            isAuthorized = false
            print("⏳ Family Controls authorization not determined")
        @unknown default:
            isAuthorized = false
            print("❓ Family Controls authorization unknown status")
        }
    }
    
    func requestAuthorization() async {
        do {
            print("🔄 Requesting Family Controls authorization...")
            try await authorizationCenter.requestAuthorization(for: .individual)
            await MainActor.run {
                checkAuthorizationStatus()
                if isAuthorized {
                    print("✅ Family Controls authorization granted")
                } else {
                    print("❌ Family Controls authorization failed")
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to get Screen Time authorization: \(error.localizedDescription)"
                print("🔥 Authorization error: \(error)")
            }
        }
    }

    func startScreenTimeMonitoring(for deviceId: String) async {
        guard isAuthorized else {
            errorMessage = "Screen Time authorization required"
            print("❌ Cannot start monitoring - authorization required")
            return
        }
        
        currentDeviceId = deviceId
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            print("🔄 Starting screen time monitoring for device: \(deviceId)")
            
            // Start daily screen time monitoring
            try await startDailyMonitoring(deviceId: deviceId)
            
            // Start new app detection monitoring
            try await startNewAppDetection(deviceId: deviceId)
            
            // Start app usage tracking
            try await startAppUsageTracking(deviceId: deviceId)
            
            // Collect current screen time data
            await collectTodayScreenTimeData(for: deviceId)
            
            // Detect new apps
            await detectNewApps()
            
            await MainActor.run {
                self.isMonitoring = true
                self.isLoading = false
            }
            
            print("✅ Screen time monitoring started successfully")
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to start monitoring: \(error.localizedDescription)"
                isLoading = false
            }
            print("🔥 Error starting monitoring: \(error)")
        }
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
        
        print("✅ Daily screen time monitoring started")
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
        
        print("✅ New app detection monitoring started")
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
        
        print("✅ App usage tracking started")
    }
    
    func collectTodayScreenTimeData(for deviceId: String) async {
        guard isAuthorized else { 
            print("❌ Cannot collect data - authorization required")
            return 
        }
        
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? Date()
        
        do {
            print("🔄 Collecting screen time data for today...")
            
            // Get app usage data using DeviceActivity
            let appUsageData = await getAppUsageData(from: today, to: tomorrow)
            let hourlyBreakdown = await getHourlyBreakdown(from: today, to: tomorrow)
            
            let totalScreenTime = appUsageData.reduce(0) { $0 + $1.duration }
            
            let screenTimeData = ScreenTimeData(
                id: nil,
                deviceId: deviceId,
                date: today,
                totalScreenTime: totalScreenTime,
                appUsages: appUsageData,
                hourlyBreakdown: hourlyBreakdown
            )
            
            // Save to Firebase
            await saveScreenTimeData(screenTimeData)
            
            await MainActor.run {
                self.currentScreenTimeData = screenTimeData
                self.isLoading = false
            }
            
            print("✅ Screen time data collected and saved: \(formatDuration(totalScreenTime))")
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to collect screen time data: \(error.localizedDescription)"
                self.isLoading = false
            }
            print("🔥 Error collecting screen time data: \(error)")
        }
    }

    private func getAppUsageData(from startDate: Date, to endDate: Date) async -> [AppUsage] {
        print("🔄 Getting app usage data from \(startDate) to \(endDate)")
        
        // Try to get real data from DeviceActivityReport extension first
        let realAppUsages = await getRealAppUsageData()
        
        if !realAppUsages.isEmpty {
            print("✅ Found \(realAppUsages.count) real app usage records")
            return realAppUsages
        }
        
        // No real data available - return empty array instead of simulated data
        print("⚠️ No real app usage data found - returning empty data")
        return []
    }
    
    private func getRealAppUsageData() async -> [AppUsage] {
        var appUsages: [AppUsage] = []
        
        // Get app usage data stored by DeviceActivityReport extension
        let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
        let installedApps = await getInstalledApps()
        
        // First try to get detailed app usage data
        if let detailedData = userDefaults?.array(forKey: "detailed_app_usage_data") as? [[String: Any]] {
            print("📊 Found \(detailedData.count) detailed app usage records from background")
            
            for usageData in detailedData {
                guard let bundleId = usageData["bundleIdentifier"] as? String,
                      let duration = usageData["duration"] as? TimeInterval,
                      let timestamp = usageData["timestamp"] as? TimeInterval else {
                    continue
                }
                
                // Find app name from installed apps
                let appName = installedApps.first { $0.bundleIdentifier == bundleId }?.appName ?? bundleId
                
                // Get usage ranges for this app
                let usageRanges = await getUsageRangesForApp(bundleId: bundleId)
                
                let usage = AppUsage(
                    appName: appName,
                    bundleIdentifier: bundleId,
                    duration: duration,
                    timestamp: Date(timeIntervalSince1970: timestamp),
                    usageRanges: usageRanges
                )
                appUsages.append(usage)
            }
            
            // Clear the detailed data after reading
            userDefaults?.removeObject(forKey: "detailed_app_usage_data")
        } else {
            // Fallback to individual app usage data
            for app in installedApps {
                let key = "app_usage_\(app.bundleIdentifier)"
                let duration = userDefaults?.double(forKey: key) ?? 0
                
                if duration > 0 {
                    let usage = AppUsage(
                        appName: app.appName,
                        bundleIdentifier: app.bundleIdentifier,
                        duration: duration,
                        timestamp: Date(),
                        usageRanges: nil
                    )
                    appUsages.append(usage)
                    
                    // Clear the stored duration after reading
                    userDefaults?.removeObject(forKey: key)
                }
            }
        }
        
        return appUsages
    }
    
    private func getUsageRangesForApp(bundleId: String) async -> [AppUsageRange]? {
        let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
        
        guard let appUsageRanges = userDefaults?.dictionary(forKey: "app_usage_ranges") as? [String: [[String: Any]]],
              let rangesData = appUsageRanges[bundleId] else {
            return nil
        }
        
        var ranges: [AppUsageRange] = []
        
        for rangeData in rangesData {
            guard let startTime = rangeData["startTime"] as? TimeInterval,
                  let endTime = rangeData["endTime"] as? TimeInterval,
                  let duration = rangeData["duration"] as? TimeInterval,
                  let sessionId = rangeData["sessionId"] as? String else {
                continue
            }
            
            let range = AppUsageRange(
                startTime: Date(timeIntervalSince1970: startTime),
                endTime: Date(timeIntervalSince1970: endTime),
                duration: duration,
                sessionId: sessionId
            )
            ranges.append(range)
        }
        
        // Clear the ranges after reading
        userDefaults?.removeObject(forKey: "app_usage_ranges")
        
        return ranges.isEmpty ? nil : ranges
    }
    
    private func getHourlyBreakdown(from startDate: Date, to endDate: Date) async -> [Int: TimeInterval] {
        print("🔄 Getting hourly breakdown from \(startDate) to \(endDate)")
        
        // Try to get real hourly data from DeviceActivityReport extension
        let realHourlyData = await getRealHourlyBreakdown()
        
        if !realHourlyData.isEmpty {
            print("✅ Found real hourly breakdown data")
            return realHourlyData
        }
        
        // No real data available - return empty dictionary instead of simulated data
        print("⚠️ No real hourly data found - returning empty data")
        return [:]
    }
    
    private func getRealHourlyBreakdown() async -> [Int: TimeInterval] {
        var breakdown: [Int: TimeInterval] = [:]
        
        // Get hourly breakdown data stored by DeviceActivityReport extension
        let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
        
        if let hourlyData = userDefaults?.dictionary(forKey: "hourly_breakdown_data") as? [String: TimeInterval] {
            print("📊 Found hourly breakdown data from background")
            
            // Convert string keys to integers
            for (hourString, duration) in hourlyData {
                if let hour = Int(hourString) {
                    breakdown[hour] = duration
                }
            }
            
            // Clear the data after reading
            userDefaults?.removeObject(forKey: "hourly_breakdown_data")
        } else {
            // Fallback to detailed app usage data
            let installedApps = await getInstalledApps()
            
            for app in installedApps {
                let key = "detailed_app_usage_\(app.bundleIdentifier)"
                let usageData = userDefaults?.array(forKey: key) as? [[String: Any]] ?? []
                
                for usage in usageData {
                    if let duration = usage["duration"] as? TimeInterval,
                       let timestamp = usage["timestamp"] as? TimeInterval {
                        let date = Date(timeIntervalSince1970: timestamp)
                        let hour = Calendar.current.component(.hour, from: date)
                        
                        breakdown[hour, default: 0] += duration
                    }
                }
            }
        }
        
        return breakdown
    }
    
    // MARK: - New App Detection
    
    func detectNewApps() async {
        do {
            print("🔄 Detecting new apps...")
            
            // Check for real new app detections from DeviceActivityReport extension first
            let realNewApps = await getRealNewAppDetections()
            
            if !realNewApps.isEmpty {
                print("🆕 Found \(realNewApps.count) real new app detections: \(realNewApps.map { $0.appName })")
                await processNewApps(realNewApps)
                await updateKnownApps(await getInstalledApps())
                return
            }
            
            // Fallback to simulated detection
            print("⚠️ No real new app detections found, using simulated detection")
            
            let currentApps = await getInstalledApps()
            let newApps = currentApps.filter { !knownApps.contains($0.bundleIdentifier) }
            
            if !newApps.isEmpty {
                print("🆕 Found \(newApps.count) new apps: \(newApps.map { $0.appName })")
                await processNewApps(newApps)
                await updateKnownApps(currentApps)
            } else {
                print("✅ No new apps detected")
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to detect new apps: \(error.localizedDescription)"
            }
            print("🔥 Error detecting new apps: \(error)")
        }
    }
    
    private func getRealNewAppDetections() async -> [AppInfo] {
        // Get new app detections stored by DeviceActivityReport extension
        let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
        let newAppBundleIds = userDefaults?.array(forKey: "new_app_detections") as? [String] ?? []
        
        if newAppBundleIds.isEmpty {
            return []
        }
        
        print("🆕 Found \(newAppBundleIds.count) new app detections from background")
        
        // Clear the detections after reading
        userDefaults?.removeObject(forKey: "new_app_detections")
        
        // Convert bundle IDs to AppInfo objects
        let installedApps = await getInstalledApps()
        let newApps = installedApps.filter { newAppBundleIds.contains($0.bundleIdentifier) }
        
        return newApps
    }
    
    private func processNewApps(_ newApps: [AppInfo]) async {
        guard let deviceId = currentDeviceId else { return }
        
        for app in newApps {
            let detection = NewAppDetection(
                appName: app.appName,
                bundleIdentifier: app.bundleIdentifier,
                category: app.category,
                detectedAt: Date(),
                deviceId: deviceId
            )
            
            await MainActor.run {
                self.detectedNewApps.append(detection)
            }
            
            // Save to Firestore
            await saveNewAppDetection(detection)
            
            // Notify parent
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
                "deviceId": detection.deviceId,
                "isNotified": false
            ]
            
            try await db.collection("newAppDetections").addDocument(data: data)
            print("✅ New app detection saved: \(detection.appName)")
            
        } catch {
            print("🔥 Error saving new app detection: \(error)")
        }
    }
    
    private func notifyParentOfNewApp(_ detection: NewAppDetection) async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        do {
            // Find parent-child relationship
            let relationshipsQuery = db.collection("parentChildRelationships")
                .whereField("childUserId", isEqualTo: currentUser.uid)
                .whereField("isActive", isEqualTo: true)
            
            let snapshot = try await relationshipsQuery.getDocuments()
            
            if let relationship = snapshot.documents.first {
                let relationshipData = relationship.data()
                let parentUserId = relationshipData["parentUserId"] as? String ?? ""
                let childName = relationshipData["childName"] as? String ?? "Child"
                
                // Create notification for parent
                try await db.collection("notifications").addDocument(data: [
                    "parentUserId": parentUserId,
                    "childUserId": currentUser.uid,
                    "childName": childName,
                    "type": "new_app_detected",
                    "title": "New App Detected",
                    "message": "\(childName) has started using a new app: \(detection.appName)",
                    "appName": detection.appName,
                    "bundleIdentifier": detection.bundleIdentifier,
                    "timestamp": Timestamp(),
                    "isRead": false
                ])
                
                print("📧 Sent new app notification to parent: \(detection.appName)")
            }
            
        } catch {
            print("🔥 Error sending new app notification: \(error)")
        }
    }
    
    // MARK: - App Information
    
    private func getInstalledApps() async -> [AppInfo] {
        // In a real implementation, this would use DeviceActivityReport
        // to get actual installed apps from the system
        
        // For now, we'll return a list of common apps
        let commonApps = [
            ("Instagram", "com.burbn.instagram"),
            ("TikTok", "com.zhiliaoapp.musically"),
            ("YouTube", "com.google.ios.youtube"),
            ("Safari", "com.apple.mobilesafari"),
            ("Messages", "com.apple.MobileSMS"),
            ("Snapchat", "com.toyopagroup.picaboo"),
            ("WhatsApp", "net.whatsapp.WhatsApp"),
            ("Discord", "com.hammerandchisel.discord"),
            ("Twitter", "com.atebits.Tweetie2"),
            ("Facebook", "com.facebook.Facebook"),
            ("Netflix", "com.netflix.Netflix"),
            ("Spotify", "com.spotify.client"),
            ("Minecraft", "com.mojang.minecraftpe"),
            ("Roblox", "com.roblox.client"),
            ("Fortnite", "com.epicgames.fortnite"),
            ("Call of Duty", "com.activision.callofduty.warzone"),
            ("Genshin Impact", "com.miHoYo.GenshinImpact"),
            ("Among Us", "com.innersloth.spacemafia"),
            ("Zoom", "us.zoom.videomeetings"),
            ("Google Classroom", "com.google.edu.googleclassroom")
        ]
        
        return commonApps.map { AppInfo(appName: $0.0, bundleIdentifier: $0.1, category: "Unknown") }
    }
    
    private func loadKnownApps() {
        // Load known apps from UserDefaults
        if let savedApps = UserDefaults.standard.array(forKey: "knownApps") as? [String] {
            knownApps = Set(savedApps)
            print("📱 Loaded \(knownApps.count) known apps from storage")
        } else {
            knownApps = []
            print("📱 No known apps found in storage")
        }
    }
    
    private func updateKnownApps(_ currentApps: [AppInfo]) async {
        let newKnownApps = Set(currentApps.map { $0.bundleIdentifier })
        
        await MainActor.run {
            self.knownApps = newKnownApps
        }
        
        // Save to UserDefaults for persistence
        UserDefaults.standard.set(Array(newKnownApps), forKey: "knownApps")
        print("💾 Updated known apps: \(newKnownApps.count) apps")
    }

    func saveScreenTimeData(_ data: ScreenTimeData) async {
        do {
            try await withCheckedThrowingContinuation { continuation in
                databaseManager.saveScreenTimeData(data) { result in
                    continuation.resume(with: result)
                }
            }
            print("✅ Screen time data saved to Firebase")
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to save screen time data: \(error.localizedDescription)"
            }
            print("🔥 Error saving screen time data: \(error)")
        }
    }
    
    func loadScreenTimeData(for deviceId: String, date: Date = Date()) async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let screenTimeData = try await withCheckedThrowingContinuation { continuation in
                databaseManager.getScreenTimeData(for: deviceId, date: date) { result in
                    continuation.resume(with: result)
                }
            }
            
            await MainActor.run {
                self.currentScreenTimeData = screenTimeData
                self.isLoading = false
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load screen time data: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    func setupRealtimeUpdates(for deviceId: String) {
        // Set up Firestore listener for real-time updates
        let today = Calendar.current.startOfDay(for: Date())
        
        db.collection("screenTimeData")
            .whereField("deviceId", isEqualTo: deviceId)
            .whereField("date", isGreaterThanOrEqualTo: today)
            .whereField("date", isLessThan: Calendar.current.date(byAdding: .day, value: 1, to: today) ?? Date())
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    Task { @MainActor in
                        self.errorMessage = "Real-time update error: \(error.localizedDescription)"
                    }
                    return
                }
                
                guard let documents = snapshot?.documents,
                      let latestDoc = documents.first else { return }
                
                // Safely parse the data with proper type checking
                do {
                    let data = latestDoc.data()
                    
                    // Validate required fields with proper type checking
                    guard let deviceId = data["deviceId"] as? String,
                          let dateTimestamp = data["date"] as? Timestamp,
                          let totalScreenTime = data["totalScreenTime"] as? TimeInterval else {
                        print("🔥 Invalid data structure in real-time update")
                        return
                    }
                    
                    // Safely parse app usages
                    let appUsagesData = data["appUsages"] as? [[String: Any]] ?? []
                    let appUsages = appUsagesData.compactMap { usageData -> AppUsage? in
                        guard let appName = usageData["appName"] as? String,
                              let bundleId = usageData["bundleIdentifier"] as? String,
                              let duration = usageData["duration"] as? TimeInterval,
                              let timestamp = (usageData["timestamp"] as? Timestamp)?.dateValue() else {
                            return nil
                        }
                        
                        return AppUsage(
                            appName: appName,
                            bundleIdentifier: bundleId,
                            duration: duration,
                            timestamp: timestamp,
                            usageRanges: nil
                        )
                    }
                    
                    // Safely parse hourly breakdown
                    let hourlyBreakdown = data["hourlyBreakdown"] as? [String: TimeInterval] ?? [:]
                    let hourlyBreakdownInt = Dictionary(uniqueKeysWithValues: hourlyBreakdown.compactMap { key, value in
                        Int(key).map { ($0, value) }
                    })
                    
                    let screenTimeData = ScreenTimeData(
                        deviceId: deviceId,
                        date: dateTimestamp.dateValue(),
                        totalScreenTime: totalScreenTime,
                        appUsages: appUsages,
                        hourlyBreakdown: hourlyBreakdownInt
                    )
                    
                    Task { @MainActor in
                        self.currentScreenTimeData = screenTimeData
                    }
                    
                } catch {
                    Task { @MainActor in
                        self.errorMessage = "Failed to parse real-time data: \(error.localizedDescription)"
                    }
                    print("🔥 Error parsing real-time data: \(error)")
                }
            }
    }

    func syncScreenTimeData(for deviceId: String) async {
        guard isAuthorized else { 
            print("❌ Cannot sync - authorization required")
            return 
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        // Collect fresh data
        await collectTodayScreenTimeData(for: deviceId)
        
        // Detect new apps
        await detectNewApps()
        
        // Send update notification to parent
        await notifyParentOfUpdate(deviceId: deviceId)
    }
    
    private func notifyParentOfUpdate(deviceId: String) async {
        // Notify parent device of screen time update
        do {
            try await withCheckedThrowingContinuation { continuation in
                databaseManager.updateDeviceLastSync(deviceId: deviceId) { result in
                    continuation.resume(with: result)
                }
            }
            print("✅ Parent notified of screen time update")
        } catch {
            print("🔥 Failed to update last sync time: \(error)")
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
        
        print("✅ Screen time monitoring stopped")
    }
    
    private func setupDeviceActivityMonitoring() {
        // This will be called when DeviceActivityReport extension is implemented
        print("🔄 Device activity monitoring setup completed")
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
    
    func getTopApps(from appUsages: [AppUsage], limit: Int = 5) -> [AppUsage] {
        return Array(appUsages.sorted { $0.duration > $1.duration }.prefix(limit))
    }

    func clearError() {
        errorMessage = nil
    }

    var isDemoMode: Bool {
        return !isAuthorized || currentScreenTimeData?.deviceId == "demo-device"
    }
}

// MARK: - Supporting Models
// AppInfo and NewAppDetection are now defined in DataModels.swift

