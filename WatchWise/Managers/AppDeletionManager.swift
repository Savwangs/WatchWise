//
//  AppDeletionManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 7/2/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class AppDeletionManager: ObservableObject {
    @Published var deletedApps: [DeletedApp] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    private let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
    private var deletionTimer: Timer?
    
    init() {
        startDeletionMonitoring()
    }
    
    deinit {
        deletionTimer?.invalidate()
    }
    
    // MARK: - App Deletion Detection
    
    func checkForDeletedApps() async {
        guard let userDefaults = userDefaults,
              let currentUser = Auth.auth().currentUser else {
            return
        }
        
        isLoading = true
        
        do {
            // Get previously known apps from DeviceActivityReport
            let knownApps = userDefaults.array(forKey: "known_apps") as? [String] ?? []
            
            // Get current apps from DeviceActivityReport
            let currentApps = getCurrentAppsFromDeviceActivity()
            
            // Find deleted apps (apps that were known but are no longer present)
            let deletedAppBundleIds = Set(knownApps).subtracting(currentApps)
            
            for bundleId in deletedAppBundleIds {
                // Check if we already processed this deletion
                if !deletedApps.contains(where: { $0.bundleId == bundleId }) {
                    let appName = getAppName(for: bundleId)
                    let deletedApp = DeletedApp(
                        bundleId: bundleId,
                        appName: appName,
                        deletedAt: Date(),
                        parentId: currentUser.uid,
                        wasMonitored: wasAppMonitored(bundleId: bundleId),
                        isProcessed: false
                    )
                    
                    // Save to Firebase
                    try await saveDeletedAppToFirebase(deletedApp)
                    
                    // Add to local state
                    deletedApps.append(deletedApp)
                    
                                // App deleted (no notification)
            print("🗑️ App deleted: \(deletedApp.appName)")
                    
                    print("🗑️ App deleted: \(appName) (\(bundleId))")
                }
            }
            
            // Update known apps list with current apps
            userDefaults.set(Array(currentApps), forKey: "known_apps")
            
        } catch {
            errorMessage = "Failed to check for deleted apps: \(error.localizedDescription)"
            print("❌ Error checking for deleted apps: \(error)")
        }
        
        isLoading = false
    }
    
    func markDeletionAsProcessed(_ deletedApp: DeletedApp) async {
        do {
            try await db.collection("deletedApps")
                .document("\(deletedApp.parentId)_\(deletedApp.bundleId)")
                .updateData([
                    "isProcessed": true,
                    "processedAt": Timestamp()
                ])
            
            // Update local state
            if let index = deletedApps.firstIndex(where: { $0.id == deletedApp.id }) {
                deletedApps[index].isProcessed = true
            }
            
            print("✅ Marked deletion as processed: \(deletedApp.appName)")
            
        } catch {
            errorMessage = "Failed to mark deletion as processed: \(error.localizedDescription)"
            print("❌ Error marking deletion as processed: \(error)")
        }
    }
    
    func restoreAppToMonitoring(_ deletedApp: DeletedApp) async {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "Authentication required"
            return
        }
        
        do {
            // Create app restriction for the restored app
            let restriction = AppRestriction(
                bundleId: deletedApp.bundleId,
                timeLimit: 2.0 * 3600.0, // 2 hours default
                isDisabled: false,
                dailyUsage: 0,
                lastResetDate: Date(),
                parentId: currentUser.uid
            )
            
            // Save restriction to Firebase
            try await db.collection("appRestrictions")
                .document("\(currentUser.uid)_\(deletedApp.bundleId)")
                .setData([
                    "bundleId": restriction.bundleId,
                    "timeLimit": restriction.timeLimit,
                    "isDisabled": restriction.isDisabled,
                    "dailyUsage": restriction.dailyUsage,
                    "lastResetDate": Timestamp(date: restriction.lastResetDate),
                    "parentId": restriction.parentId,
                    "lastUpdated": Timestamp()
                ])
            
            // Mark deletion as processed
            await markDeletionAsProcessed(deletedApp)
            
            // Add back to known apps
            let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
            var knownApps = userDefaults?.array(forKey: "known_apps") as? [String] ?? []
            if !knownApps.contains(deletedApp.bundleId) {
                knownApps.append(deletedApp.bundleId)
                userDefaults?.set(knownApps, forKey: "known_apps")
            }
            
            print("✅ Restored \(deletedApp.appName) to monitoring")
            
        } catch {
            errorMessage = "Failed to restore app: \(error.localizedDescription)"
            print("❌ Error restoring app: \(error)")
        }
    }
    
    func removeAppFromMonitoring(_ deletedApp: DeletedApp) async {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "Authentication required"
            return
        }
        
        do {
            // Remove app restriction from Firebase
            try await db.collection("appRestrictions")
                .document("\(currentUser.uid)_\(deletedApp.bundleId)")
                .delete()
            
            // Mark deletion as processed
            await markDeletionAsProcessed(deletedApp)
            
            // Remove from known apps
            let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
            var knownApps = userDefaults?.array(forKey: "known_apps") as? [String] ?? []
            knownApps.removeAll { $0 == deletedApp.bundleId }
            userDefaults?.set(knownApps, forKey: "known_apps")
            
            print("✅ Removed \(deletedApp.appName) from monitoring")
            
        } catch {
            errorMessage = "Failed to remove app from monitoring: \(error.localizedDescription)"
            print("❌ Error removing app from monitoring: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func getCurrentAppsFromDeviceActivity() -> Set<String> {
        guard let userDefaults = userDefaults else { return [] }
        
        var currentApps: Set<String> = []
        
        // Get apps from detailed usage data
        if let appUsageData = userDefaults.array(forKey: "detailed_app_usage_data") as? [[String: Any]] {
            for appData in appUsageData {
                if let bundleId = appData["bundleIdentifier"] as? String {
                    currentApps.insert(bundleId)
                }
            }
        }
        
        // Also check individual app usage data
        for (key, _) in userDefaults.dictionaryRepresentation() {
            if key.hasPrefix("app_usage_") {
                let bundleId = String(key.dropFirst("app_usage_".count))
                currentApps.insert(bundleId)
            }
        }
        
        return currentApps
    }
    
    private func wasAppMonitored(bundleId: String) -> Bool {
        guard let userDefaults = userDefaults else { return false }
        
        // Check if app had restrictions
        if let restrictionData = userDefaults.dictionary(forKey: "app_restriction_\(bundleId)") {
            return restrictionData["timeLimit"] as? TimeInterval ?? 0 > 0
        }
        
        return false
    }
    
    private func saveDeletedAppToFirebase(_ deletedApp: DeletedApp) async throws {
        let data: [String: Any] = [
            "bundleId": deletedApp.bundleId,
            "appName": deletedApp.appName,
            "deletedAt": Timestamp(date: deletedApp.deletedAt),
            "parentId": deletedApp.parentId,
            "wasMonitored": deletedApp.wasMonitored,
            "isProcessed": deletedApp.isProcessed
        ]
        
        try await db.collection("deletedApps")
            .document("\(deletedApp.parentId)_\(deletedApp.bundleId)")
            .setData(data, merge: true)
    }
    

    
    private func startDeletionMonitoring() {
        // Check for deleted apps every 10 minutes
        deletionTimer = Timer.scheduledTimer(withTimeInterval: 600.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForDeletedApps()
            }
        }
    }
    
    private func getAppName(for bundleId: String) -> String {
        let appNameMapping: [String: String] = [
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
        
        return appNameMapping[bundleId] ?? bundleId.components(separatedBy: ".").last ?? bundleId
    }
    
    // MARK: - Utility Methods
    
    func loadDeletedApps() {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        Task {
            do {
                let snapshot = try await db.collection("deletedApps")
                    .whereField("parentId", isEqualTo: currentUser.uid)
                    .whereField("isProcessed", isEqualTo: false)
                    .order(by: "deletedAt", descending: true)
                    .getDocuments()
                
                let deletedApps = try snapshot.documents.compactMap { document -> DeletedApp? in
                    try document.data(as: DeletedApp.self)
                }
                
                await MainActor.run {
                    self.deletedApps = deletedApps
                }
                
            } catch {
                print("❌ Error loading deleted apps: \(error)")
            }
        }
    }
    
    func clearError() {
        errorMessage = nil
    }
}

// MARK: - Deleted App Model
struct DeletedApp: Codable, Identifiable {
    let id = UUID()
    let bundleId: String
    let appName: String
    let deletedAt: Date
    let parentId: String
    let wasMonitored: Bool
    var isProcessed: Bool
    
    enum CodingKeys: String, CodingKey {
        case bundleId, appName, deletedAt, parentId, wasMonitored, isProcessed
    }
    
    var formattedDeletedAt: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: deletedAt, relativeTo: Date())
    }
} 