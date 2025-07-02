//
//  ActivityMonitoringManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/7/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions
import UIKit

@MainActor
class ActivityMonitoringManager: ObservableObject {
    static let shared = ActivityMonitoringManager()
    
    @Published var isMonitoring = false
    @Published var lastActivityTime: Date?
    @Published var activityStatus: ActivityStatus = .unknown
    
    private let firebaseManager = FirebaseManager.shared
    private let functions = Functions.functions()
    private var activityTimer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    enum ActivityStatus {
        case active
        case inactive
        case unknown
        
        var description: String {
            switch self {
            case .active:
                return "Active"
            case .inactive:
                return "Inactive"
            case .unknown:
                return "Unknown"
            }
        }
        
        var color: String {
            switch self {
            case .active:
                return "green"
            case .inactive:
                return "red"
            case .unknown:
                return "gray"
            }
        }
    }
    
    private init() {
        setupActivityMonitoring()
        setupAppLifecycleObservers()
    }
    
    // MARK: - Activity Monitoring Setup
    
    private func setupActivityMonitoring() {
        // Start monitoring when app becomes active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // Handle app going to background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        // Handle app termination
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    private func setupAppLifecycleObservers() {
        // Monitor app state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appStateChanged),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appStateChanged),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }
    
    // MARK: - Activity Tracking
    
    @objc private func appDidBecomeActive() {
        print("📱 App became active - recording activity")
        recordActivity(type: "app_opened")
        startActivityTimer()
    }
    
    @objc private func appDidEnterBackground() {
        print("📱 App entered background - recording activity")
        recordActivity(type: "app_backgrounded")
        stopActivityTimer()
    }
    
    @objc private func appWillTerminate() {
        print("📱 App will terminate - recording activity")
        recordActivity(type: "app_closed")
        stopActivityTimer()
    }
    
    @objc private func appStateChanged() {
        updateActivityStatus()
    }
    
    // MARK: - Activity Recording
    
    func recordActivity(type: String) {
        Task {
            await recordActivityAsync(type: type)
        }
    }
    
    private func recordActivityAsync(type: String) async {
        guard let currentUser = Auth.auth().currentUser else {
            print("❌ No authenticated user for activity recording")
            return
        }
        
        do {
            let deviceInfo = getDeviceInfo()
            
            // Call Cloud Function to update activity
            let data: [String: Any] = [
                "deviceInfo": deviceInfo,
                "activityType": type
            ]
            
            let result = try await functions.httpsCallable("updateDeviceActivity").call(data)
            
            if let resultData = result.data as? [String: Any],
               let success = resultData["success"] as? Bool,
               success {
                print("✅ Activity recorded successfully: \(type)")
                
                await MainActor.run {
                    self.lastActivityTime = Date()
                    self.updateActivityStatus()
                }
            } else {
                print("❌ Failed to record activity")
            }
            
        } catch {
            print("❌ Error recording activity: \(error)")
            
            // Fallback: Update directly in Firestore
            await updateActivityInFirestore(type: type)
        }
    }
    
    private func updateActivityInFirestore(type: String) async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        do {
            let deviceInfo = getDeviceInfo()
            
            try await firebaseManager.usersCollection.document(currentUser.uid).updateData([
                "lastActiveAt": Timestamp(),
                "deviceInfo": deviceInfo,
                "lastActivityType": type
            ])
            
            // Update parent-child relationships if this is a child device
            let relationshipsQuery = firebaseManager.parentChildRelationshipsCollection
                .whereField("childUserId", isEqualTo: currentUser.uid)
                .whereField("isActive", isEqualTo: true)
            
            let snapshot = try await relationshipsQuery.getDocuments()
            
            if !snapshot.documents.isEmpty {
                let batch = firebaseManager.db.batch()
                
                for doc in snapshot.documents {
                    batch.updateData([
                        "lastSyncAt": Timestamp(),
                        "childDeviceInfo": deviceInfo
                    ], forDocument: doc.reference)
                }
                
                try await batch.commit()
                print("✅ Updated \(snapshot.documents.count) parent-child relationships")
            }
            
        } catch {
            print("❌ Error updating activity in Firestore: \(error)")
        }
    }
    
    // MARK: - Activity Timer
    
    private func startActivityTimer() {
        stopActivityTimer()
        
        // Update activity every 2 minutes while app is active (more frequent for better online status)
        activityTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.recordActivity(type: "app_active")
        }
        
        isMonitoring = true
    }
    
    private func stopActivityTimer() {
        activityTimer?.invalidate()
        activityTimer = nil
        isMonitoring = false
    }
    
    // MARK: - Activity Status
    
