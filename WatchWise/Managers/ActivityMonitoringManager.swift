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
import BackgroundTasks

@MainActor
class ActivityMonitoringManager: ObservableObject {
    static let shared = ActivityMonitoringManager()
    
    @Published var isMonitoring = false
    @Published var lastActivityTime: Date?
    @Published var activityStatus: ActivityStatus = .unknown
    @Published var missedHeartbeats: Int = 0
    
    private let firebaseManager = FirebaseManager.shared
    private let functions = Functions.functions()
    private var heartbeatTimer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var isChildUser: Bool = false
    
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
        checkUserType()
    }
    
    // MARK: - User Type Detection
    
    private func checkUserType() {
        // Check if current user is a child
        if let userType = UserDefaults.standard.string(forKey: "userType") {
            isChildUser = (userType == "Child")
        } else if let currentUser = Auth.auth().currentUser {
            // Fallback: check Firebase for user type
            Task {
                await loadUserTypeFromFirebase(userId: currentUser.uid)
            }
        }
    }
    
    private func loadUserTypeFromFirebase(userId: String) async {
        do {
            let userDoc = try await firebaseManager.usersCollection.document(userId).getDocument()
            if let data = userDoc.data(),
               let userType = data["userType"] as? String {
                await MainActor.run {
                    self.isChildUser = (userType == "Child")
                    if self.isChildUser {
                        self.startHeartbeatMonitoring()
                    }
                }
            }
        } catch {
            print("❌ Error loading user type: \(error)")
        }
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
    
    // MARK: - Heartbeat System (Child Devices Only)
    
    func startHeartbeatMonitoring() {
        guard isChildUser else {
            print("📱 Not a child user - skipping heartbeat monitoring")
            return
        }
        
        print("💓 Starting heartbeat monitoring for child device")
        stopHeartbeatMonitoring()
        
        // Send initial heartbeat
        Task {
            await sendHeartbeat()
        }
        
        // Start timer for heartbeats (30 seconds for testing, change back to 900 for production)
        let heartbeatInterval: TimeInterval = 30 // 30 seconds for testing, 900 for production
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.sendHeartbeat()
            }
        }
        
        isMonitoring = true
        
        // Register background task for heartbeat monitoring
        registerBackgroundTask()
    }
    
    func stopHeartbeatMonitoring() {
        print("💓 Stopping heartbeat monitoring")
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        isMonitoring = false
        endBackgroundTask()
    }
    
    func sendHeartbeat() async {
        guard isChildUser else { return }
        
        print("💓 Sending heartbeat...")
        await sendHeartbeatAsync()
    }
    
    private func sendHeartbeatAsync() async {
        guard let currentUser = Auth.auth().currentUser else {
            print("❌ No authenticated user for heartbeat")
            return
        }
        
        print("💓 Starting heartbeat process for user: \(currentUser.uid)")
        
        do {
            let deviceInfo = getDeviceInfo()
            print("📱 Device info prepared: \(deviceInfo)")
            
            // Call Cloud Function to update heartbeat
            let data: [String: Any] = [
                "deviceInfo": deviceInfo,
                "activityType": "heartbeat",
                "timestamp": Timestamp()
            ]
            
            print("📤 Calling cloud function with data: \(data)")
            let result = try await functions.httpsCallable("updateDeviceActivity").call(data)
            print("📥 Cloud function response received: \(result.data ?? "nil")")
            
            if let resultData = result.data as? [String: Any] {
                print("📊 Result data: \(resultData)")
                
                if let success = resultData["success"] as? Bool {
                    if success {
                        print("✅ Heartbeat sent successfully")
                        
                        await MainActor.run {
                            self.lastActivityTime = Date()
                            self.missedHeartbeats = 0
                            self.updateActivityStatus()
                        }
                    } else {
                        print("❌ Cloud function returned success: false")
                        if let error = resultData["error"] as? String {
                            print("❌ Cloud function error: \(error)")
                        }
                        await handleMissedHeartbeat()
                    }
                } else {
                    print("❌ No success field in response")
                    await handleMissedHeartbeat()
                }
            } else {
                print("❌ Invalid response format from cloud function")
                await handleMissedHeartbeat()
            }
            
        } catch {
            print("❌ Error sending heartbeat: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            await handleMissedHeartbeat()
        }
    }
    
    private func handleMissedHeartbeat() async {
        await MainActor.run {
            missedHeartbeats += 1
        }
        
        // Send notification to parent about missed heartbeat
        await notifyParentOfMissedHeartbeat()
    }
    
    private func notifyParentOfMissedHeartbeat() async {
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
                
                // Determine notification message based on missed heartbeats
                let (title, message) = getMissedHeartbeatMessage(missedHeartbeats: missedHeartbeats, childName: childName)
                
                // Create notification for parent
                try await firebaseManager.db.collection("notifications").addDocument(data: [
                    "parentUserId": parentUserId,
                    "childUserId": currentUser.uid,
                    "childName": childName,
                    "type": "missed_heartbeat",
                    "title": title,
                    "message": message,
                    "missedHeartbeats": missedHeartbeats,
                    "timestamp": Timestamp(),
                    "isRead": false
                ])
                
                print("📧 Sent missed heartbeat notification to parent: \(title)")
            }
            
        } catch {
            print("❌ Error sending missed heartbeat notification: \(error)")
        }
    }
    
    private func getMissedHeartbeatMessage(missedHeartbeats: Int, childName: String) -> (String, String) {
        switch missedHeartbeats {
        case 1:
            return (
                "First Heartbeat Missed",
                "\(childName)'s device missed its first heartbeat. This could indicate the app was closed or the device is having connectivity issues."
            )
        case 2:
            return (
                "Second Heartbeat Missed",
                "\(childName)'s device has missed 2 consecutive heartbeats. The app may have been deleted or the device is turned off."
            )
        case 3, 4:
            return (
                "Multiple Heartbeats Missed",
                "\(childName)'s device has missed \(missedHeartbeats) consecutive heartbeats. Please check if the WatchWise app is still installed and running."
            )
        default:
            return (
                "Extended Heartbeat Failure",
                "\(childName)'s device has been offline for over 5 hours. The WatchWise app may have been deleted or the device is experiencing issues."
            )
        }
    }
    
    // MARK: - Activity Tracking (Legacy - for non-child users)
    
    @objc private func appDidBecomeActive() {
        print("📱 App became active")
        if !isChildUser {
            recordActivity(type: "app_opened")
        }
    }
    
    @objc private func appDidEnterBackground() {
        print("📱 App entered background")
        if !isChildUser {
            recordActivity(type: "app_backgrounded")
        }
    }
    
    @objc private func appWillTerminate() {
        print("📱 App will terminate")
        if !isChildUser {
            recordActivity(type: "app_closed")
        }
        stopHeartbeatMonitoring()
    }
    
    @objc private func appStateChanged() {
        updateActivityStatus()
    }
    
    // MARK: - Legacy Activity Recording (for non-child users)
    
    func recordActivity(type: String) {
        guard !isChildUser else { return } // Child users use heartbeat system
        
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
    
    // MARK: - Activity Status
    
    private func updateActivityStatus() {
        guard let lastActivity = lastActivityTime else {
            activityStatus = .unknown
            return
        }
        
        let timeSinceLastActivity = Date().timeIntervalSince(lastActivity)
        let threshold: TimeInterval = isChildUser ? 1800 : 300 // 30 min for child, 5 min for others
        
        if timeSinceLastActivity < threshold {
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
    
    // MARK: - Background Task Management
    
    private func registerBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        print("📱 Starting activity monitoring")
        
        // Force refresh user type from Firebase
        if let currentUser = Auth.auth().currentUser {
            Task {
                await loadUserTypeFromFirebase(userId: currentUser.uid)
                
                await MainActor.run {
                    if self.isChildUser {
                        self.startHeartbeatMonitoring()
                    } else {
                        print("📱 Starting activity monitoring for non-child user")
                        self.recordActivity(type: "monitoring_started")
                    }
                }
            }
        } else {
            // Fallback to local check
            checkUserType()
            if isChildUser {
                startHeartbeatMonitoring()
            } else {
                print("📱 Starting activity monitoring for non-child user")
                recordActivity(type: "monitoring_started")
            }
        }
    }
    
    func stopMonitoring() {
        if isChildUser {
            stopHeartbeatMonitoring()
        } else {
            print("📱 Stopping activity monitoring")
            recordActivity(type: "monitoring_stopped")
        }
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
            stopHeartbeatMonitoring()
            endBackgroundTask()
        }
    }
} 