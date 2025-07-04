//
//  AppRestrictionManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 7/2/25.
//

import Foundation
import ManagedSettings
import FamilyControls
import FirebaseFirestore
import FirebaseAuth

@MainActor
class AppRestrictionManager: ObservableObject {
    @Published var isRestrictionsEnabled = false
    @Published var currentRestrictions: [String: AppRestriction] = [:]
    @Published var errorMessage: String?
    @Published var isLoading = false
    
    private let store = ManagedSettingsStore()
    private let db = Firestore.firestore()
    private var restrictionTimer: Timer?
    
    // App bundle identifiers for common apps
    private let appBundleIds: [String: String] = [
        "Instagram": "com.burbn.instagram",
        "TikTok": "com.zhiliaoapp.musically",
        "YouTube": "com.google.ios.youtube",
        "Safari": "com.apple.mobilesafari",
        "Messages": "com.apple.MobileSMS",
        "Snapchat": "com.toyopagroup.picaboo",
        "WhatsApp": "com.whatsapp.WhatsApp",
        "Facebook": "com.facebook.Facebook",
        "Twitter": "com.twitter.ios",
        "Discord": "com.hammerandchisel.discord",
        "Reddit": "com.reddit.Reddit",
        "Netflix": "com.netflix.Netflix",
        "Spotify": "com.spotify.client",
        "Minecraft": "com.mojang.minecraftpe",
        "Roblox": "com.roblox.client",
        "Fortnite": "com.epicgames.fortnite",
        "Call of Duty": "com.activision.callofduty.shooter",
        "PUBG": "com.tencent.ig",
        "Genshin Impact": "com.mihoyo.genshinimpact",
        "Among Us": "com.innersloth.spacemafia"
    ]
    
    init() {
        loadRestrictions()
        startRestrictionMonitoring()
    }
    
    deinit {
        restrictionTimer?.invalidate()
    }
    
    // MARK: - App Restriction Management
    
    func setAppLimit(bundleId: String, timeLimit: TimeInterval) async {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "Authentication required"
            return
        }
        
        isLoading = true
        
        do {
            // Create or update restriction
            let restriction = AppRestriction(
                bundleId: bundleId,
                timeLimit: timeLimit,
                isDisabled: false,
                dailyUsage: 0,
                lastResetDate: Date(),
                parentId: currentUser.uid
            )
            
            // Save to Firebase
            try await saveRestrictionToFirebase(restriction)
            
            // Update local state
            currentRestrictions[bundleId] = restriction
            
            // Apply restriction to child device
            await applyRestrictionToDevice(restriction)
            
            print("✅ Set app limit for \(bundleId): \(timeLimit/3600) hours")
            
        } catch {
            errorMessage = "Failed to set app limit: \(error.localizedDescription)"
            print("❌ Error setting app limit: \(error)")
        }
        
