//
//  DeviceActivityReportExtension.swift
//  DeviceActivityReportExtension
//
//  Created by Savir Wangoo on 6/7/25.
//

import DeviceActivity
import SwiftUI

class DeviceActivityReportExtension: DeviceActivityReport {
    override func intervalDidStart(for activityReports: [DeviceActivityReport.Context : DeviceActivityReport.ActivityReport]) {
        super.intervalDidStart(for: activityReports)
        
        // Handle interval start
        print("🔄 Device activity interval started")
        
        for (context, activityReport) in activityReports {
            print("📊 Activity report for context: \(context)")
            
            // Process activity report data
            processActivityReport(activityReport)
        }
    }
    
    override func intervalDidEnd(for activityReports: [DeviceActivityReport.Context : DeviceActivityReport.ActivityReport]) {
        super.intervalDidEnd(for: activityReports)
        
        // Handle interval end
        print("🔄 Device activity interval ended")
        
        for (context, activityReport) in activityReports {
            print("📊 Final activity report for context: \(context)")
            
            // Process final activity report data
            processActivityReport(activityReport)
        }
    }
    
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activityReport: DeviceActivityReport.ActivityReport) {
        super.eventDidReachThreshold(event, activityReport: activityReport)
        
        // Handle threshold events
        print("⚠️ Event threshold reached: \(event)")
        
        // Process threshold event
        processThresholdEvent(event, activityReport: activityReport)
    }
    
    private func processActivityReport(_ activityReport: DeviceActivityReport.ActivityReport) {
        // Extract app usage data from the activity report
        let applications = activityReport.applications
        
        for application in applications {
            let bundleIdentifier = application.bundleIdentifier
            let totalActivityDuration = application.totalActivityDuration
            
            print("📱 App: \(bundleIdentifier), Duration: \(totalActivityDuration)")
            
            // Store app usage data
            storeAppUsageData(bundleIdentifier: bundleIdentifier, duration: totalActivityDuration)
        }
        
        // Extract web usage data
        let webUsage = activityReport.webUsage
        
        for webDomain in webUsage {
            let domain = webDomain.domain
            let totalActivityDuration = webDomain.totalActivityDuration
            
            print("🌐 Web: \(domain), Duration: \(totalActivityDuration)")
            
            // Store web usage data
            storeWebUsageData(domain: domain, duration: totalActivityDuration)
        }
    }
    
    private func processThresholdEvent(_ event: DeviceActivityEvent.Name, activityReport: DeviceActivityReport.ActivityReport) {
        // Handle specific threshold events
        switch event.rawValue {
        case "DailyScreenTime":
            handleDailyScreenTimeThreshold(activityReport)
        case "NewAppDetection":
            handleNewAppDetection(activityReport)
        case "AppUsageTracking":
            handleAppUsageTracking(activityReport)
        default:
            print("⚠️ Unknown threshold event: \(event)")
        }
    }
    
    private func handleDailyScreenTimeThreshold(_ activityReport: DeviceActivityReport.ActivityReport) {
        print("📊 Daily screen time threshold reached")
        
        // Calculate total screen time for the day
        let totalScreenTime = activityReport.applications.reduce(0) { $0 + $1.totalActivityDuration }
        
        // Store daily screen time data
        storeDailyScreenTimeData(totalScreenTime: totalScreenTime)
    }
    
    private func handleNewAppDetection(_ activityReport: DeviceActivityReport.ActivityReport) {
        print("🆕 New app detection threshold reached")
        
        // Check for new apps in the activity report
        let currentApps = Set(activityReport.applications.map { $0.bundleIdentifier })
        
        // Compare with known apps (this would be stored in UserDefaults or similar)
        let knownApps = getKnownApps()
        let newApps = currentApps.subtracting(knownApps)
        
        if !newApps.isEmpty {
            print("🆕 Detected new apps: \(newApps)")
            
            // Store new app detections
            for bundleIdentifier in newApps {
                storeNewAppDetection(bundleIdentifier: bundleIdentifier)
            }
            
            // Update known apps
            updateKnownApps(currentApps)
        }
    }
    
    private func handleAppUsageTracking(_ activityReport: DeviceActivityReport.ActivityReport) {
        print("📱 App usage tracking threshold reached")
        
        // Process detailed app usage data
        for application in activityReport.applications {
            let bundleIdentifier = application.bundleIdentifier
            let totalActivityDuration = application.totalActivityDuration
            
            // Store detailed app usage data
            storeDetailedAppUsageData(bundleIdentifier: bundleIdentifier, duration: totalActivityDuration)
        }
    }
    
    // MARK: - Data Storage Methods
    
    private func storeAppUsageData(bundleIdentifier: String, duration: TimeInterval) {
        // Store app usage data in UserDefaults or shared container
        let key = "app_usage_\(bundleIdentifier)"
        let currentDuration = UserDefaults.standard.double(forKey: key)
        UserDefaults.standard.set(currentDuration + duration, forKey: key)
        
        print("💾 Stored app usage: \(bundleIdentifier) - \(duration) seconds")
    }
    
    private func storeWebUsageData(domain: String, duration: TimeInterval) {
        // Store web usage data
        let key = "web_usage_\(domain)"
        let currentDuration = UserDefaults.standard.double(forKey: key)
        UserDefaults.standard.set(currentDuration + duration, forKey: key)
        
        print("💾 Stored web usage: \(domain) - \(duration) seconds")
    }
    
    private func storeDailyScreenTimeData(totalScreenTime: TimeInterval) {
        // Store daily screen time data
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateKey = dateFormatter.string(from: today)
        
        let key = "daily_screen_time_\(dateKey)"
        UserDefaults.standard.set(totalScreenTime, forKey: key)
        
        print("💾 Stored daily screen time: \(totalScreenTime) seconds for \(dateKey)")
    }
    
    private func storeNewAppDetection(bundleIdentifier: String) {
        // Store new app detection
        let detections = UserDefaults.standard.array(forKey: "new_app_detections") as? [String] ?? []
        var updatedDetections = detections
        
        if !updatedDetections.contains(bundleIdentifier) {
            updatedDetections.append(bundleIdentifier)
            UserDefaults.standard.set(updatedDetections, forKey: "new_app_detections")
            
            print("💾 Stored new app detection: \(bundleIdentifier)")
        }
    }
    
    private func storeDetailedAppUsageData(bundleIdentifier: String, duration: TimeInterval) {
        // Store detailed app usage data with timestamp
        let usageData = [
            "bundleIdentifier": bundleIdentifier,
            "duration": duration,
            "timestamp": Date().timeIntervalSince1970
        ] as [String: Any]
        
        let key = "detailed_app_usage_\(bundleIdentifier)"
        let existingData = UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? []
        var updatedData = existingData
        updatedData.append(usageData)
        
        // Keep only last 100 entries
        if updatedData.count > 100 {
            updatedData = Array(updatedData.suffix(100))
        }
        
        UserDefaults.standard.set(updatedData, forKey: key)
        
        print("💾 Stored detailed app usage: \(bundleIdentifier) - \(duration) seconds")
    }
    
    // MARK: - Helper Methods
    
    private func getKnownApps() -> Set<String> {
        return Set(UserDefaults.standard.array(forKey: "known_apps") as? [String] ?? [])
    }
    
    private func updateKnownApps(_ currentApps: Set<String>) {
        UserDefaults.standard.set(Array(currentApps), forKey: "known_apps")
        print("💾 Updated known apps: \(currentApps.count) apps")
    }
} 