    private func updateActivityStatus() {
        guard let lastActivity = lastActivityTime else {
            activityStatus = .unknown
            return
        }
        
        let timeSinceLastActivity = Date().timeIntervalSince(lastActivity)
        let fiveMinutes: TimeInterval = 300
        
        if timeSinceLastActivity < fiveMinutes {
            activityStatus = .active
        } else {
            activityStatus = .inactive
        }
    }
    
    // MARK: - Device Information
    
    private func getDeviceInfo() -> [String: Any] {
        let device = UIDevice.current
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        
        return [
            "deviceModel": device.model,
            "systemName": device.systemName,
            "systemVersion": device.systemVersion,
            "appVersion": appVersion,
            "buildNumber": buildNumber,
            "deviceName": device.name,
            "identifierForVendor": device.identifierForVendor?.uuidString ?? "",
            "batteryLevel": device.batteryLevel,
            "batteryState": device.batteryState.rawValue,
            "timestamp": Timestamp()
        ]
    }
    
    // MARK: - Inactivity Monitoring
    
    func checkForInactivity() async -> Bool {
        guard let currentUser = Auth.auth().currentUser else { return false }
        
        do {
            let userDoc = try await firebaseManager.usersCollection.document(currentUser.uid).getDocument()
            
            guard let data = userDoc.data(),
                  let lastActiveAt = data["lastActiveAt"] as? Timestamp else {
                return false
            }
            
            let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 60 * 60)
            let isInactive = lastActiveAt.dateValue() < threeDaysAgo
            
            if isInactive {
                print("⚠️ User has been inactive for more than 3 days")
                await sendInactivityNotification()
            }
            
            return isInactive
            
        } catch {
            print("❌ Error checking inactivity: \(error)")
            return false
        }
    }
    
    private func sendInactivityNotification() async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        do {
            // Find parent-child relationship
            let relationshipsQuery = firebaseManager.parentChildRelationshipsCollection
                .whereField("childUserId", isEqualTo: currentUser.uid)
                .whereField("isActive", isEqualTo: true)
            
            let snapshot = try await relationshipsQuery.getDocuments()
            
            if let relationship = snapshot.documents.first {
                let relationshipData = relationship.data()
                let parentUserId = relationshipData["parentUserId"] as? String ?? ""
                let childName = relationshipData["childName"] as? String ?? "Child"
                
                // Create notification for parent
                try await firebaseManager.db.collection("notifications").addDocument(data: [
                    "parentUserId": parentUserId,
                    "childUserId": currentUser.uid,
                    "childName": childName,
                    "type": "inactivity_alert",
                    "title": "Child Device Inactive",
                    "message": "\(childName) hasn't opened WatchWise in 3 days. Please check on their device.",
                    "timestamp": Timestamp(),
                    "isRead": false
                ])
                
                print("📧 Sent inactivity notification to parent")
            }
            
        } catch {
            print("❌ Error sending inactivity notification: \(error)")
        }
    }
    
    // MARK: - Background Task Management
    
    func startBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        print("🔄 Starting activity monitoring")
        recordActivity(type: "monitoring_started")
        startActivityTimer()
    }
    
    func stopMonitoring() {
        print("🛑 Stopping activity monitoring")
        recordActivity(type: "monitoring_stopped")
        stopActivityTimer()
        endBackgroundTask()
    }
    
    func getActivitySummary() async -> [String: Any]? {
        guard let currentUser = Auth.auth().currentUser else { return nil }
        
        do {
            let userDoc = try await firebaseManager.usersCollection.document(currentUser.uid).getDocument()
            return userDoc.data()
        } catch {
            print("❌ Error getting activity summary: \(error)")
            return nil
        }
    }
    
    /// Manually update sync time (can be called from child device)
    func updateSyncTime() async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        do {
            // Update user's last active time
            try await firebaseManager.usersCollection.document(currentUser.uid).updateData([
                "lastActiveAt": Timestamp()
            ])
            
            // Update parent-child relationships
            let relationshipsQuery = firebaseManager.parentChildRelationshipsCollection
                .whereField("childUserId", isEqualTo: currentUser.uid)
                .whereField("isActive", isEqualTo: true)
            
            let snapshot = try await relationshipsQuery.getDocuments()
            
            if !snapshot.documents.isEmpty {
                let batch = firebaseManager.db.batch()
                
                for doc in snapshot.documents {
                    batch.updateData([
                        "lastSyncAt": Timestamp()
                    ], forDocument: doc.reference)
                }
                
                try await batch.commit()
                print("✅ Manually updated sync time for \(snapshot.documents.count) relationships")
            }
            
        } catch {
            print("❌ Error manually updating sync time: \(error)")
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        Task { @MainActor in
            stopActivityTimer()
            endBackgroundTask()
        }
    }
} 