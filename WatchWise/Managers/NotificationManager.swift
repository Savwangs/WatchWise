//
//  NotificationManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/7/25.
//

import Foundation
import UserNotifications
import UIKit
import FirebaseFirestore
import FirebaseAuth

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var notifications: [AppNotification] = []
    @Published var unreadCount: Int = 0
    @Published var isLoading = false
    
    private let firebaseManager = FirebaseManager.shared
    private var listenerRegistration: ListenerRegistration?
    
    struct AppNotification: Identifiable, Codable {
        let id: String
        let parentUserId: String
        let childUserId: String
        let childName: String
        let type: NotificationType
        let title: String
        let message: String
        let timestamp: Timestamp
        var isRead: Bool
        
        enum NotificationType: String, Codable {
            case inactivity_alert
            case device_unlinked
            case screen_time_limit
            case bedtime_reminder
            case app_usage_alert
            case general
            
            var icon: String {
                switch self {
                case .inactivity_alert:
                    return "⏰"
                case .device_unlinked:
                    return "🔗"
                case .screen_time_limit:
                    return "📱"
                case .bedtime_reminder:
                    return "🌙"
                case .app_usage_alert:
                    return "⚠️"
                case .general:
                    return "📢"
                }
            }
            
            var color: String {
                switch self {
                case .inactivity_alert:
                    return "orange"
                case .device_unlinked:
                    return "red"
                case .screen_time_limit:
                    return "blue"
                case .bedtime_reminder:
                    return "purple"
                case .app_usage_alert:
                    return "yellow"
                case .general:
                    return "gray"
                }
            }
        }
    }
    
    private init() {
        setupNotificationPermissions()
    }
    
    // MARK: - Notification Permissions
    
    private func setupNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("✅ Notification permissions granted")
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                print("❌ Notification permissions denied: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    // MARK: - Real-time Notifications
    
    func startListeningForNotifications() {
        guard let currentUser = Auth.auth().currentUser else {
            print("❌ No authenticated user for notifications")
            return
        }
        
        stopListeningForNotifications()
        
        print("🔄 Starting to listen for notifications for user: \(currentUser.uid)")
        
        listenerRegistration = firebaseManager.db.collection("notifications")
            .whereField("parentUserId", isEqualTo: currentUser.uid)
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error listening for notifications: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else {
                    print("❌ No snapshot for notifications")
                    return
                }
                
                let newNotifications = snapshot.documents.compactMap { document -> AppNotification? in
                    let data = document.data()
                    
                    guard let parentUserId = data["parentUserId"] as? String,
                          let childUserId = data["childUserId"] as? String,
                          let childName = data["childName"] as? String,
                          let typeString = data["type"] as? String,
                          let type = AppNotification.NotificationType(rawValue: typeString),
                          let title = data["title"] as? String,
                          let message = data["message"] as? String,
                          let timestamp = data["timestamp"] as? Timestamp,
                          let isRead = data["isRead"] as? Bool else {
                        return nil
                    }
                    
                    return AppNotification(
                        id: document.documentID,
                        parentUserId: parentUserId,
                        childUserId: childUserId,
                        childName: childName,
                        type: type,
                        title: title,
                        message: message,
                        timestamp: timestamp,
                        isRead: isRead
                    )
                }
                
                DispatchQueue.main.async {
                    self.notifications = newNotifications
                    self.unreadCount = newNotifications.filter { !$0.isRead }.count
                    print("📱 Updated notifications: \(newNotifications.count) total, \(self.unreadCount) unread")
                }
            }
    }
    
    func stopListeningForNotifications() {
        listenerRegistration?.remove()
        listenerRegistration = nil
        print("🛑 Stopped listening for notifications")
    }
    
    // MARK: - Notification Management
    
    func markNotificationAsRead(notificationId: String) async {
        do {
            try await firebaseManager.db.collection("notifications")
                .document(notificationId)
                .updateData([
                    "isRead": true,
                    "readAt": Timestamp()
                ])
            
            print("✅ Marked notification as read: \(notificationId)")
        } catch {
            print("❌ Error marking notification as read: \(error)")
        }
    }
    
    func markAllNotificationsAsRead() async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        do {
            let snapshot = try await firebaseManager.db.collection("notifications")
                .whereField("parentUserId", isEqualTo: currentUser.uid)
                .whereField("isRead", isEqualTo: false)
                .getDocuments()
            
            if snapshot.documents.isEmpty {
                print("✅ No unread notifications to mark")
                return
            }
            
            let batch = firebaseManager.db.batch()
            
            for doc in snapshot.documents {
                batch.updateData([
                    "isRead": true,
                    "readAt": Timestamp()
                ], forDocument: doc.reference)
            }
            
            try await batch.commit()
            print("✅ Marked \(snapshot.documents.count) notifications as read")
            
        } catch {
            print("❌ Error marking all notifications as read: \(error)")
        }
    }
    
    func deleteNotification(notificationId: String) async {
        do {
            try await firebaseManager.db.collection("notifications")
                .document(notificationId)
                .delete()
            
            print("✅ Deleted notification: \(notificationId)")
        } catch {
            print("❌ Error deleting notification: \(error)")
        }
    }
    
    func deleteAllNotifications() async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        do {
            let snapshot = try await firebaseManager.db.collection("notifications")
                .whereField("parentUserId", isEqualTo: currentUser.uid)
                .getDocuments()
            
            if snapshot.documents.isEmpty {
                print("✅ No notifications to delete")
                return
            }
            
            let batch = firebaseManager.db.batch()
            
            for doc in snapshot.documents {
                batch.deleteDocument(doc.reference)
            }
            
            try await batch.commit()
            print("✅ Deleted \(snapshot.documents.count) notifications")
            
        } catch {
            print("❌ Error deleting all notifications: \(error)")
        }
    }
    
    // MARK: - Local Notifications
    
    func scheduleLocalNotification(title: String, body: String, timeInterval: TimeInterval = 1) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error scheduling local notification: \(error)")
            } else {
                print("✅ Local notification scheduled")
            }
        }
    }
    
    func scheduleBedtimeReminder(at time: Date, childName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Bedtime Reminder"
        content.body = "It's time for \(childName) to put their device away for the night."
        content.sound = .default
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "bedtime-reminder-\(childName)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error scheduling bedtime reminder: \(error)")
            } else {
                print("✅ Bedtime reminder scheduled for \(childName)")
            }
        }
    }
    
    func cancelBedtimeReminder(for childName: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["bedtime-reminder-\(childName)"]
        )
        print("✅ Cancelled bedtime reminder for \(childName)")
    }
    
    // MARK: - Notification Analytics
    
    func logNotificationInteraction(notificationId: String, action: String) {
        Task {
            do {
                try await firebaseManager.db.collection("notificationAnalytics").addDocument(data: [
                    "notificationId": notificationId,
                    "action": action,
                    "userId": Auth.auth().currentUser?.uid ?? "",
                    "timestamp": Timestamp()
                ])
            } catch {
                print("❌ Error logging notification interaction: \(error)")
            }
        }
    }
    
    // MARK: - Notification Settings
    
    func updateNotificationSettings(settings: NotificationSettings) async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        do {
            try await firebaseManager.settingsCollection.document(currentUser.uid).setData([
                "notificationSettings": [
                    "inactivityAlerts": settings.inactivityAlerts,
                    "screenTimeAlerts": settings.screenTimeAlerts,
                    "bedtimeReminders": settings.bedtimeReminders,
                    "appUsageAlerts": settings.appUsageAlerts,
                    "deviceUnlinkAlerts": settings.deviceUnlinkAlerts,
                    "quietHours": settings.quietHours,
                    "quietHoursStart": settings.quietHoursStart,
                    "quietHoursEnd": settings.quietHoursEnd
                ],
                "updatedAt": Timestamp()
            ], merge: true)
            
            print("✅ Updated notification settings")
        } catch {
            print("❌ Error updating notification settings: \(error)")
        }
    }
    
    func getNotificationSettings() async -> NotificationSettings? {
        guard let currentUser = Auth.auth().currentUser else { return nil }
        
        do {
            let document = try await firebaseManager.settingsCollection.document(currentUser.uid).getDocument()
            
            guard let data = document.data(),
                  let settingsData = data["notificationSettings"] as? [String: Any] else {
                return NotificationSettings.defaultSettings
            }
            
            return NotificationSettings(
                inactivityAlerts: settingsData["inactivityAlerts"] as? Bool ?? true,
                screenTimeAlerts: settingsData["screenTimeAlerts"] as? Bool ?? true,
                bedtimeReminders: settingsData["bedtimeReminders"] as? Bool ?? true,
                appUsageAlerts: settingsData["appUsageAlerts"] as? Bool ?? true,
                deviceUnlinkAlerts: settingsData["deviceUnlinkAlerts"] as? Bool ?? true,
                quietHours: settingsData["quietHours"] as? Bool ?? false,
                quietHoursStart: settingsData["quietHoursStart"] as? String ?? "22:00",
                quietHoursEnd: settingsData["quietHoursEnd"] as? String ?? "08:00"
            )
        } catch {
            print("❌ Error getting notification settings: \(error)")
            return NotificationSettings.defaultSettings
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        Task { @MainActor in
            stopListeningForNotifications()
        }
    }
}

// MARK: - Notification Settings Model

struct NotificationSettings {
    var inactivityAlerts: Bool
    var screenTimeAlerts: Bool
    var bedtimeReminders: Bool
    var appUsageAlerts: Bool
    var deviceUnlinkAlerts: Bool
    var quietHours: Bool
    var quietHoursStart: String
    var quietHoursEnd: String
    
    static let defaultSettings = NotificationSettings(
        inactivityAlerts: true,
        screenTimeAlerts: true,
        bedtimeReminders: true,
        appUsageAlerts: true,
        deviceUnlinkAlerts: true,
        quietHours: false,
        quietHoursStart: "22:00",
        quietHoursEnd: "08:00"
    )
}


