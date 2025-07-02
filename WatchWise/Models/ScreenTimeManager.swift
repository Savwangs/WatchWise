//
//  ScreenTimeManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//

import Foundation
import FirebaseFirestore

@MainActor
class ScreenTimeManager: ObservableObject {
    @Published var isLoading = false
    @Published var todayScreenTime: ScreenTimeData?
    @Published var pairedDevices: [ChildDevice] = []
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    private let databaseManager = DatabaseManager.shared
    private var realtimeListener: ListenerRegistration?
    
    deinit {
        realtimeListener?.remove()
    }
    
    func loadTodayScreenTime(parentId: String, childDeviceId: String? = nil) {
        isLoading = true
        errorMessage = nil
        
        // DEMO DATA - START (Remove in production)
            Task {
                // Simulate network delay
                try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                
                await MainActor.run {
                    self.pairedDevices = [ChildDevice.demoDevice]
                    self.todayScreenTime = ScreenTimeData.demoData
                    self.isLoading = false
                }
            }
            // DEMO DATA - END (Remove in production)
        
        
        /* PRODUCTION CODE - Uncomment when ready for production
        Task {
            do {
                // Load paired devices from Firebase
                let devices = try await withCheckedThrowingContinuation { continuation in
                    databaseManager.getChildDevices(for: parentId) { result in
                        continuation.resume(with: result)
                    }
                }
                
                await MainActor.run {
                    self.pairedDevices = devices
                }
                
                // Get screen time for first device (can be extended for multiple devices)
                if let firstDevice = devices.first,
                   let deviceId = firstDevice.id {
                    await loadScreenTimeForDevice(deviceId: deviceId)
                } else {
                    await MainActor.run {
                        self.isLoading = false
                        self.errorMessage = "No paired devices found. Please pair a device first."
                    }
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Failed to load paired devices: \(error.localizedDescription)"
                }
            }
        }
        */
    }
    
