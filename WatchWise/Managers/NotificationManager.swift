//
//  NotificationManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 7/2/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import UserNotifications
import UIKit

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var notifications: [AppNotification] = []
    @Published var unreadCount = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    private var notificationListener: ListenerRegistration?
    
    private init() {}
    
    deinit {
        Task { @MainActor in
            disconnect()
        }
    }
    
    // MARK: - Setup & Connection
    
    func setup() {
        requestNotificationPermissions()
        setupNotificationCategories()
    }
    
    func connect(userId: String) {
        disconnect()
        
        isLoading = true
        errorMessage = nil
        
        setupNotificationListener(userId: userId)
        
        isLoading = false
        
        print("🔔 NotificationManager: Connected for user \(userId)")
    }
    
    func disconnect() {
        notificationListener?.remove()
        notificationListener = nil
        notifications.removeAll()
        unreadCount = 0
        
        print("🔔 NotificationManager: Disconnected")
    }
    
    // MARK: - Notification Permissions
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                    print("✅ Notification permissions granted")
                } else if let error = error {
                    print("❌ Notification permission error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func setupNotificationCategories() {
        // App limit exceeded category
        let appLimitCategory = UNNotificationCategory(
            identifier: "APP_LIMIT_EXCEEDED",
            actions: [
                UNNotificationAction(
                    identifier: "EXTEND_TIME",
                    title: "Extend Time",
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: "VIEW_DETAILS",
                    title: "View Details",
                    options: [.foreground]
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        // New app detected category
        let newAppCategory = UNNotificationCategory(
            identifier: "NEW_APP_DETECTED",
            actions: [
                UNNotificationAction(
                    identifier: "ADD_TO_MONITORING",
                    title: "Add to Monitoring",
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: "IGNORE_APP",
                    title: "Ignore",
                    options: []
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        // App deleted category
        let appDeletedCategory = UNNotificationCategory(
            identifier: "APP_DELETED",
            actions: [
                UNNotificationAction(
                    identifier: "VIEW_HISTORY",
                    title: "View History",
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: "DISMISS",
                    title: "Dismiss",
                    options: []
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        // Message category
        let messageCategory = UNNotificationCategory(
            identifier: "NEW_MESSAGE",
            actions: [
                UNNotificationAction(
                    identifier: "REPLY",
                    title: "Reply",
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: "VIEW_CHAT",
                    title: "View Chat",
                    options: [.foreground]
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        // Register categories
        UNUserNotificationCenter.current().setNotificationCategories([
            appLimitCategory,
            newAppCategory,
            appDeletedCategory,
            messageCategory
        ])
    }
    
    // MARK: - Notification Listener
    
    private func setupNotificationListener(userId: String) {
        notificationListener = db.collection("notifications")
            .whereField("recipientId", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    if let error = error {
                        // Check if it's a permissions error
                        if error.localizedDescription.contains("Missing or insufficient permissions") {
                            // Don't show error for simulator - this is expected
                            #if targetEnvironment(simulator)
                            print("🔔 Simulator: Notifications collection not accessible (expected)")
                            self.notifications = []
                            self.unreadCount = 0
                            return
                            #else
                            self.errorMessage = "Failed to load notifications: Missing or insufficient permissions"
                            print("❌ Error loading notifications: \(error)")
                            return
                            #endif
                        } else {
                            self.errorMessage = "Failed to load notifications: \(error.localizedDescription)"
                            print("❌ Error loading notifications: \(error)")
                            return
                        }
                    }
                    
                    guard let documents = snapshot?.documents else {
                        print("🔔 No notifications found")
                        return
                    }
                    
                    let newNotifications = documents.compactMap { document -> AppNotification? in
                        try? document.data(as: AppNotification.self)
                    }
                    
                    self.notifications = newNotifications
                    self.unreadCount = newNotifications.filter { !$0.isRead }.count
                    
                    print("🔔 Loaded \(newNotifications.count) notifications (\(self.unreadCount) unread)")
                }
            }
    }
    
    // MARK: - Notification Operations
    
    func markAsRead(_ notificationId: String) async {
        do {
            try await db.collection("notifications")
                .document(notificationId)
                .updateData([
                    "isRead": true,
                    "readAt": Timestamp()
                ])
            
            // Update local notification
            if let index = notifications.firstIndex(where: { $0.id == notificationId }) {
                notifications[index].isRead = true
                notifications[index].readAt = Date()
                unreadCount = notifications.filter { !$0.isRead }.count
            }
            
        } catch {
            print("❌ Error marking notification as read: \(error)")
        }
    }
    
    func markAllAsRead() async {
        do {
            let batch = db.batch()
            
            let unreadNotifications = notifications.filter { !$0.isRead }
            
            for notification in unreadNotifications {
                let notificationRef = db.collection("notifications").document(notification.id)
                batch.updateData([
                    "isRead": true,
                    "readAt": Timestamp()
                ], forDocument: notificationRef)
            }
            
            try await batch.commit()
            
            // Update local notifications
            for index in notifications.indices {
                notifications[index].isRead = true
                notifications[index].readAt = Date()
            }
            
            unreadCount = 0
            
            print("✅ Marked \(unreadNotifications.count) notifications as read")
            
        } catch {
            print("❌ Error marking notifications as read: \(error)")
        }
    }
    
    func deleteNotification(_ notificationId: String) async {
        do {
            try await db.collection("notifications")
                .document(notificationId)
                .delete()
            
            // Remove from local notifications
            notifications.removeAll { $0.id == notificationId }
            unreadCount = notifications.filter { !$0.isRead }.count
            
        } catch {
            print("❌ Error deleting notification: \(error)")
        }
    }
    
    func clearAllNotifications() async {
        do {
            let batch = db.batch()
            
            for notification in notifications {
                let notificationRef = db.collection("notifications").document(notification.id)
                batch.deleteDocument(notificationRef)
            }
            
            try await batch.commit()
            
            notifications.removeAll()
            unreadCount = 0
            
            print("🗑️ Cleared all notifications")
            
        } catch {
            print("❌ Error clearing notifications: \(error)")
        }
    }
    
    // MARK: - Send Notifications
    
    func sendAppLimitExceededNotification(
        to parentId: String,
        appName: String,
        bundleId: String
    ) async {
        let notification = AppNotification(
            id: UUID().uuidString,
            recipientId: parentId,
            type: .appLimitExceeded,
            title: "App Time Limit Exceeded",
            message: "\(appName) has reached its daily time limit",
            data: [
                "bundleId": bundleId,
                "appName": appName
            ],
            timestamp: Date(),
            isRead: false
        )
        
        await sendNotification(notification)
    }
    
    func sendNewAppDetectedNotification(
        to parentId: String,
        appName: String,
        bundleId: String
    ) async {
        let notification = AppNotification(
            id: UUID().uuidString,
            recipientId: parentId,
            type: .newAppDetected,
            title: "New App Detected",
            message: "\(appName) has been installed on your child's device",
            data: [
                "bundleId": bundleId,
                "appName": appName
            ],
            timestamp: Date(),
            isRead: false
        )
        
        await sendNotification(notification)
    }
    
    func sendAppDeletedNotification(
        to parentId: String,
        appName: String,
        bundleId: String
    ) async {
        let notification = AppNotification(
            id: UUID().uuidString,
            recipientId: parentId,
            type: .appDeleted,
            title: "App Deleted",
            message: "\(appName) has been deleted from your child's device",
            data: [
                "bundleId": bundleId,
                "appName": appName
            ],
            timestamp: Date(),
            isRead: false
        )
        
        await sendNotification(notification)
    }
    
    func sendMessageNotification(
        to recipientId: String,
        from senderId: String,
        message: String,
        messageId: String
    ) async {
        let notification = AppNotification(
            id: UUID().uuidString,
            recipientId: recipientId,
            type: .newMessage,
            title: "New Message",
            message: message,
            data: [
                "senderId": senderId,
                "messageId": messageId
            ],
            timestamp: Date(),
            isRead: false
        )
        
        await sendNotification(notification)
    }
    
    func sendBedtimeReminderNotification(
        to parentId: String,
        childName: String
    ) async {
        let notification = AppNotification(
            id: UUID().uuidString,
            recipientId: parentId,
            type: .bedtimeReminder,
            title: "Bedtime Reminder",
            message: "It's time for \(childName) to go to bed. Apps will be disabled soon.",
            data: [
                "childName": childName
            ],
            timestamp: Date(),
            isRead: false
        )
        
        await sendNotification(notification)
    }
    
    func sendScreenTimeSummaryNotification(
        to parentId: String,
        childName: String,
        totalTime: TimeInterval
    ) async {
        let hours = Int(totalTime) / 3600
        let minutes = Int(totalTime) % 3600 / 60
        
        let timeString = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        
        let notification = AppNotification(
            id: UUID().uuidString,
            recipientId: parentId,
            type: .screenTimeSummary,
            title: "Daily Screen Time Summary",
            message: "\(childName) used their device for \(timeString) today",
            data: [
                "childName": childName,
                "totalTime": String(Int(totalTime))
            ],
            timestamp: Date(),
            isRead: false
        )
        
        await sendNotification(notification)
    }
    
    func sendDeviceOfflineNotification(
        to parentId: String,
        childName: String,
        childUserId: String
    ) async {
        let notification = AppNotification(
            id: UUID().uuidString,
            recipientId: parentId,
            type: .deviceOffline,
            title: "Device Unreachable",
            message: "\(childName)'s device hasn't been reachable for over 24 hours. The device may be offline, powered off, or WatchWise may have been removed.",
            data: [
                "childUserId": childUserId,
                "childName": childName,
                "offlineSince": String(Int(Date().timeIntervalSince1970))
            ],
            timestamp: Date(),
            isRead: false
        )
        
        await sendNotification(notification)
    }
    
    func sendSystemAlertNotification(
        title: String,
        message: String
    ) async {
        let notification = AppNotification(
            id: UUID().uuidString,
            recipientId: Auth.auth().currentUser?.uid ?? "",
            type: .systemAlert,
            title: title,
            message: message,
            data: [:],
            timestamp: Date(),
            isRead: false
        )
        
        await sendNotification(notification)
    }
    
    // MARK: - Private Methods
    
    private func sendNotification(_ notification: AppNotification) async {
        do {
            // Save to Firebase
            try await saveNotificationToFirebase(notification)
            
            // Add to local notifications
            notifications.insert(notification, at: 0)
            if !notification.isRead {
                unreadCount += 1
            }
            
            // Send local notification
            await sendLocalNotification(notification)
            
            print("🔔 Sent notification: \(notification.title)")
            
        } catch {
            print("❌ Error sending notification: \(error)")
        }
    }
    
    private func saveNotificationToFirebase(_ notification: AppNotification) async throws {
        let data: [String: Any] = [
            "id": notification.id,
            "recipientId": notification.recipientId,
            "type": notification.type.rawValue,
            "title": notification.title,
            "message": notification.message,
            "data": notification.data,
            "timestamp": Timestamp(date: notification.timestamp),
            "isRead": notification.isRead
        ]
        
        try await db.collection("notifications")
            .document(notification.id)
            .setData(data)
    }
    
    private func sendLocalNotification(_ notification: AppNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.message
        content.sound = .default
        content.badge = NSNumber(value: unreadCount)
        content.categoryIdentifier = notification.type.categoryIdentifier
        
        // Add custom data
        content.userInfo = notification.data
        
        // Create trigger (immediate)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: trigger
        )
        
        // Schedule notification
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("❌ Error scheduling local notification: \(error)")
        }
    }
    
    // MARK: - Utility Methods
    
    func getNotificationsByType(_ type: NotificationType) -> [AppNotification] {
        return notifications.filter { $0.type == type }
    }
    
    func getUnreadNotifications() -> [AppNotification] {
        return notifications.filter { !$0.isRead }
    }
    
    func clearError() {
        errorMessage = nil
    }
}

// MARK: - App Notification Model
struct AppNotification: Codable, Identifiable {
    let id: String
    let recipientId: String
    let type: NotificationType
    let title: String
    let message: String
    let data: [String: String]
    let timestamp: Date
    var isRead: Bool
    var readAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id, recipientId, type, title, message, data, timestamp, isRead, readAt
    }
    
    var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Notification Type Enum
enum NotificationType: String, Codable, CaseIterable {
    case appLimitExceeded = "app_limit_exceeded"
    case newAppDetected = "new_app_detected"
    case appDeleted = "app_deleted"
    case newMessage = "new_message"
    case bedtimeReminder = "bedtime_reminder"
    case screenTimeSummary = "screen_time_summary"
    case deviceOffline = "device_offline"
    case systemAlert = "system_alert"
    
    var categoryIdentifier: String {
        switch self {
        case .appLimitExceeded:
            return "APP_LIMIT_EXCEEDED"
        case .newAppDetected:
            return "NEW_APP_DETECTED"
        case .appDeleted:
            return "APP_DELETED"
        case .newMessage:
            return "NEW_MESSAGE"
        case .bedtimeReminder, .screenTimeSummary, .deviceOffline, .systemAlert:
            return "DEFAULT"
        }
    }
    
    var icon: String {
        switch self {
        case .appLimitExceeded:
            return "clock.badge.exclamationmark"
        case .newAppDetected:
            return "app.badge.plus"
        case .appDeleted:
            return "app.badge.minus"
        case .newMessage:
            return "message.fill"
        case .bedtimeReminder:
            return "moon.fill"
        case .screenTimeSummary:
            return "chart.bar.fill"
        case .deviceOffline:
            return "wifi.slash"
        case .systemAlert:
            return "exclamationmark.triangle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .appLimitExceeded:
            return "red"
        case .newAppDetected:
            return "orange"
        case .appDeleted:
            return "purple"
        case .newMessage:
            return "blue"
        case .bedtimeReminder:
            return "indigo"
        case .screenTimeSummary:
            return "green"
        case .deviceOffline:
            return "gray"
        case .systemAlert:
            return "yellow"
        }
    }
}



