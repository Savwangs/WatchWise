//
//  DataModels.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//

import Foundation
import FirebaseFirestore

enum ChildFlowState {
    case generateCode
    case pairedConfirmation
}

struct AppUsage: Identifiable, Codable {
    let id = UUID()
    let appName: String
    let bundleIdentifier: String
    let duration: TimeInterval
    let category: String
    let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case appName, bundleIdentifier, duration, category, timestamp
    }
}

struct ChildDevice: Identifiable, Codable {
    @DocumentID var id: String?
    let childName: String
    let deviceName: String
    let pairCode: String
    let parentId: String
    let pairedAt: Timestamp
    var isActive: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, childName, deviceName, pairCode, parentId, pairedAt, isActive
    }
}

struct ScreenTimeData: Identifiable, Codable {
    @DocumentID var id: String?
    let deviceId: String
    let date: Date
    let totalScreenTime: TimeInterval
    let appUsages: [AppUsage]
    let hourlyBreakdown: [Int: TimeInterval] // Hour of day -> duration
    
    enum CodingKeys: String, CodingKey {
        case id, deviceId, date, totalScreenTime, appUsages, hourlyBreakdown
    }
}

struct QuickMessage: Identifiable {
    let id = UUID()
    let text: String
    let emoji: String
    
    static let presetMessages = [
        QuickMessage(text: "I see you've been on social media for a while, take a break?", emoji: "⏰"),
        QuickMessage(text: "Doing great today! Screen time is low 👏", emoji: "🎉"),
        QuickMessage(text: "Let's take a walk – phone-free time?", emoji: "🚶‍♀️"),
        QuickMessage(text: "Time for homework! Let's focus 📚", emoji: "📚"),
        QuickMessage(text: "Great job managing your screen time today!", emoji: "⭐")
    ]
}

struct NotificationMessage: Codable {
    let parentId: String
    let childDeviceId: String
    let message: String
    let timestamp: Timestamp
    let isRead: Bool
}

// MARK: - Chat Messaging Models

enum MessageSenderType: String, Codable {
    case parent
    case child
}

struct ChatMessage: Identifiable, Codable {
    var id: String
    var senderId: String
    var senderType: MessageSenderType
    var content: String
    var timestamp: Timestamp
    
    enum CodingKeys: String, CodingKey {
        case id, senderId, senderType, content, timestamp
    }
}

// Family structure to group parent and children
struct Family: Identifiable, Codable {
    @DocumentID var id: String?
    let parentId: String
    var childDeviceIds: [String]
    let createdAt: Timestamp
    var isActive: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, parentId, childDeviceIds, createdAt, isActive
    }
}

// Pairing code management
struct PairCode: Identifiable, Codable {
    @DocumentID var id: String?
    let code: String
    let parentId: String
    let createdAt: Timestamp
    let expiresAt: Timestamp
    var isUsed: Bool
    var childDeviceId: String?
    
    enum CodingKeys: String, CodingKey {
        case id, code, parentId, createdAt, expiresAt, isUsed, childDeviceId
    }
}

// Enhanced user model for better database integration
struct DatabaseUser: Identifiable, Codable {
    @DocumentID var id: String?
    let email: String
    var displayName: String?
    var isDevicePaired: Bool
    var hasCompletedOnboarding: Bool
    var userType: String?
    let createdAt: Timestamp
    var lastActiveAt: Timestamp
    var familyId: String?
    var deviceToken: String? // For push notifications
    
    enum CodingKeys: String, CodingKey {
        case id, email, displayName, isDevicePaired, hasCompletedOnboarding, userType, createdAt, lastActiveAt, familyId, deviceToken
    }
}

// Message thread between parent and child
struct MessageThread: Identifiable, Codable {
    @DocumentID var id: String?
    let parentId: String
    let childDeviceId: String
    let familyId: String
    var lastMessage: String?
    var lastMessageTimestamp: Timestamp?
    var unreadCount: Int
    let createdAt: Timestamp
    
    enum CodingKeys: String, CodingKey {
        case id, parentId, childDeviceId, familyId, lastMessage, lastMessageTimestamp, unreadCount, createdAt
    }
}

// Push notification payload
struct PushNotificationPayload: Codable {
    let title: String
    let body: String
    let data: [String: String]?
    let badge: Int?
    
    enum CodingKeys: String, CodingKey {
        case title, body, data, badge
    }
}

// Screen time summary for dashboard
struct ScreenTimeSummary: Identifiable {
    let id = UUID()
    let date: Date
    let totalTime: TimeInterval
    let topApps: [AppUsage]
    let hourlyBreakdown: [Int: TimeInterval]
    let categoryBreakdown: [String: TimeInterval]
    
    var formattedTotalTime: String {
        let hours = Int(totalTime) / 3600
        let minutes = Int(totalTime) % 3600 / 60
        return "\(hours)h \(minutes)m"
    }
}

// Alert settings for parents
struct AlertSettings: Codable {
    var dailyLimitHours: Double
    var socialMediaLimitHours: Double
    var isEnabled: Bool
    var alertTimes: [String] // Time strings like "09:00", "15:00"
    var enabledCategories: [String]
    
    static let defaultSettings = AlertSettings(
        dailyLimitHours: 4.0,
        socialMediaLimitHours: 2.0,
        isEnabled: true,
        alertTimes: ["12:00", "18:00"],
        enabledCategories: ["Social Networking", "Games", "Entertainment"]
    )
}

// Device info for child devices
struct DeviceInfo: Codable {
    let deviceModel: String
    let systemVersion: String
    let appVersion: String
    let lastSyncAt: Timestamp
    var isOnline: Bool
    
    enum CodingKeys: String, CodingKey {
        case deviceModel, systemVersion, appVersion, lastSyncAt, isOnline
    }
}
