//
//  MessagingManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/7/25.
//

import Foundation
import FirebaseMessaging
import FirebaseFirestore
import UserNotifications
import UIKit

@MainActor
class MessagingManager: NSObject, ObservableObject {
    static let shared = MessagingManager()
    
    @Published var fcmToken: String?
    @Published var isTokenRegistered = false
    
    private let db = Firestore.firestore()
    private let messaging = Messaging.messaging()
    
    override init() {
        super.init()
        messaging.delegate = self
        setupNotifications()
    }
    
    // MARK: - Setup
    func setupNotifications() {
        // Note: NotificationManager.shared is not a UNUserNotificationCenterDelegate
        // The delegate is set in the main app delegate
        requestNotificationPermissions()
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                } else if let error = error {
                    print("❌ Notification permission error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Token Management
    func retrieveFCMToken(for userId: String, deviceType: DeviceType) async throws {
        do {
            let token = try await messaging.token()
            self.fcmToken = token
            try await registerTokenInFirestore(userId: userId, token: token, deviceType: deviceType)
            print("✅ FCM Token retrieved and registered: \(token)")
        } catch {
            print("❌ Error retrieving FCM token: \(error)")
            throw MessagingError.tokenRetrievalFailed
        }
    }
    
    private func registerTokenInFirestore(userId: String, token: String, deviceType: DeviceType) async throws {
        let tokenData: [String: Any] = [
            "fcmToken": token,
            "deviceType": deviceType.rawValue,
            "lastUpdated": Timestamp(),
            "isActive": true
        ]
        
        do {
            try await db.collection("users").document(userId).updateData([
                "fcmTokens.\(deviceType.rawValue)": tokenData
            ])
            isTokenRegistered = true
        } catch {
            print("❌ Error registering token in Firestore: \(error)")
            throw MessagingError.tokenRegistrationFailed
        }
    }
    
    // MARK: - Send Messages
    func sendMessageToChild(
        parentId: String,
        childDeviceId: String,
        message: String,
        messageType: MessageType = .reminder
    ) async throws {
        // Store message in Firestore
        let messageData = MessageData(
            id: UUID().uuidString,
            parentId: parentId,
            childDeviceId: childDeviceId,
            message: message,
            messageType: messageType,
            timestamp: Timestamp(),
            isRead: false,
            isDelivered: false
        )
        
        do {
            // Save to Firestore
            try await db.collection("messages").document(messageData.id).setData(from: messageData)
            
            // Get child's FCM token
            let childToken = try await getChildFCMToken(childDeviceId: childDeviceId)
            
            // Send push notification via Cloud Function
            try await sendPushNotification(
                to: childToken,
                message: message,
                messageType: messageType,
                messageId: messageData.id
            )
            
            // Mark as delivered
            try await db.collection("messages").document(messageData.id).updateData([
                "isDelivered": true,
                "deliveredAt": Timestamp()
            ])
            
            print("✅ Message sent successfully to child device")
            
        } catch {
            print("❌ Error sending message: \(error)")
            throw MessagingError.sendMessageFailed
        }
    }
    
    func sendMessageToParent(
        childDeviceId: String,
        parentId: String,
        message: String,
        messageType: MessageType = .response
    ) async throws {
        let messageData = MessageData(
            id: UUID().uuidString,
            parentId: parentId,
            childDeviceId: childDeviceId,
            message: message,
            messageType: messageType,
            timestamp: Timestamp(),
            isRead: false,
            isDelivered: false
        )
        
        do {
            try await db.collection("messages").document(messageData.id).setData(from: messageData)
            
            let parentToken = try await getParentFCMToken(parentId: parentId)
            
            try await sendPushNotification(
                to: parentToken,
                message: message,
                messageType: messageType,
                messageId: messageData.id
            )
            
            try await db.collection("messages").document(messageData.id).updateData([
                "isDelivered": true,
                "deliveredAt": Timestamp()
            ])
            
            print("✅ Message sent successfully to parent")
            
        } catch {
            print("❌ Error sending message to parent: \(error)")
            throw MessagingError.sendMessageFailed
        }
    }
    
    // MARK: - Get FCM Tokens
    private func getChildFCMToken(childDeviceId: String) async throws -> String {
        do {
            let document = try await db.collection("childDevices").document(childDeviceId).getDocument()
            guard let data = document.data(),
                  let userId = data["userId"] as? String else {
                throw MessagingError.deviceNotFound
            }
            
            let userDoc = try await db.collection("users").document(userId).getDocument()
            guard let userData = userDoc.data(),
                  let tokens = userData["fcmTokens"] as? [String: [String: Any]],
                  let childTokenData = tokens["child"] as? [String: Any],
                  let token = childTokenData["fcmToken"] as? String else {
                throw MessagingError.tokenNotFound
            }
            
            return token
        } catch {
            throw MessagingError.tokenNotFound
        }
    }
    
    private func getParentFCMToken(parentId: String) async throws -> String {
        do {
            let document = try await db.collection("users").document(parentId).getDocument()
            guard let data = document.data(),
                  let tokens = data["fcmTokens"] as? [String: [String: Any]],
                  let parentTokenData = tokens["parent"] as? [String: Any],
                  let token = parentTokenData["fcmToken"] as? String else {
                throw MessagingError.tokenNotFound
            }
            
            return token
        } catch {
            throw MessagingError.tokenNotFound
        }
    }
    
    // MARK: - Send Push Notification
    private func sendPushNotification(
        to token: String,
        message: String,
        messageType: MessageType,
        messageId: String
    ) async throws {
        let payload: [String: Any] = [
            "to": token,
            "notification": [
                "title": messageType.notificationTitle,
                "body": message,
                "sound": "default",
                "badge": 1
            ],
            "data": [
                "messageId": messageId,
                "messageType": messageType.rawValue,
                "timestamp": String(Date().timeIntervalSince1970)
            ],
            "priority": "high",
            "content_available": true
        ]
        
        // This would typically be handled by a Cloud Function
        // For now, we'll create a Firestore document that triggers the Cloud Function
        try await db.collection("fcmQueue").addDocument(data: payload)
    }
    
    // MARK: - Message History
    func getMessageHistory(for userId: String, deviceId: String) async throws -> [MessageData] {
        do {
            let snapshot = try await db.collection("messages")
                .whereField("childDeviceId", isEqualTo: deviceId)
                .order(by: "timestamp", descending: true)
                .limit(to: 50)
                .getDocuments()
            
            let messages = try snapshot.documents.compactMap { document -> MessageData? in
                try document.data(as: MessageData.self)
            }
            
            return messages
        } catch {
            print("❌ Error fetching message history: \(error)")
            throw MessagingError.fetchMessagesFailed
        }
    }
    
    func markMessageAsRead(messageId: String) async throws {
        do {
            try await db.collection("messages").document(messageId).updateData([
                "isRead": true,
                "readAt": Timestamp()
            ])
        } catch {
            print("❌ Error marking message as read: \(error)")
        }
    }
    
    // MARK: - Real-time Message Listening
    func listenForMessages(
        childDeviceId: String,
        completion: @escaping ([MessageData]) -> Void
    ) -> ListenerRegistration {
        return db.collection("messages")
            .whereField("childDeviceId", isEqualTo: childDeviceId)
            .whereField("isRead", isEqualTo: false)
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Error listening for messages: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                let messages = documents.compactMap { document -> MessageData? in
                    try? document.data(as: MessageData.self)
                }
                
                DispatchQueue.main.async {
                    completion(messages)
                }
            }
    }
}

// MARK: - MessagingDelegate
extension MessagingManager: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        
        DispatchQueue.main.async {
            self.fcmToken = token
            print("✅ FCM Token updated: \(token)")
            
            // Refresh token in Firestore if user is logged in
            // This should be called from your AuthenticationManager when token updates
        }
    }
}

