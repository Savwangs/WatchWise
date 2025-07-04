//
//  HeartbeatManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 7/2/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import BackgroundTasks

@MainActor
class HeartbeatManager: ObservableObject {
    @Published var childDevices: [ChildHeartbeatStatus] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    private var heartbeatTimer: Timer?
    private var statusCheckTimer: Timer?
    
    // Heartbeat configuration
    private let heartbeatInterval: TimeInterval = 30 * 60 // 30 minutes
    private let offlineThreshold: TimeInterval = 24 * 60 * 60 // 24 hours
    
    deinit {
        heartbeatTimer?.invalidate()
        statusCheckTimer?.invalidate()
    }
    
    // MARK: - Child App Heartbeat (Called from Child App)
    
    func sendHeartbeat(childUserId: String, deviceInfo: DeviceInfo) async {
        do {
            let heartbeatData: [String: Any] = [
                "childUserId": childUserId,
                "timestamp": Timestamp(),
                "deviceInfo": [
                    "deviceName": deviceInfo.deviceName,
                    "osVersion": deviceInfo.osVersion,
                    "appVersion": deviceInfo.appVersion,
                    "batteryLevel": deviceInfo.batteryLevel,
                    "isCharging": deviceInfo.isCharging,
                    "networkStatus": deviceInfo.networkStatus
                ],
                "isActive": true
            ]
            
            try await db.collection("heartbeats")
                .document(childUserId)
                .setData(heartbeatData, merge: true)
            
            print("💓 Heartbeat sent for child: \(childUserId)")
            
        } catch {
            print("❌ Error sending heartbeat: \(error)")
        }
    }
    
    // MARK: - Parent App Status Monitoring
    
