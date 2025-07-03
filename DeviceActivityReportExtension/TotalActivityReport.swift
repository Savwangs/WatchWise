//
//  TotalActivityReport.swift
//  DeviceActivityReportExtension
//
//  Created by Savir Wangoo on 7/2/25.
//

import DeviceActivity
import SwiftUI

extension DeviceActivityReport.Context {
    // If your app initializes a DeviceActivityReport with this context, then the system will use
    // your extension's corresponding DeviceActivityReportScene to render the contents of the
    // report.
    static let totalActivity = Self("Total Activity")
    static let appUsage = Self("App Usage")
    static let newAppDetection = Self("New App Detection")
}

struct TotalActivityReport: DeviceActivityReportScene {
    // Define which context your scene will represent.
    let context: DeviceActivityReport.Context = .totalActivity
    
    // Define the custom configuration and the resulting view for this report.
    let content: (String) -> TotalActivityView
    
    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> String {
        // Reformat the data into a configuration that can be used to create
        // the report's view.
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        
        var totalActivityDuration: TimeInterval = 0
        
        // Access the data correctly using flatMap to get all activity segments
        let allSegments = data.flatMap { $0.activitySegments }
        for await segment in allSegments {
            totalActivityDuration += segment.totalActivityDuration
        }
        
        // Store the total activity data for the main app to access
        await storeActivityData(data)
        
        return formatter.string(from: totalActivityDuration) ?? "No activity data"
    }
    
    private func storeActivityData(_ data: DeviceActivityResults<DeviceActivityData>) async {
        // Store detailed app usage data in shared UserDefaults
        let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
        
        var appUsageData: [[String: Any]] = []
        var hourlyBreakdown: [Int: TimeInterval] = [:]
        var appUsageRanges: [String: [[String: Any]]] = [:] // Track exact time ranges per app
        
        // Access the data correctly using flatMap to get all activity segments
        let allSegments = data.flatMap { $0.activitySegments }
        for await segment in allSegments {
            for await categoryActivity in segment.categories {
                for await applicationActivity in categoryActivity.applications {
                    let bundleId = applicationActivity.application.bundleIdentifier ?? "unknown"
                    let appUsage: [String: Any] = [
                        "bundleIdentifier": bundleId,
                        "duration": applicationActivity.totalActivityDuration,
                        "timestamp": segment.dateInterval.start.timeIntervalSince1970
                    ]
                    appUsageData.append(appUsage)
                    
                    // Store exact time range for this app
                    let timeRange: [String: Any] = [
                        "startTime": segment.dateInterval.start.timeIntervalSince1970,
                        "endTime": segment.dateInterval.end.timeIntervalSince1970,
                        "duration": applicationActivity.totalActivityDuration,
                        "sessionId": UUID().uuidString
                    ]
                    
                    if appUsageRanges[bundleId] == nil {
                        appUsageRanges[bundleId] = []
                    }
                    appUsageRanges[bundleId]?.append(timeRange)
                    
                    // Aggregate by hour
                    let hour = Calendar.current.component(.hour, from: segment.dateInterval.start)
                    hourlyBreakdown[hour, default: 0] += applicationActivity.totalActivityDuration
                }
            }
        }
        
        // Store the data for main app to access
        userDefaults?.set(appUsageData, forKey: "detailed_app_usage_data")
        userDefaults?.set(hourlyBreakdown, forKey: "hourly_breakdown_data")
        userDefaults?.set(appUsageRanges, forKey: "app_usage_ranges") // New: exact time ranges
        userDefaults?.set(Date().timeIntervalSince1970, forKey: "last_activity_update")
        
        print("📊 DeviceActivityReport: Stored \(appUsageData.count) app usage records with time ranges")
    }
}

// MARK: - App Usage Report
struct AppUsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .appUsage
    let content: (String) -> TotalActivityView
    
    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> String {
        // Process and store app-specific usage data
        await processAppUsageData(data)
        return "App usage data processed"
    }
    
    private func processAppUsageData(_ data: DeviceActivityResults<DeviceActivityData>) async {
        let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
        
        var appUsageByBundle: [String: TimeInterval] = [:]
        
        // Access the data correctly using flatMap to get all activity segments
        let allSegments = data.flatMap { $0.activitySegments }
        for await segment in allSegments {
            for await categoryActivity in segment.categories {
                for await applicationActivity in categoryActivity.applications {
                    let bundleId = applicationActivity.application.bundleIdentifier ?? "unknown"
                    appUsageByBundle[bundleId, default: 0] += applicationActivity.totalActivityDuration
                }
            }
        }
        
        // Store individual app usage data
        for (bundleId, duration) in appUsageByBundle {
            let key = "app_usage_\(bundleId)"
            userDefaults?.set(duration, forKey: key)
        }
        
        print("📱 DeviceActivityReport: Processed usage for \(appUsageByBundle.count) apps")
    }
}

// MARK: - New App Detection Report
struct NewAppDetectionReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .newAppDetection
    let content: (String) -> TotalActivityView
    
    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> String {
        // Detect and store new app installations
        await detectNewApps(data)
        return "New app detection completed"
    }
    
    private func detectNewApps(_ data: DeviceActivityResults<DeviceActivityData>) async {
        let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
        
        // Get previously known apps
        let knownApps = userDefaults?.array(forKey: "known_apps") as? [String] ?? []
        
        // Get current apps from activity data
        var currentApps: Set<String> = []
        
        // Access the data correctly using flatMap to get all activity segments
        let allSegments = data.flatMap { $0.activitySegments }
        for await segment in allSegments {
            for await categoryActivity in segment.categories {
                for await applicationActivity in categoryActivity.applications {
                    if let bundleId = applicationActivity.application.bundleIdentifier {
                        currentApps.insert(bundleId)
                    }
                }
            }
        }
        
        // Find new apps
        let newApps = currentApps.subtracting(knownApps)
        
        if !newApps.isEmpty {
            // Store new app detections
            var existingDetections = userDefaults?.array(forKey: "new_app_detections") as? [String] ?? []
            existingDetections.append(contentsOf: newApps)
            userDefaults?.set(existingDetections, forKey: "new_app_detections")
            
            // Update known apps
            userDefaults?.set(Array(currentApps), forKey: "known_apps")
            
            print("🆕 DeviceActivityReport: Detected \(newApps.count) new apps")
        }
    }
}