// MARK: - Error Types
enum MessagingError: LocalizedError {
    case tokenRetrievalFailed
    case tokenRegistrationFailed
    case tokenNotFound
    case deviceNotFound
    case sendMessageFailed
    case fetchMessagesFailed
    
    var errorDescription: String? {
        switch self {
        case .tokenRetrievalFailed:
            return "Failed to retrieve FCM token"
        case .tokenRegistrationFailed:
            return "Failed to register FCM token"
        case .tokenNotFound:
            return "FCM token not found"
        case .deviceNotFound:
            return "Device not found"
        case .sendMessageFailed:
            return "Failed to send message"
        case .fetchMessagesFailed:
            return "Failed to fetch messages"
        }
    }
}

// MARK: - Supporting Data Models
struct MessageData: Codable, Identifiable {
    let id: String
    let parentId: String
    let childDeviceId: String
    let message: String
    let messageType: MessageType
    let timestamp: Timestamp
    var isRead: Bool
    var isDelivered: Bool
    let readAt: Timestamp?
    let deliveredAt: Timestamp?
    
    init(id: String, parentId: String, childDeviceId: String, message: String, messageType: MessageType, timestamp: Timestamp, isRead: Bool, isDelivered: Bool) {
        self.id = id
        self.parentId = parentId
        self.childDeviceId = childDeviceId
        self.message = message
        self.messageType = messageType
        self.timestamp = timestamp
        self.isRead = isRead
        self.isDelivered = isDelivered
        self.readAt = nil
        self.deliveredAt = nil
    }
}

enum MessageType: String, Codable, CaseIterable {
    case reminder = "reminder"
    case encouragement = "encouragement"
    case warning = "warning"
    case response = "response"
    case custom = "custom"
    
    var notificationTitle: String {
        switch self {
        case .reminder:
            return "Reminder from Parent"
        case .encouragement:
            return "Message from Parent"
        case .warning:
            return "Important Message"
        case .response:
            return "Message from Child"
        case .custom:
            return "Message"
        }
    }
}

enum DeviceType: String, Codable {
    case parent = "parent"
    case child = "child"
}
