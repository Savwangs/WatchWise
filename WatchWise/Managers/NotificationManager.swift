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

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var hasNotificationPermission = false
    @Published var pendingNotifications: [PendingNotification] = []
    @Published var unreadMessageCount = 0
    
    private let db = Firestore.firestore()
    
    override init() {
        super.init()
        checkNotificationPermission()
    }
    
    // MARK: - Permission Management
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound, .provisional]
            )
            
            await MainActor.run {
                self.hasNotificationPermission = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            
            return granted
            
        } catch {
            print("❌ Error requesting notification permission: \(error)")
            return false
        }
    }
    
    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.hasNotificationPermission = settings.authorizationStatus == .authorized ||
                                               settings.authorizationStatus == .provisional
            }
        }
    }
    
    // MARK: - Local Notifications
    func scheduleScreenTimeReminder(
        title: String,
        body: String,
        timeInterval: TimeInterval,
        identifier: String = UUID().uuidString
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: unreadMessageCount + 1)
        content.categoryIdentifier = NotificationCategory.screenTimeReminder.rawValue
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("✅ Screen time reminder scheduled for \(timeInterval) seconds")
        } catch {
            print("❌ Error scheduling notification: \(error)")
            throw NotificationError.schedulingFailed
        }
    }
    
    func scheduleBreakReminder(
        appName: String,
        usageTime: TimeInterval,
        identifier: String = UUID().uuidString
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Take a Break! 🌟"
        content.body = "You've been using \(appName) for \(Int(usageTime/60)) minutes. Time for a screen break!"
        content.sound = .default
        content.badge = NSNumber(value: unreadMessageCount + 1)
        content.categoryIdentifier = NotificationCategory.breakReminder.rawValue
        
        // Schedule immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        try await UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleEncouragementNotification(
        message: String,
        identifier: String = UUID().uuidString
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Great Job! 🎉"
        content.body = message
        content.sound = .default
        content.badge = NSNumber(value: unreadMessageCount + 1)
        content.categoryIdentifier = NotificationCategory.encouragement.rawValue
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        try await UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Message Notifications
    func showMessageNotification(
        from sender: String,
        message: String,
        messageId: String,
        isFromParent: Bool = true
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = isFromParent ? "Message from Parent 👨‍👩‍👧‍👦" : "Message from Child 👶"
        content.body = message
        content.sound = .default
        content.badge = NSNumber(value: unreadMessageCount + 1)
        content.categoryIdentifier = NotificationCategory.message.rawValue
        content.userInfo = [
            "messageId": messageId,
            "sender": sender,
            "isFromParent": isFromParent
        ]
        
        // Add action buttons
        let replyAction = UNNotificationAction(
            identifier: NotificationAction.reply.rawValue,
            title: "Reply",
            options: [.foreground]
        )
        
        let markReadAction = UNNotificationAction(
            identifier: NotificationAction.markRead.rawValue,
            title: "Mark as Read",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: NotificationCategory.message.rawValue,
            actions: [replyAction, markReadAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: messageId, content: content, trigger: trigger)
        
        try await UNUserNotificationCenter.current().add(request)
        updateUnreadMessageCount(increment: true)
    }
    
    // MARK: - Badge Management
    func updateUnreadMessageCount(increment: Bool) {
        if increment {
            unreadMessageCount += 1
        } else {
            unreadMessageCount = max(0, unreadMessageCount - 1)
        }
        
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = self.unreadMessageCount
        }
    }
    
    func clearBadge() {
        unreadMessageCount = 0
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
    
    func resetUnreadCount(to count: Int) {
        unreadMessageCount = count
        UIApplication.shared.applicationIconBadgeNumber = count
    }
    
    // MARK: - Notification Management
    func cancelNotification(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        clearBadge()
    }
    
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await UNUserNotificationCenter.current().pendingNotificationRequests()
    }
    
    func getDeliveredNotifications() async -> [UNNotification] {
        return await UNUserNotificationCenter.current().deliveredNotifications()
    }
    
    // MARK: - Screen Time Alerts
    func checkAndScheduleScreenTimeAlerts(
        for userId: String,
        currentUsage: [String: TimeInterval],
        limits: [String: TimeInterval]
    ) async {
        for (appId, usage) in currentUsage {
            guard let limit = limits[appId] else { continue }
            
            let percentUsed = usage / limit
            
            // Alert at 75% of limit
            if percentUsed >= 0.75 && percentUsed < 0.9 {
                try? await scheduleScreenTimeReminder(
                    title: "Screen Time Alert 📱",
                    body: "You've used 75% of your \(appId) time limit today",
                    timeInterval: 1,
                    identifier: "alert_75_\(appId)"
                )
            }
            
            // Alert at 90% of limit
            if percentUsed >= 0.9 && percentUsed < 1.0 {
                try? await scheduleScreenTimeReminder(
                    title: "Screen Time Warning ⚠️",
                    body: "You're close to your \(appId) time limit for today",
                    timeInterval: 1,
                    identifier: "alert_90_\(appId)"
                )
            }
            
            // Alert when limit exceeded
            if percentUsed >= 1.0 {
                try? await scheduleScreenTimeReminder(
                    title: "Time Limit Reached 🚫",
                    body: "You've reached your daily limit for \(appId)",
                    timeInterval: 1,
                    identifier: "alert_limit_\(appId)"
                )
            }
        }
    }
    
    // MARK: - Healthy Usage Encouragement
    func scheduleHealthyUsageReminders() async {
        let healthyReminders = [
            (title: "Eye Break Time! 👀", body: "Look at something 20 feet away for 20 seconds", interval: 1200.0), // 20 minutes
            (title: "Stretch Break! 🤸‍♀️", body: "Stand up and stretch for a minute", interval: 1800.0), // 30 minutes
            (title: "Hydration Check! 💧", body: "Don't forget to drink some water", interval: 2700.0), // 45 minutes
            (title: "Move Your Body! 🚶‍♀️", body: "Take a quick walk around", interval: 3600.0) // 1 hour
        ]
        
        for (index, reminder) in healthyReminders.enumerated() {
            try? await scheduleScreenTimeReminder(
                title: reminder.title,
                body: reminder.body,
                timeInterval: reminder.interval,
                identifier: "healthy_reminder_\(index)"
            )
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        switch response.actionIdentifier {
        case NotificationAction.reply.rawValue:
            handleReplyAction(userInfo: userInfo)
            
        case NotificationAction.markRead.rawValue:
            handleMarkReadAction(userInfo: userInfo)
            
        case UNNotificationDefaultActionIdentifier:
            handleDefaultAction(userInfo: userInfo)
            
        default:
            break
        }
        
        completionHandler()
    }
    
    private func handleReplyAction(userInfo: [AnyHashable: Any]) {
        guard let messageId = userInfo["messageId"] as? String else { return }
        
        // Navigate to messages view or show reply interface
        NotificationCenter.default.post(
            name: .notificationReplyTapped,
            object: nil,
            userInfo: ["messageId": messageId]
        )
    }
    
    private func handleMarkReadAction(userInfo: [AnyHashable: Any]) {
        guard let messageId = userInfo["messageId"] as? String else { return }
        
        Task {
            try? await MessagingManager.shared.markMessageAsRead(messageId: messageId)
            updateUnreadMessageCount(increment: false)
        }
    }
    
    private func handleDefaultAction(userInfo: [AnyHashable: Any]) {
        // Open the app to the relevant screen
        if let messageId = userInfo["messageId"] as? String {
            NotificationCenter.default.post(
                name: .notificationTapped,
                object: nil,
                userInfo: ["messageId": messageId]
            )
        }
    }
}

// MARK: - Supporting Types
struct PendingNotification: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let scheduledDate: Date
    let identifier: String
}

enum NotificationCategory: String, CaseIterable {
    case message = "MESSAGE"
    case screenTimeReminder = "SCREEN_TIME_REMINDER"
    case breakReminder = "BREAK_REMINDER"
    case encouragement = "ENCOURAGEMENT"
}

enum NotificationAction: String, CaseIterable {
    case reply = "REPLY"
    case markRead = "MARK_READ"
    case snooze = "SNOOZE"
    case dismiss = "DISMISS"
}

enum NotificationError: LocalizedError {
    case permissionDenied
    case schedulingFailed
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permission denied"
        case .schedulingFailed:
            return "Failed to schedule notification"
        case .invalidData:
            return "Invalid notification data"
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let notificationTapped = Notification.Name("notificationTapped")
    static let notificationReplyTapped = Notification.Name("notificationReplyTapped")
    static let messageReceived = Notification.Name("messageReceived")
}