    func startMonitoring(parentId: String) {
        stopMonitoring()
        
        // Start heartbeat timer for sending status checks
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkChildDevicesStatus(parentId: parentId)
            }
        }
        
        // Initial check
        Task {
            await checkChildDevicesStatus(parentId: parentId)
        }
        
        print("💓 Heartbeat monitoring started for parent: \(parentId)")
    }
    
    func stopMonitoring() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        statusCheckTimer?.invalidate()
        statusCheckTimer = nil
        
        print("💓 Heartbeat monitoring stopped")
    }
    
    private func checkChildDevicesStatus(parentId: String) async {
        isLoading = true
        
        do {
            // Get all children for this parent
            let childrenSnapshot = try await db.collection("parentChildRelationships")
                .whereField("parentUserId", isEqualTo: parentId)
                .getDocuments()
            
            var updatedDevices: [ChildHeartbeatStatus] = []
            
            for childDoc in childrenSnapshot.documents {
                let childUserId = childDoc.data()["childUserId"] as? String ?? ""
                let childName = childDoc.data()["childName"] as? String ?? "Unknown Child"
                
                // Check heartbeat status
                let heartbeatStatus = await getHeartbeatStatus(childUserId: childUserId)
                updatedDevices.append(heartbeatStatus)
                
                // Check if device is offline and send notification
                if heartbeatStatus.status == .offline {
                    await sendOfflineNotification(parentId: parentId, childName: childName, childUserId: childUserId)
                }
            }
            
            childDevices = updatedDevices
            isLoading = false
            
        } catch {
            errorMessage = "Failed to check device status: \(error.localizedDescription)"
            isLoading = false
            print("❌ Error checking device status: \(error)")
        }
    }
    
    private func getHeartbeatStatus(childUserId: String) async -> ChildHeartbeatStatus {
        do {
            let heartbeatDoc = try await db.collection("heartbeats")
                .document(childUserId)
                .getDocument()
            
            guard let data = heartbeatDoc.data(),
                  let timestamp = data["timestamp"] as? Timestamp else {
                return ChildHeartbeatStatus(
                    childUserId: childUserId,
                    childName: "Unknown",
                    lastHeartbeat: nil,
                    status: .offline,
                    deviceInfo: nil
                )
            }
            
            let lastHeartbeat = timestamp.dateValue()
            let timeSinceHeartbeat = Date().timeIntervalSince(lastHeartbeat)
            
            let status: HeartbeatStatus = timeSinceHeartbeat > offlineThreshold ? .offline : .online
            
            let deviceInfo = parseDeviceInfo(from: data["deviceInfo"] as? [String: Any])
            
            return ChildHeartbeatStatus(
                childUserId: childUserId,
                childName: "Child", // Will be updated from parent-child relationship
                lastHeartbeat: lastHeartbeat,
                status: status,
                deviceInfo: deviceInfo
            )
            
        } catch {
            return ChildHeartbeatStatus(
                childUserId: childUserId,
                childName: "Unknown",
                lastHeartbeat: nil,
                status: .offline,
                deviceInfo: nil
            )
        }
    }
    
    private func parseDeviceInfo(from data: [String: Any]?) -> DeviceInfo? {
        guard let data = data else { return nil }
        
        return DeviceInfo(
            deviceName: data["deviceName"] as? String ?? "Unknown Device",
            osVersion: data["osVersion"] as? String ?? "Unknown",
            appVersion: data["appVersion"] as? String ?? "Unknown",
            batteryLevel: data["batteryLevel"] as? Double ?? 0.0,
            isCharging: data["isCharging"] as? Bool ?? false,
            networkStatus: data["networkStatus"] as? String ?? "Unknown"
        )
    }
    
    private func sendOfflineNotification(parentId: String, childName: String, childUserId: String) async {
        do {
            // Check if we already sent a notification recently (within 6 hours)
            let recentNotification = try await db.collection("notifications")
                .whereField("recipientId", isEqualTo: parentId)
                .whereField("type", isEqualTo: "device_offline")
                .whereField("data.childUserId", isEqualTo: childUserId)
                .whereField("timestamp", isGreaterThan: Timestamp(date: Date().addingTimeInterval(-6 * 60 * 60)))
                .limit(to: 1)
                .getDocuments()
            
            if !recentNotification.documents.isEmpty {
                return // Already notified recently
            }
            
            let notificationData: [String: Any] = [
                "recipientId": parentId,
                "type": "device_offline",
                "title": "Device Unreachable",
                "message": "\(childName)'s device hasn't been reachable for over 24 hours. The device may be offline, powered off, or WatchWise may have been removed.",
                "data": [
                    "childUserId": childUserId,
                    "childName": childName,
                    "offlineSince": Timestamp()
                ],
                "timestamp": Timestamp(),
                "isRead": false
            ]
            
            try await db.collection("notifications").addDocument(data: notificationData)
            
            print("🔔 Sent offline notification for child: \(childName)")
            
        } catch {
            print("❌ Error sending offline notification: \(error)")
        }
    }
    
    // MARK: - Background Task Support
    
    func registerBackgroundTasks() {
        // Register background task for heartbeat
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.watchwise.heartbeat", using: nil) { task in
            self.handleBackgroundHeartbeat(task: task as! BGAppRefreshTask)
        }
    }
    
    private func handleBackgroundHeartbeat(task: BGAppRefreshTask) {
        // Schedule next background task
        scheduleBackgroundHeartbeat()
        
        guard let currentUser = Auth.auth().currentUser else {
            task.setTaskCompleted(success: false)
            return
        }
        
        // Send heartbeat
        Task {
            let deviceInfo = await getCurrentDeviceInfo()
            await sendHeartbeat(childUserId: currentUser.uid, deviceInfo: deviceInfo)
            task.setTaskCompleted(success: true)
        }
    }
    
    private func scheduleBackgroundHeartbeat() {
        let request = BGAppRefreshTaskRequest(identifier: "com.watchwise.heartbeat")
        request.earliestBeginDate = Date(timeIntervalSinceNow: heartbeatInterval)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("❌ Could not schedule background heartbeat: \(error)")
        }
    }
    
    private func getCurrentDeviceInfo() async -> DeviceInfo {
        // Get current device information
        let device = UIDevice.current
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        
        return DeviceInfo(
            deviceName: device.name,
            osVersion: device.systemVersion,
            appVersion: appVersion,
            batteryLevel: device.batteryLevel,
            isCharging: device.batteryState == .charging,
            networkStatus: await getNetworkStatus()
        )
    }
    
    private func getNetworkStatus() async -> String {
        // Simple network status check
        // In a real app, you might use Network framework for more detailed status
        return "WiFi" // Placeholder
    }
    
    // MARK: - Utility Methods
    
    func clearError() {
        errorMessage = nil
    }
}

// MARK: - Supporting Models

struct ChildHeartbeatStatus: Identifiable {
    let id = UUID()
    let childUserId: String
    let childName: String
    let lastHeartbeat: Date?
    let status: HeartbeatStatus
    let deviceInfo: DeviceInfo?
    
    var formattedLastHeartbeat: String {
        guard let lastHeartbeat = lastHeartbeat else {
            return "Never"
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastHeartbeat, relativeTo: Date())
    }
    
    var statusDescription: String {
        switch status {
        case .online:
            return "Online"
        case .offline:
            return "Offline"
        case .unknown:
            return "Unknown"
        }
    }
}

enum HeartbeatStatus {
    case online
    case offline
    case unknown
}

struct DeviceInfo: Codable {
    let deviceName: String
    let osVersion: String
    let appVersion: String
    let batteryLevel: Double
    let isCharging: Bool
    let networkStatus: String
} 