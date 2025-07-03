//
//  ScreenTimeManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class ScreenTimeManager: ObservableObject {
    @Published var isLoading = false
    @Published var todayScreenTime: ScreenTimeData?
    @Published var pairedDevices: [ChildDevice] = []
    @Published var errorMessage: String?
    @Published var isOffline = false
    @Published var lastSyncTime: Date?
    
    private let db = Firestore.firestore()
    private let databaseManager = DatabaseManager.shared
    private var realtimeListeners: [String: ListenerRegistration] = [:]
    private var cacheManager = ScreenTimeCacheManager()
    
    deinit {
        Task {
            await removeAllListeners()
        }
    }
    
    // MARK: - Data Loading Methods
    func loadTodayScreenTime(parentId: String, childDeviceId: String? = nil) {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Check network connectivity
                if !NetworkMonitor.shared.isConnected {
                    await loadCachedData(parentId: parentId, childDeviceId: childDeviceId)
                    return
                }
                
                // Load paired devices from Firebase
                let devices = try await withCheckedThrowingContinuation { continuation in
                    databaseManager.getChildDevices(for: parentId) { result in
                        continuation.resume(with: result)
                    }
                }
                
                await MainActor.run {
                    self.pairedDevices = devices
                }
                
                // Get screen time for selected device or first device
                let targetDeviceId = childDeviceId ?? devices.first?.id
                
                if let deviceId = targetDeviceId {
                    await loadScreenTimeForDevice(deviceId: deviceId)
                    await setupRealtimeUpdates(for: deviceId)
                } else {
                    await MainActor.run {
                        self.isLoading = false
                        self.errorMessage = "No paired devices found. Please pair a device first."
                    }
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Failed to load data: \(error.localizedDescription)"
                }
                
                // Fallback to cached data
                await loadCachedData(parentId: parentId, childDeviceId: childDeviceId)
            }
        }
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
                self.lastSyncTime = Date()
                self.isOffline = false
            }
            
            // Cache the data for offline access
            if let data = screenTimeData {
                await cacheManager.cacheScreenTimeData(data, for: deviceId)
            }
            
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "No screen time data available for today. Make sure the child device is actively collecting data."
            }
        }
    }
    
    private func loadCachedData(parentId: String, childDeviceId: String?) async {
        await MainActor.run {
            self.isOffline = true
            self.isLoading = true
        }
        
        // Load cached data
        if let cachedData = await cacheManager.getCachedScreenTimeData(for: childDeviceId ?? "default") {
            await MainActor.run {
                self.todayScreenTime = cachedData
                self.isLoading = false
                self.errorMessage = "Showing cached data (offline mode)"
            }
        } else {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "No cached data available. Please check your internet connection."
            }
        }
    }
    
    func refreshData(parentId: String, childDeviceId: String? = nil) {
        todayScreenTime = nil
        loadTodayScreenTime(parentId: parentId, childDeviceId: childDeviceId)
    }
    
    // MARK: - Real-time Updates
    private func setupRealtimeUpdates(for deviceId: String) async {
        // Remove existing listener for this device
        realtimeListeners[deviceId]?.remove()
        
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? Date()
        
        let listener = db.collection("screenTimeData")
            .whereField("deviceId", isEqualTo: deviceId)
            .whereField("date", isGreaterThanOrEqualTo: today)
            .whereField("date", isLessThan: tomorrow)
            .order(by: "date", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.errorMessage = "Real-time update failed: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let documents = snapshot?.documents,
                          let latestDoc = documents.first else {
                        return
                    }
                    
                    do {
                        let updatedData = try latestDoc.data(as: ScreenTimeData.self)
                        self.todayScreenTime = updatedData
                        self.lastSyncTime = Date()
                        self.isOffline = false
                        
                        // Cache the updated data
                        await self.cacheManager.cacheScreenTimeData(updatedData, for: deviceId)
                        
                    } catch {
                        self.errorMessage = "Failed to parse updated data: \(error.localizedDescription)"
                    }
                }
            }
        
        realtimeListeners[deviceId] = listener
    }
    
    private func removeAllListeners() async {
        for (_, listener) in realtimeListeners {
            listener.remove()
        }
        realtimeListeners.removeAll()
    }
    
    // MARK: - Cross-Device Synchronization
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
                    
                    if let data = screenTimeData {
                        allScreenTimeData[deviceId] = data
                        await cacheManager.cacheScreenTimeData(data, for: deviceId)
                    }
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
    
    // MARK: - Historical Data
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
                    
                    if let data = screenTimeData {
                        historicalData[dayStart] = data
                        await cacheManager.cacheScreenTimeData(data, for: deviceId)
                    }
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
    
    // MARK: - Data Aggregation
    func getAggregatedScreenTimeData(parentId: String, days: Int = 7) async -> ScreenTimeAggregation {
        let historicalData = await loadHistoricalData(parentId: parentId, days: days)
        
        var totalScreenTime: TimeInterval = 0
        var appUsageTotals: [String: TimeInterval] = [:]
        var dailyAverages: [TimeInterval] = []
        
        for (_, data) in historicalData {
            totalScreenTime += data.totalScreenTime
            dailyAverages.append(data.totalScreenTime)
            
            for appUsage in data.appUsages {
                appUsageTotals[appUsage.appName, default: 0] += appUsage.duration
            }
        }
        
        let averageDailyScreenTime = dailyAverages.isEmpty ? 0 : dailyAverages.reduce(0, +) / Double(dailyAverages.count)
        
        let sortedApps = appUsageTotals.sorted { $0.value > $1.value }
        let topApps = sortedApps.prefix(5).map { (appName, duration) in
            AppUsage(
                appName: appName,
                bundleIdentifier: "", // We don't have bundle IDs in aggregated data
                duration: duration,
                timestamp: Date(),
                usageRanges: nil
            )
        }
        
        return ScreenTimeAggregation(
            totalScreenTime: totalScreenTime,
            averageDailyScreenTime: averageDailyScreenTime,
            topApps: Array(topApps),
            daysAnalyzed: days
        )
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
        
        let sortedData = data.sorted(by: { $0.key < $1.key })
        for (date, screenTimeData) in sortedData {
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
    
    func disconnect() {
        Task {
            await removeAllListeners()
        }
    }
}

// MARK: - Supporting Types
enum ExportFormat {
    case csv
    case json
}

struct ScreenTimeAggregation {
    let totalScreenTime: TimeInterval
    let averageDailyScreenTime: TimeInterval
    let topApps: [AppUsage]
    let daysAnalyzed: Int
}

// MARK: - Cache Manager
actor ScreenTimeCacheManager {
    private let cache = NSCache<NSString, CachedScreenTimeData>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ScreenTimeCache")
        
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func cacheScreenTimeData(_ data: ScreenTimeData, for deviceId: String) {
        let cachedData = CachedScreenTimeData(data: data)
        cache.setObject(cachedData, forKey: deviceId as NSString)
        
        // Also save to disk for persistence
        let fileURL = cacheDirectory.appendingPathComponent("\(deviceId)_\(Date().timeIntervalSince1970).json")
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: fileURL)
        } catch {
            print("Failed to cache screen time data: \(error)")
        }
    }
    
    func getCachedScreenTimeData(for deviceId: String) -> ScreenTimeData? {
        // First check memory cache
        if let cachedData = cache.object(forKey: deviceId as NSString) {
            return cachedData.data
        }
        
        // Then check disk cache
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            let deviceFiles = files.filter { $0.lastPathComponent.hasPrefix(deviceId) }
            
            if let latestFile = deviceFiles.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first {
                let jsonData = try Data(contentsOf: latestFile)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let data = try decoder.decode(ScreenTimeData.self, from: jsonData)
                
                // Update memory cache
                let cachedData = CachedScreenTimeData(data: data)
                cache.setObject(cachedData, forKey: deviceId as NSString)
                return data
            }
        } catch {
            print("Failed to load cached screen time data: \(error)")
        }
        
        return nil
    }
    
    func clearCache() {
        cache.removeAllObjects()
        
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
        } catch {
            print("Failed to clear cache: \(error)")
        }
    }
}

// MARK: - Cached Data Wrapper Class
class CachedScreenTimeData {
    let data: ScreenTimeData
    
    init(data: ScreenTimeData) {
        self.data = data
    }
}

// MARK: - Network Monitor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    @Published var isConnected = true
    
    private init() {
        // In a real app, you would implement actual network monitoring
        // For now, we'll assume connected
        isConnected = true
    }
}
