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
    let timestamp: Date
    let usageRanges: [AppUsageRange]? // New: exact time ranges
    
    enum CodingKeys: String, CodingKey {
        case appName, bundleIdentifier, duration, timestamp, usageRanges
    }
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    var formattedUsageRanges: String {
        guard let ranges = usageRanges, !ranges.isEmpty else {
            return "No time data"
        }
        
        return ranges.map { range in
            let startTime = range.startTime.formatted(date: .omitted, time: .shortened)
            let endTime = range.endTime.formatted(date: .omitted, time: .shortened)
            return "\(startTime) - \(endTime)"
        }.joined(separator: ", ")
    }
}

// New: Structure for exact time ranges
struct AppUsageRange: Identifiable, Codable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let sessionId: String
    
    enum CodingKeys: String, CodingKey {
        case startTime, endTime, duration, sessionId
    }
    
    var formattedRange: String {
        let start = startTime.formatted(date: .omitted, time: .shortened)
        let end = endTime.formatted(date: .omitted, time: .shortened)
        return "\(start) - \(end)"
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
    
    var formattedTotalTime: String {
        let hours = Int(totalTime) / 3600
        let minutes = Int(totalTime) % 3600 / 60
        return "\(hours)h \(minutes)m"
    }
}

// Alert settings for parents
struct AlertSettings: Codable {
    var isEnabled: Bool
    var alertTimes: [String] // Time strings like "09:00", "15:00"
    var enabledCategories: [String]
    var appLimits: [String: Double]
    var bedtimeSettings: BedtimeSettings
    var disabledApps: [String] // Bundle identifiers of completely disabled apps
    
    static let defaultSettings = AlertSettings(
        isEnabled: true,
        alertTimes: ["12:00", "18:00"],
        enabledCategories: ["Social Networking", "Games", "Entertainment"],
        appLimits: [:],
        bedtimeSettings: BedtimeSettings.defaultSettings,
        disabledApps: []
    )
}

// Bedtime settings for automatic app disabling
struct BedtimeSettings: Codable {
    var isEnabled: Bool
    var startTime: String // Format: "22:00" (10:00 PM)
    var endTime: String   // Format: "08:00" (8:00 AM)
    var enabledDays: [Int] // 1 = Sunday, 2 = Monday, ..., 7 = Saturday
    
    static let defaultSettings = BedtimeSettings(
        isEnabled: false,
        startTime: "22:00",
        endTime: "08:00",
        enabledDays: [1, 2, 3, 4, 5, 6, 7] // All days
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





// MARK: - App Monitoring Models

struct AppInfo: Identifiable, Codable {
    let id = UUID()
    let appName: String
    let bundleIdentifier: String
    let category: String
    
    enum CodingKeys: String, CodingKey {
        case appName, bundleIdentifier, category
    }
}

struct NewAppDetection: Identifiable, Codable {
    let id = UUID()
    let appName: String
    let bundleIdentifier: String
    let category: String
    let detectedAt: Date
    let deviceId: String?
    
    enum CodingKeys: String, CodingKey {
        case appName, bundleIdentifier, category, detectedAt, deviceId
    }
}
