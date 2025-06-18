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
    
    enum CodingKeys: String, CodingKey {
        case appName, bundleIdentifier, duration, timestamp
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
    
    static let defaultSettings = AlertSettings(
        isEnabled: true,
        alertTimes: ["12:00", "18:00"],
        enabledCategories: ["Social Networking", "Games", "Entertainment"],
        appLimits: [:]
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

// MARK: - DEMO DATA - START (Remove in production)
extension ScreenTimeData {
    static var demoData: ScreenTimeData {
        let demoApps = [
            AppUsage(
                appName: "Instagram",
                bundleIdentifier: "com.burbn.instagram",
                duration: 4500, // 1h 15m
                timestamp: Date().addingTimeInterval(-3600)
            ),
            AppUsage(
                appName: "TikTok",
                bundleIdentifier: "com.zhiliaoapp.musically",
                duration: 2700, // 45m
                timestamp: Date().addingTimeInterval(-7200)
            ),
            AppUsage(
                appName: "YouTube",
                bundleIdentifier: "com.google.ios.youtube",
                duration: 3600, // 1h
                timestamp: Date().addingTimeInterval(-5400)
            ),
            AppUsage(
                appName: "Safari",
                bundleIdentifier: "com.apple.mobilesafari",
                duration: 1200, // 20m
                timestamp: Date().addingTimeInterval(-1800)
            ),
            AppUsage(
                appName: "Snapchat",
                bundleIdentifier: "com.toyopagroup.picaboo",
                duration: 1800, // 30m
                timestamp: Date().addingTimeInterval(-900)
            ),
            AppUsage(
                appName: "Messages",
                bundleIdentifier: "com.apple.MobileSMS",
                duration: 900, // 15m
                timestamp: Date().addingTimeInterval(-600)
            )
        ]
        
        let hourlyData: [Int: TimeInterval] = [
            8: 600,   // 8 AM - 10 minutes
            9: 1800,  // 9 AM - 30 minutes
            10: 900,  // 10 AM - 15 minutes
            12: 2400, // 12 PM - 40 minutes
            14: 1800, // 2 PM - 30 minutes
            16: 3600, // 4 PM - 1 hour
            18: 2700, // 6 PM - 45 minutes
            20: 1800, // 8 PM - 30 minutes
            21: 1200  // 9 PM - 20 minutes
        ]
        
        return ScreenTimeData(
            id: "demo-screen-time-data",
            deviceId: "demo-device-id",
            date: Date(),
            totalScreenTime: demoApps.reduce(0) { $0 + $1.duration },
            appUsages: demoApps,
            hourlyBreakdown: hourlyData
        )
    }
}

// MARK: - DEMO DATA - App Limits Extension (Remove in production)
extension AlertSettings {
    static var demoSettings: AlertSettings {
        return AlertSettings(
            isEnabled: true,
            alertTimes: ["12:00", "18:00"],
            enabledCategories: ["Social Networking", "Games", "Entertainment"],
            appLimits: [
                "com.burbn.instagram": 1.25, // 1h 15m current usage
                "com.zhiliaoapp.musically": 0.75, // 45m current usage
                "com.google.ios.youtube": 1.0, // 1h current usage
                "com.apple.mobilesafari": 0.5, // 30m limit (20m current)
                "com.toyopagroup.picaboo": 0.5, // 30m limit (30m current)
            ]
        )
    }
}
// MARK: - END DEMO DATA

extension ChildDevice {
    static var demoDevice: ChildDevice {
        return ChildDevice(
            id: "demo-device-id",
            childName: "Savir",
            deviceName: "Savir's iPhone",
            pairCode: "123456",
            parentId: "demo-parent-id",
            pairedAt: Timestamp(date: Date().addingTimeInterval(-86400)), // Paired yesterday
            isActive: true
        )
    }
}
