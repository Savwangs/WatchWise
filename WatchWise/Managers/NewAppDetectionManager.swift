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
    @Published var newAppDetections: [NewAppDetection] = []
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
                if !newAppDetections.contains(where: { $0.bundleId == bundleId }) {
                    let appName = getAppName(for: bundleId)
                    let detection = NewAppDetection(
                        bundleId: bundleId,
                        appName: appName,
                        detectedAt: Date(),
                        parentId: currentUser.uid,
                        isProcessed: false
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
    
    func addAppToMonitoring(_ detection: NewAppDetection) async {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "Authentication required"
            return
        }
        
        do {
            // Create default app restriction (2 hours limit)
            let restriction = AppRestriction(
                bundleId: detection.bundleId,
                timeLimit: 2.0 * 3600.0, // 2 hours in seconds
                isDisabled: false,
                dailyUsage: 0,
                lastResetDate: Date(),
                parentId: currentUser.uid
            )
            
            // Save restriction to Firebase
            try await db.collection("appRestrictions")
                .document("\(currentUser.uid)_\(detection.bundleId)")
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
            
            // Update local state
            if let index = newAppDetections.firstIndex(where: { $0.id == detection.id }) {
                newAppDetections[index].isProcessed = true
            }
            
            print("✅ Added \(detection.appName) to monitoring")
            
        } catch {
            errorMessage = "Failed to add app to monitoring: \(error.localizedDescription)"
            print("❌ Error adding app to monitoring: \(error)")
        }
    }
    
    func ignoreNewApp(_ detection: NewAppDetection) async {
        do {
            // Mark detection as processed (ignored)
            try await markDetectionAsProcessed(detection)
            
            // Update local state
            if let index = newAppDetections.firstIndex(where: { $0.id == detection.id }) {
                newAppDetections[index].isProcessed = true
            }
            
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
                    .whereField("isProcessed", isEqualTo: false)
                    .order(by: "detectedAt", descending: true)
                    .getDocuments()
                
                let detections = try snapshot.documents.compactMap { document -> NewAppDetection? in
                    try document.data(as: NewAppDetection.self)
                }
                
                await MainActor.run {
                    self.newAppDetections = detections
                }
                
            } catch {
                print("❌ Error loading new app detections: \(error)")
            }
        }
    }
    
    private func saveNewAppDetection(_ detection: NewAppDetection) async throws {
        let data: [String: Any] = [
            "bundleId": detection.bundleId,
            "appName": detection.appName,
            "detectedAt": Timestamp(date: detection.detectedAt),
            "parentId": detection.parentId,
            "isProcessed": detection.isProcessed
        ]
        
        try await db.collection("newAppDetections")
            .document("\(detection.parentId)_\(detection.bundleId)")
            .setData(data, merge: true)
    }
    
    private func markDetectionAsProcessed(_ detection: NewAppDetection) async throws {
        try await db.collection("newAppDetections")
            .document("\(detection.parentId)_\(detection.bundleId)")
            .updateData([
                "isProcessed": true,
                "processedAt": Timestamp()
            ])
    }
    
    private func sendNewAppNotification(_ detection: NewAppDetection) async {
        do {
            try await db.collection("notifications").addDocument(data: [
                "parentId": detection.parentId,
                "type": "new_app_detected",
                "title": "New App Detected",
                "message": "\(detection.appName) has been installed on your child's device",
                "bundleId": detection.bundleId,
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

// MARK: - New App Detection Model
struct NewAppDetection: Codable, Identifiable {
    let id = UUID()
    let bundleId: String
    let appName: String
    let detectedAt: Date
    let parentId: String
    var isProcessed: Bool
    
    enum CodingKeys: String, CodingKey {
        case bundleId, appName, detectedAt, parentId, isProcessed
    }
} 