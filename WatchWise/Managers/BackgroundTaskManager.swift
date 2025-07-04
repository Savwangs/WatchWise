//
//  BackgroundTaskManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 7/2/25.
//

import Foundation
import BackgroundTasks
import FirebaseFirestore

class BackgroundTaskManager: ObservableObject {
    static let shared = BackgroundTaskManager()
    
    private let deviceActivityManager = DeviceActivityDataManager()
    private let db = Firestore.firestore()
    
    private init() {
        registerBackgroundTasks()
    }
    
    // MARK: - Background Task Registration
    
    private func registerBackgroundTasks() {
        // Register daily reset task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.watchwise.dailyreset",
            using: nil
        ) { task in
            self.handleDailyReset(task: task as! BGAppRefreshTask)
        }
        
        // Register data sync task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.watchwise.datasync",
            using: nil
        ) { task in
            self.handleDataSync(task: task as! BGAppRefreshTask)
        }
    }
    
    // MARK: - Schedule Background Tasks
    
    func scheduleBackgroundTasks() {
        scheduleDailyReset()
        scheduleDataSync()
    }
    
    private func scheduleDailyReset() {
        let request = BGAppRefreshTaskRequest(identifier: "com.watchwise.dailyreset")
        request.earliestBeginDate = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Scheduled daily reset background task")
        } catch {
            print("❌ Failed to schedule daily reset: \(error)")
        }
    }
    
    private func scheduleDataSync() {
        let request = BGAppRefreshTaskRequest(identifier: "com.watchwise.datasync")
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60) // 15 minutes from now
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Scheduled data sync background task")
        } catch {
            print("❌ Failed to schedule data sync: \(error)")
        }
    }
    
    // MARK: - Background Task Handlers
    
    private func handleDailyReset(task: BGAppRefreshTask) {
        print("🔄 Starting daily reset background task")
        
        // Set up task expiration
        task.expirationHandler = {
            print("⏰ Daily reset task expired")
            task.setTaskCompleted(success: false)
        }
        
        Task {
            do {
                // Clear cached data
                await clearDailyData()
                
                // Reset device activity data
                await resetDeviceActivityData()
                
                // Schedule next daily reset
                scheduleDailyReset()
                
                print("✅ Daily reset completed successfully")
                task.setTaskCompleted(success: true)
                
            } catch {
                print("❌ Daily reset failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    private func handleDataSync(task: BGAppRefreshTask) {
        print("🔄 Starting data sync background task")
        
        // Set up task expiration
        task.expirationHandler = {
            print("⏰ Data sync task expired")
            task.setTaskCompleted(success: false)
        }
        
        Task {
            do {
                // Sync data for all active devices
                await syncAllDeviceData()
                
                // Schedule next data sync
                scheduleDataSync()
                
                print("✅ Data sync completed successfully")
                task.setTaskCompleted(success: true)
                
            } catch {
                print("❌ Data sync failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    // MARK: - Data Management
    
    private func clearDailyData() async {
        // Clear UserDefaults cache
        let userDefaults = UserDefaults.standard
        let keys = userDefaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("screentime_cache_") }
        for key in keys {
            userDefaults.removeObject(forKey: key)
        }
        
        // Clear shared UserDefaults
        let sharedDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
        sharedDefaults?.removeObject(forKey: "detailed_app_usage_data")
        sharedDefaults?.removeObject(forKey: "hourly_breakdown_data")
        sharedDefaults?.removeObject(forKey: "app_usage_ranges")
        sharedDefaults?.removeObject(forKey: "last_activity_update")
        
        print("🗑️ Cleared daily screen time data")
    }
    
    private func resetDeviceActivityData() async {
        // Reset device activity data in shared UserDefaults
        let userDefaults = UserDefaults(suiteName: "group.com.watchwise.screentime")
        userDefaults?.removeObject(forKey: "detailed_app_usage_data")
        userDefaults?.removeObject(forKey: "hourly_breakdown_data")
        userDefaults?.removeObject(forKey: "app_usage_ranges")
        userDefaults?.set(Date().timeIntervalSince1970, forKey: "last_activity_update")
        
        print("🔄 Reset device activity data")
    }
    
    private func syncAllDeviceData() async {
        // Get all active child devices
        guard let currentUser = Auth.auth().currentUser else {
            print("❌ No authenticated user for data sync")
            return
        }
        
        do {
            let snapshot = try await db.collection("childDevices")
                .whereField("parentId", isEqualTo: currentUser.uid)
                .whereField("isActive", isEqualTo: true)
                .getDocuments()
            
            let devices = try snapshot.documents.compactMap { document -> ChildDevice? in
                try document.data(as: ChildDevice.self)
            }
            
            // Sync data for each device
            for device in devices {
                guard let deviceId = device.id else { continue }
                
                if let screenTimeData = deviceActivityManager.getCurrentScreenTimeData(for: deviceId) {
                    await deviceActivityManager.syncDataToFirebase(for: deviceId, parentId: currentUser.uid)
                    print("✅ Synced data for device: \(device.childName)")
                }
            }
            
        } catch {
            print("❌ Error syncing device data: \(error)")
        }
    }
    
    // MARK: - Public Methods
    
    func startBackgroundProcessing() {
        scheduleBackgroundTasks()
    }
    
    func stopBackgroundProcessing() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
        print("🛑 Cancelled all background tasks")
    }
} 