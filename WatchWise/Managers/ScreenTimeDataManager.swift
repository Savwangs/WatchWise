//
//  ScreenTimeDataManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/7/25.
//

import Foundation
import FamilyControls
import DeviceActivity
import ManagedSettings
import SwiftUI
import FirebaseFirestore

@MainActor
class ScreenTimeDataManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var isLoading = false
    @Published var currentScreenTimeData: ScreenTimeData?
    @Published var errorMessage: String?
    
    private let authorizationCenter = AuthorizationCenter.shared
    private let db = Firestore.firestore()
    private let databaseManager = DatabaseManager.shared
    private var deviceActivityCenter = DeviceActivityCenter()

    init() {
        checkAuthorizationStatus()
    }

    func checkAuthorizationStatus() {
        switch authorizationCenter.authorizationStatus {
        case .approved:
            isAuthorized = true
        case .denied, .notDetermined:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
    }
    
    func requestAuthorization() async {
        do {
            try await authorizationCenter.requestAuthorization(for: .individual)
            await MainActor.run {
                checkAuthorizationStatus()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to get Screen Time authorization: \(error.localizedDescription)"
            }
        }
    }

    func startScreenTimeMonitoring(for deviceId: String) async {
        guard isAuthorized else {
            errorMessage = "Screen Time authorization required"
            return
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            // Start device activity monitoring
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: 0, minute: 0),
                intervalEnd: DateComponents(hour: 23, minute: 59),
                repeats: true
            )
            
            let activityName = DeviceActivityName("DailyScreenTime_\(deviceId)")
            
            try deviceActivityCenter.startMonitoring(activityName, during: schedule)
            
            // Collect current screen time data
            await collectTodayScreenTimeData(for: deviceId)
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to start monitoring: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    func collectTodayScreenTimeData(for deviceId: String) async {
        guard isAuthorized else { return }
        
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? Date()
        
        do {
            // Get app usage data using DeviceActivity
            let appUsageData = await getAppUsageData(from: today, to: tomorrow)
            let hourlyBreakdown = await getHourlyBreakdown(from: today, to: tomorrow)
            
            let totalScreenTime = appUsageData.reduce(0) { $0 + $1.duration }
            
            let screenTimeData = ScreenTimeData(
                id: nil,
                deviceId: deviceId,
                date: today,
                totalScreenTime: totalScreenTime,
                appUsages: appUsageData,
                hourlyBreakdown: hourlyBreakdown
            )
            
            // Save to Firebase
            await saveScreenTimeData(screenTimeData)
            
            await MainActor.run {
                self.currentScreenTimeData = screenTimeData
                self.isLoading = false
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to collect screen time data: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func getAppUsageData(from startDate: Date, to endDate: Date) async -> [AppUsage] {
        // This is a simplified version - in a real implementation, you would use
        // DeviceActivityReport to get actual usage data
        
        // For now, we'll simulate getting data from the system
        // In production, you'd implement DeviceActivityReportExtension
        
        var appUsages: [AppUsage] = []
        
        // Get installed apps and their usage (simplified)
        let commonApps = [
            ("Instagram", "com.burbn.instagram"),
            ("TikTok", "com.zhiliaoapp.musically"),
            ("YouTube", "com.google.ios.youtube"),
            ("Safari", "com.apple.mobilesafari"),
            ("Messages", "com.apple.MobileSMS"),
            ("Snapchat", "com.toyopagroup.picaboo"),
            ("WhatsApp", "net.whatsapp.WhatsApp"),
            ("Discord", "com.hammerandchisel.discord"),
            ("Twitter", "com.atebits.Tweetie2"),
            ("Facebook", "com.facebook.Facebook")
        ]
        
        // Note: In production, you would replace this with actual DeviceActivity data
        // This is a placeholder until Apple's DeviceActivityReport is properly implemented
        
        return appUsages
    }
    
    private func getHourlyBreakdown(from startDate: Date, to endDate: Date) async -> [Int: TimeInterval] {
        // Similar to above - this would use DeviceActivityReport in production
        var breakdown: [Int: TimeInterval] = [:]
        
        // Placeholder implementation
        // In production, this would aggregate actual usage data by hour
        
        return breakdown
    }

    func saveScreenTimeData(_ data: ScreenTimeData) async {
        do {
            try await withCheckedThrowingContinuation { continuation in
                databaseManager.saveScreenTimeData(data) { result in
                    continuation.resume(with: result)
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to save screen time data: \(error.localizedDescription)"
            }
        }
    }
    
    func loadScreenTimeData(for deviceId: String, date: Date = Date()) async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let screenTimeData = try await withCheckedThrowingContinuation { continuation in
                databaseManager.getScreenTimeData(for: deviceId, date: date) { result in
                    continuation.resume(with: result)
                }
            }
            
            await MainActor.run {
                self.currentScreenTimeData = screenTimeData
                self.isLoading = false
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load screen time data: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    func setupRealtimeUpdates(for deviceId: String) {
        // Set up Firestore listener for real-time updates
        let today = Calendar.current.startOfDay(for: Date())
        
        db.collection("screenTimeData")
            .whereField("deviceId", isEqualTo: deviceId)
            .whereField("date", isGreaterThanOrEqualTo: today)
            .whereField("date", isLessThan: Calendar.current.date(byAdding: .day, value: 1, to: today) ?? Date())
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    Task { @MainActor in
                        self.errorMessage = "Real-time update error: \(error.localizedDescription)"
                    }
                    return
                }
                
                guard let documents = snapshot?.documents,
                      let latestDoc = documents.first else { return }
                
                do {
                    let screenTimeData = try latestDoc.data(as: ScreenTimeData.self)
                    Task { @MainActor in
                        self.currentScreenTimeData = screenTimeData
                    }
                } catch {
                    Task { @MainActor in
                        self.errorMessage = "Failed to parse real-time data: \(error.localizedDescription)"
                    }
                }
            }
    }

    func syncScreenTimeData(for deviceId: String) async {
        guard isAuthorized else { return }
        
        await MainActor.run {
            isLoading = true
        }
        
        // Collect fresh data
        await collectTodayScreenTimeData(for: deviceId)
        
        // Send update notification to parent
        await notifyParentOfUpdate(deviceId: deviceId)
    }
    
    private func notifyParentOfUpdate(deviceId: String) async {
        // Notify parent device of screen time update
        do {
            try await withCheckedThrowingContinuation { continuation in
                databaseManager.updateDeviceLastSync(deviceId: deviceId) { result in
                    continuation.resume(with: result)
                }
            }
        } catch {
            print("Failed to update last sync time: \(error)")
        }
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    func getTopApps(from appUsages: [AppUsage], limit: Int = 5) -> [AppUsage] {
        return Array(appUsages.sorted { $0.duration > $1.duration }.prefix(limit))
    }

    func clearError() {
        errorMessage = nil
    }

    var isDemoMode: Bool {
        return !isAuthorized || currentScreenTimeData?.deviceId == "demo-device"
    }
}

extension ScreenTimeDataManager {
    
    func stopMonitoring(for deviceId: String) {
        let activityName = DeviceActivityName("DailyScreenTime_\(deviceId)")
        deviceActivityCenter.stopMonitoring([activityName])
    }
    
    // Set up monitoring schedule
    private func createMonitoringSchedule() -> DeviceActivitySchedule {
        let startComponents = DateComponents(hour: 0, minute: 0)
        let endComponents = DateComponents(hour: 23, minute: 59)
        
        return DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: true
        )
    }
}