    private func loadScreenTimeForDevice(deviceId: String) async {
        do {
            let screenTimeData = try await withCheckedThrowingContinuation { continuation in
                databaseManager.getScreenTimeData(for: deviceId, date: Date()) { result in
                    continuation.resume(with: result)
                }
            }
            
            await MainActor.run {
                self.todayScreenTime = screenTimeData
                self.isLoading = false
            }
            
            // Set up real-time updates
            setupRealtimeUpdates(for: deviceId)
            
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "No screen time data available for today. Make sure the child device is actively collecting data."
            }
        }
    }
    
    func refreshData(parentId: String, childDeviceId: String? = nil) {
        // DEMO DATA - START (Remove in production)
        todayScreenTime = nil
        isLoading = true
            
        Task {
            // Simulate refresh delay
            try await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
                
            await MainActor.run {
                // Slightly modify demo data to show "refresh" effect
                var refreshedData = ScreenTimeData.demoData
                // Add a few more minutes to total time to simulate real-time updates
                let additionalTime: TimeInterval = Double.random(in: 300...900) // 5-15 minutes
                refreshedData = ScreenTimeData(
                    id: refreshedData.id,
                    deviceId: refreshedData.deviceId,
                    date: refreshedData.date,
                    totalScreenTime: refreshedData.totalScreenTime + additionalTime,
                    appUsages: refreshedData.appUsages,
                    hourlyBreakdown: refreshedData.hourlyBreakdown
                )
                    
                self.todayScreenTime = refreshedData
                self.isLoading = false
            }
        }
        // DEMO DATA - END (Remove in production)
        
        /* PRODUCTION CODE - Uncomment when ready for production
        todayScreenTime = nil
        loadTodayScreenTime(parentId: parentId)
         */
    }
    
    // MARK: - Real-time Updates
    private func setupRealtimeUpdates(for deviceId: String) {
        // Remove existing listener
        realtimeListener?.remove()
        
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? Date()
        
        realtimeListener = db.collection("screenTimeData")
            .whereField("deviceId", isEqualTo: deviceId)
            .whereField("date", isGreaterThanOrEqualTo: today)
            .whereField("date", isLessThan: tomorrow)
            .order(by: "date", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    Task { @MainActor in
                        self.errorMessage = "Real-time update failed: \(error.localizedDescription)"
                    }
                    return
                }
                
                guard let documents = snapshot?.documents,
                      let latestDoc = documents.first else {
                    return
                }
                
                do {
                    let updatedData = try latestDoc.data(as: ScreenTimeData.self)
                    Task { @MainActor in
                        self.todayScreenTime = updatedData
                    }
                } catch {
                    Task { @MainActor in
                        self.errorMessage = "Failed to parse updated data: \(error.localizedDescription)"
                    }
                }
            }
    }
    func loadScreenTimeForAllDevices(parentId: String) async -> [String: ScreenTimeData] {
        var allScreenTimeData: [String: ScreenTimeData] = [:]
        
        do {
            let devices = try await withCheckedThrowingContinuation { continuation in
                databaseManager.getChildDevices(for: parentId) { result in
                    continuation.resume(with: result)
                }
            }
            
            for device in devices {
                guard let deviceId = device.id else { continue }
                
                do {
                    let screenTimeData = try await withCheckedThrowingContinuation { continuation in
                        databaseManager.getScreenTimeData(for: deviceId, date: Date()) { result in
                            continuation.resume(with: result)
                        }
                    }
                    allScreenTimeData[deviceId] = screenTimeData
                } catch {
                    print("Failed to load screen time for device \(deviceId): \(error)")
                }
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load devices: \(error.localizedDescription)"
            }
        }
        
        return allScreenTimeData
    }
    func loadHistoricalData(parentId: String, days: Int = 7) async -> [Date: ScreenTimeData] {
        var historicalData: [Date: ScreenTimeData] = [:]
        
        do {
            let devices = try await withCheckedThrowingContinuation { continuation in
                databaseManager.getChildDevices(for: parentId) { result in
                    continuation.resume(with: result)
                }
            }
            
            guard let firstDevice = devices.first,
                  let deviceId = firstDevice.id else {
                return historicalData
            }
            
            let calendar = Calendar.current
            
            for i in 0..<days {
                guard let date = calendar.date(byAdding: .day, value: -i, to: Date()) else { continue }
                let dayStart = calendar.startOfDay(for: date)
                
                do {
                    let screenTimeData = try await withCheckedThrowingContinuation { continuation in
                        databaseManager.getScreenTimeData(for: deviceId, date: dayStart) { result in
                            continuation.resume(with: result)
                        }
                    }
                    historicalData[dayStart] = screenTimeData
                } catch {
                    // No data for this day - continue
                    continue
                }
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load historical data: \(error.localizedDescription)"
            }
        }
        
        return historicalData
    }
    
    // MARK: - Data Export
    func exportScreenTimeData(parentId: String, format: ExportFormat = .csv) async -> Data? {
        do {
            let historicalData = await loadHistoricalData(parentId: parentId, days: 30)
            
            switch format {
            case .csv:
                return generateCSVData(from: historicalData)
            case .json:
                return generateJSONData(from: historicalData)
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to export data: \(error.localizedDescription)"
            }
            return nil
        }
    }
    
    private func generateCSVData(from data: [Date: ScreenTimeData]) -> Data? {
        var csvContent = "Date,Total Screen Time (minutes),Top App,Top App Duration (minutes)\n"
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        
        for (date, screenTimeData) in data.sorted(by: { $0.key < $1.key }) {
            let totalMinutes = Int(screenTimeData.totalScreenTime / 60)
            let topApp = screenTimeData.appUsages.first
            let topAppName = topApp?.appName ?? "N/A"
            let topAppMinutes = Int((topApp?.duration ?? 0) / 60)
            
            csvContent += "\(formatter.string(from: date)),\(totalMinutes),\(topAppName),\(topAppMinutes)\n"
        }
        
        return csvContent.data(using: .utf8)
    }
    
    private func generateJSONData(from data: [Date: ScreenTimeData]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            return try encoder.encode(data)
        } catch {
            return nil
        }
    }
    
    // MARK: - Utility Methods
    func clearError() {
        errorMessage = nil
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
}
enum ExportFormat {
    case csv
    case json
}