        isLoading = false
    }
    
    func disableApp(bundleId: String) async {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "Authentication required"
            return
        }
        
        isLoading = true
        
        do {
            // Get existing restriction or create new one
            var restriction = currentRestrictions[bundleId] ?? AppRestriction(
                bundleId: bundleId,
                timeLimit: 0,
                isDisabled: true,
                dailyUsage: 0,
                lastResetDate: Date(),
                parentId: currentUser.uid
            )
            
            restriction.isDisabled = true
            
            // Save to Firebase
            try await saveRestrictionToFirebase(restriction)
            
            // Update local state
            currentRestrictions[bundleId] = restriction
            
            // Apply restriction to child device
            await applyRestrictionToDevice(restriction)
            
            print("✅ Disabled app: \(bundleId)")
            
        } catch {
            errorMessage = "Failed to disable app: \(error.localizedDescription)"
            print("❌ Error disabling app: \(error)")
        }
        
        isLoading = false
    }
    
    func enableApp(bundleId: String) async {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "Authentication required"
            return
        }
        
        isLoading = true
        
        do {
            guard var restriction = currentRestrictions[bundleId] else {
                errorMessage = "App restriction not found"
                return
            }
            
            restriction.isDisabled = false
            
            // Save to Firebase
            try await saveRestrictionToFirebase(restriction)
            
            // Update local state
            currentRestrictions[bundleId] = restriction
            
            // Apply restriction to child device
            await applyRestrictionToDevice(restriction)
            
            print("✅ Enabled app: \(bundleId)")
            
        } catch {
            errorMessage = "Failed to enable app: \(error.localizedDescription)"
            print("❌ Error enabling app: \(error)")
        }
        
        isLoading = false
    }
    
    func removeAppFromMonitoring(bundleId: String) async {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "Authentication required"
            return
        }
        
        isLoading = true
        
        do {
            // Remove from Firebase
            try await db.collection("appRestrictions")
                .whereField("bundleId", isEqualTo: bundleId)
                .whereField("parentId", isEqualTo: currentUser.uid)
                .getDocuments()
                .documents
                .forEach { document in
                    document.reference.delete()
                }
            
            // Remove from local state
            currentRestrictions.removeValue(forKey: bundleId)
            
            // Remove restriction from child device
            await removeRestrictionFromDevice(bundleId)
            
            print("✅ Removed app from monitoring: \(bundleId)")
            
        } catch {
            errorMessage = "Failed to remove app: \(error.localizedDescription)"
            print("❌ Error removing app: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Bedtime Restrictions
    
    func setBedtimeRestrictions(settings: BedtimeSettings) async {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "Authentication required"
            return
        }
        
        isLoading = true
        
        do {
            // Save bedtime settings to Firebase
            try await db.collection("users")
                .document(currentUser.uid)
                .collection("settings")
                .document("bedtime")
                .setData([
                    "isEnabled": settings.isEnabled,
                    "startTime": settings.startTime,
                    "endTime": settings.endTime,
                    "enabledDays": settings.enabledDays,
                    "lastUpdated": Timestamp()
                ])
            
            // Apply bedtime restrictions to all monitored apps
            if settings.isEnabled {
                await applyBedtimeRestrictions(settings: settings)
            } else {
                await removeBedtimeRestrictions()
            }
            
            print("✅ Bedtime restrictions updated")
            
        } catch {
            errorMessage = "Failed to set bedtime restrictions: \(error.localizedDescription)"
            print("❌ Error setting bedtime restrictions: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Usage Tracking
    
    func updateAppUsage(bundleId: String, usageTime: TimeInterval) async {
        guard var restriction = currentRestrictions[bundleId] else { return }
        
        // Check if it's a new day and reset usage
        if !Calendar.current.isDate(restriction.lastResetDate, inSameDayAs: Date()) {
            restriction.dailyUsage = 0
            restriction.lastResetDate = Date()
        }
        
        restriction.dailyUsage += usageTime
        
        // Check if limit exceeded
        if restriction.timeLimit > 0 && restriction.dailyUsage >= restriction.timeLimit {
            await disableApp(bundleId: bundleId)
            await sendLimitExceededNotification(bundleId: bundleId)
        }
        
        // Update Firebase
        try? await saveRestrictionToFirebase(restriction)
        currentRestrictions[bundleId] = restriction
    }
    
    // MARK: - Private Methods
    
    private func saveRestrictionToFirebase(_ restriction: AppRestriction) async throws {
        let data: [String: Any] = [
            "bundleId": restriction.bundleId,
            "timeLimit": restriction.timeLimit,
            "isDisabled": restriction.isDisabled,
            "dailyUsage": restriction.dailyUsage,
            "lastResetDate": Timestamp(date: restriction.lastResetDate),
            "parentId": restriction.parentId,
            "lastUpdated": Timestamp()
        ]
        
        try await db.collection("appRestrictions")
            .document("\(restriction.parentId)_\(restriction.bundleId)")
            .setData(data, merge: true)
    }
    
    private func loadRestrictions() {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        Task {
            do {
                let snapshot = try await db.collection("appRestrictions")
                    .whereField("parentId", isEqualTo: currentUser.uid)
                    .getDocuments()
                
                let restrictions = try snapshot.documents.compactMap { document -> AppRestriction? in
                    try document.data(as: AppRestriction.self)
                }
                
                await MainActor.run {
                    for restriction in restrictions {
                        self.currentRestrictions[restriction.bundleId] = restriction
                    }
                }
                
            } catch {
                print("❌ Error loading restrictions: \(error)")
            }
        }
    }
    
    private func applyRestrictionToDevice(_ restriction: AppRestriction) async {
        // This would apply restrictions to the child device
        // For now, we'll store the restriction data that the child app can read
        let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
        
        let restrictionData: [String: Any] = [
            "bundleId": restriction.bundleId,
            "timeLimit": restriction.timeLimit,
            "isDisabled": restriction.isDisabled,
            "dailyUsage": restriction.dailyUsage,
            "lastResetDate": restriction.lastResetDate.timeIntervalSince1970
        ]
        
        userDefaults?.set(restrictionData, forKey: "app_restriction_\(restriction.bundleId)")
        userDefaults?.set(Date().timeIntervalSince1970, forKey: "last_restriction_update")
        
        print("📱 Applied restriction to device: \(restriction.bundleId)")
    }
    
    private func removeRestrictionFromDevice(_ bundleId: String) async {
        let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
        userDefaults?.removeObject(forKey: "app_restriction_\(bundleId)")
        userDefaults?.set(Date().timeIntervalSince1970, forKey: "last_restriction_update")
        
        print("📱 Removed restriction from device: \(bundleId)")
    }
    
    private func applyBedtimeRestrictions(settings: BedtimeSettings) async {
        let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
        
        let bedtimeData: [String: Any] = [
            "isEnabled": settings.isEnabled,
            "startTime": settings.startTime,
            "endTime": settings.endTime,
            "enabledDays": settings.enabledDays
        ]
        
        userDefaults?.set(bedtimeData, forKey: "bedtime_settings")
        userDefaults?.set(Date().timeIntervalSince1970, forKey: "last_bedtime_update")
        
        print("🌙 Applied bedtime restrictions")
    }
    
    private func removeBedtimeRestrictions() async {
        let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
        userDefaults?.removeObject(forKey: "bedtime_settings")
        userDefaults?.set(Date().timeIntervalSince1970, forKey: "last_bedtime_update")
        
        print("🌙 Removed bedtime restrictions")
    }
    
    private func sendLimitExceededNotification(bundleId: String) async {
        // Send notification to parent about limit exceeded
        guard let currentUser = Auth.auth().currentUser else { return }
        
        let appName = getAppName(for: bundleId)
        
        do {
            try await db.collection("notifications").addDocument(data: [
                "parentId": currentUser.uid,
                "type": "app_limit_exceeded",
                "title": "App Time Limit Exceeded",
                "message": "\(appName) has reached its daily time limit",
                "bundleId": bundleId,
                "timestamp": Timestamp(),
                "isRead": false
            ])
            
            print("🔔 Sent limit exceeded notification for \(appName)")
            
        } catch {
            print("❌ Error sending notification: \(error)")
        }
    }
    
    private func startRestrictionMonitoring() {
        // Check restrictions every minute
        restrictionTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkBedtimeRestrictions()
            }
        }
    }
    
    private func checkBedtimeRestrictions() async {
        let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
        
        guard let bedtimeData = userDefaults?.dictionary(forKey: "bedtime_settings"),
              let isEnabled = bedtimeData["isEnabled"] as? Bool,
              isEnabled,
              let startTime = bedtimeData["startTime"] as? String,
              let endTime = bedtimeData["endTime"] as? String,
              let enabledDays = bedtimeData["enabledDays"] as? [Int] else {
            return
        }
        
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentDay = calendar.component(.weekday, from: now)
        
        // Check if current day is enabled
        guard enabledDays.contains(currentDay) else { return }
        
        // Parse bedtime times
        let startComponents = startTime.components(separatedBy: ":")
        let endComponents = endTime.components(separatedBy: ":")
        
        guard let startHour = Int(startComponents[0]),
              let startMinute = Int(startComponents[1]),
              let endHour = Int(endComponents[0]),
              let endMinute = Int(endComponents[1]) else {
            return
        }
        
        let currentTimeInMinutes = currentHour * 60 + currentMinute
        let startTimeInMinutes = startHour * 60 + startMinute
        let endTimeInMinutes = endHour * 60 + endMinute
        
        // Check if we're in bedtime hours
        let isBedtime = if startTimeInMinutes <= endTimeInMinutes {
            // Same day bedtime (e.g., 10 PM to 6 AM)
            currentTimeInMinutes >= startTimeInMinutes || currentTimeInMinutes < endTimeInMinutes
        } else {
            // Overnight bedtime (e.g., 10 PM to 6 AM)
            currentTimeInMinutes >= startTimeInMinutes || currentTimeInMinutes < endTimeInMinutes
        }
        
        if isBedtime {
            await applyBedtimeRestrictions(settings: BedtimeSettings(
                isEnabled: true,
                startTime: startTime,
                endTime: endTime,
                enabledDays: enabledDays
            ))
        }
    }
    
    // MARK: - Utility Methods
    
    func getAppName(for bundleId: String) -> String {
        for (name, id) in appBundleIds {
            if id == bundleId {
                return name
            }
        }
        return bundleId.components(separatedBy: ".").last ?? bundleId
    }
    
    func getBundleId(for appName: String) -> String? {
        return appBundleIds[appName]
    }
    
    func getAllAppNames() -> [String] {
        return Array(appBundleIds.keys).sorted()
    }
    
    func isAppRestricted(bundleId: String) -> Bool {
        return currentRestrictions[bundleId]?.isDisabled ?? false
    }
    
    func getAppLimit(bundleId: String) -> TimeInterval {
        return currentRestrictions[bundleId]?.timeLimit ?? 0
    }
    
    func getAppUsage(bundleId: String) -> TimeInterval {
        return currentRestrictions[bundleId]?.dailyUsage ?? 0
    }
}

// MARK: - App Restriction Model
struct AppRestriction: Codable, Identifiable {
    let id = UUID()
    let bundleId: String
    let timeLimit: TimeInterval // in seconds
    var isDisabled: Bool
    var dailyUsage: TimeInterval // in seconds
    var lastResetDate: Date
    let parentId: String
    
    enum CodingKeys: String, CodingKey {
        case bundleId, timeLimit, isDisabled, dailyUsage, lastResetDate, parentId
    }
    
    var formattedTimeLimit: String {
        let hours = Int(timeLimit) / 3600
        let minutes = Int(timeLimit) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    var formattedDailyUsage: String {
        let hours = Int(dailyUsage) / 3600
        let minutes = Int(dailyUsage) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    var usagePercentage: Double {
        guard timeLimit > 0 else { return 0 }
        return min(dailyUsage / timeLimit, 1.0)
    }
} 