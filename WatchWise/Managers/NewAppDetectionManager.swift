//
//  NewAppDetectionManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 7/2/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class NewAppDetectionManager: ObservableObject {
    @Published var newAppDetections: [WatchWise.NewAppDetection] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    private let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
    
    init() {
        loadNewAppDetections()
        startDetectionMonitoring()
    }
    
    // MARK: - New App Detection
    
    func checkForNewApps() async {
        guard let userDefaults = userDefaults,
              let newAppBundleIds = userDefaults.array(forKey: "new_app_detections") as? [String] else {
            return
        }
        
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "Authentication required"
            return
        }
        
        isLoading = true
        
        do {
            for bundleId in newAppBundleIds {
                // Check if we already processed this app
                if !newAppDetections.contains(where: { $0.bundleIdentifier == bundleId }) {
                    let appName = getAppName(for: bundleId)
                    let detection = WatchWise.NewAppDetection(
                        appName: appName,
                        bundleIdentifier: bundleId,
                        category: "Unknown",
                        detectedAt: Date(),
                        deviceId: nil
                    )
                    
                    // Save to Firebase
                    try await saveNewAppDetection(detection)
                    
                    // Add to local state
                    newAppDetections.append(detection)
                    
                    // Send notification to parent
                    await sendNewAppNotification(detection)
                    
                    print("🆕 New app detected: \(appName) (\(bundleId))")
                }
            }
            
            // Clear the detection list after processing
            userDefaults.removeObject(forKey: "new_app_detections")
            
        } catch {
            errorMessage = "Failed to process new app detections: \(error.localizedDescription)"
            print("❌ Error processing new app detections: \(error)")
        }
        
        isLoading = false
    }
    
    func addAppToMonitoring(_ detection: WatchWise.NewAppDetection) async {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "Authentication required"
            return
        }
        
        do {
            // Create default app restriction (2 hours limit)
            let restriction = AppRestriction(
                bundleId: detection.bundleIdentifier,
                timeLimit: 2.0 * 3600.0, // 2 hours in seconds
                isDisabled: false,
                dailyUsage: 0,
                lastResetDate: Date(),
                parentId: currentUser.uid
            )
            
            // Save restriction to Firebase
            try await db.collection("appRestrictions")
                .document("\(currentUser.uid)_\(detection.bundleIdentifier)")
                .setData([
                    "bundleId": restriction.bundleId,
                    "timeLimit": restriction.timeLimit,
                    "isDisabled": restriction.isDisabled,
                    "dailyUsage": restriction.dailyUsage,
                    "lastResetDate": Timestamp(date: restriction.lastResetDate),
                    "parentId": restriction.parentId,
                    "lastUpdated": Timestamp()
                ])
            
            // Mark detection as processed
            try await markDetectionAsProcessed(detection)
            
            // Update local state - remove from list since it's processed
            newAppDetections.removeAll(where: { $0.id == detection.id })
            
            print("✅ Added \(detection.appName) to monitoring")
            
        } catch {
            errorMessage = "Failed to add app to monitoring: \(error.localizedDescription)"
            print("❌ Error adding app to monitoring: \(error)")
        }
    }
    
    func ignoreNewApp(_ detection: WatchWise.NewAppDetection) async {
        do {
            // Mark detection as processed (ignored)
            try await markDetectionAsProcessed(detection)
            
            // Update local state - remove from list since it's processed
            newAppDetections.removeAll(where: { $0.id == detection.id })
            
            print("❌ Ignored new app: \(detection.appName)")
            
        } catch {
            errorMessage = "Failed to ignore app: \(error.localizedDescription)"
            print("❌ Error ignoring app: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func loadNewAppDetections() {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        Task {
            do {
                let snapshot = try await db.collection("newAppDetections")
                    .whereField("parentId", isEqualTo: currentUser.uid)
                    .order(by: "detectedAt", descending: true)
                    .getDocuments()
                
                let detections = try snapshot.documents.compactMap { document -> WatchWise.NewAppDetection? in
                    try document.data(as: WatchWise.NewAppDetection.self)
                }
                
                await MainActor.run {
                    self.newAppDetections = detections
                }
                
            } catch {
                print("❌ Error loading new app detections: \(error)")
            }
        }
    }
    
    private func saveNewAppDetection(_ detection: WatchWise.NewAppDetection) async throws {
        let data: [String: Any] = [
            "bundleIdentifier": detection.bundleIdentifier,
            "appName": detection.appName,
            "category": detection.category,
            "detectedAt": Timestamp(date: detection.detectedAt),
            "deviceId": detection.deviceId ?? "",
            "parentId": Auth.auth().currentUser?.uid ?? ""
        ]
        
        try await db.collection("newAppDetections")
            .document("\(Auth.auth().currentUser?.uid ?? "")_\(detection.bundleIdentifier)")
            .setData(data, merge: true)
    }
    
    private func markDetectionAsProcessed(_ detection: WatchWise.NewAppDetection) async throws {
        try await db.collection("newAppDetections")
            .document("\(Auth.auth().currentUser?.uid ?? "")_\(detection.bundleIdentifier)")
            .updateData([
                "isProcessed": true,
                "processedAt": Timestamp()
            ])
    }
    
    private func sendNewAppNotification(_ detection: WatchWise.NewAppDetection) async {
        do {
            try await db.collection("notifications").addDocument(data: [
                "parentId": Auth.auth().currentUser?.uid ?? "",
                "type": "new_app_detected",
                "title": "New App Detected",
                "message": "\(detection.appName) has been installed on your child's device",
                "bundleIdentifier": detection.bundleIdentifier,
                "timestamp": Timestamp(),
                "isRead": false,
                "data": [
                    "detectionId": detection.id.uuidString
                ]
            ])
            
            print("🔔 Sent new app notification for \(detection.appName)")
            
        } catch {
            print("❌ Error sending new app notification: \(error)")
        }
    }
    
    private func startDetectionMonitoring() {
        // Check for new apps every 5 minutes
        Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForNewApps()
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
}

 