//
//  ScreenTimeCacheManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 7/2/25.
//

import Foundation

class ScreenTimeCacheManager {
    private let userDefaults = UserDefaults.standard
    private let cacheKeyPrefix = "screentime_cache_"
    private let maxCacheAge: TimeInterval = 24 * 60 * 60 // 24 hours
    
    func cacheScreenTimeData(_ data: ScreenTimeData, for deviceId: String) async {
        let key = "\(cacheKeyPrefix)\(deviceId)"
        
        do {
            let encoder = JSONEncoder()
            let encodedData = try encoder.encode(data)
            
            let cacheEntry = CacheEntry(
                data: encodedData,
                timestamp: Date(),
                deviceId: deviceId
            )
            
            let cacheData = try encoder.encode(cacheEntry)
            userDefaults.set(cacheData, forKey: key)
            
            print("✅ Cached screen time data for device: \(deviceId)")
        } catch {
            print("❌ Failed to cache screen time data: \(error)")
        }
    }
    
    func getCachedScreenTimeData(for deviceId: String) async -> ScreenTimeData? {
        let key = "\(cacheKeyPrefix)\(deviceId)"
        
        guard let cacheData = userDefaults.data(forKey: key) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let cacheEntry = try decoder.decode(CacheEntry.self, from: cacheData)
            
            // Check if cache is still valid
            let age = Date().timeIntervalSince(cacheEntry.timestamp)
            if age > maxCacheAge {
                // Cache is too old, remove it
                userDefaults.removeObject(forKey: key)
                return nil
            }
            
            let screenTimeData = try decoder.decode(ScreenTimeData.self, from: cacheEntry.data)
            print("📱 Retrieved cached screen time data for device: \(deviceId)")
            return screenTimeData
            
        } catch {
            print("❌ Failed to retrieve cached screen time data: \(error)")
            // Remove corrupted cache
            userDefaults.removeObject(forKey: key)
            return nil
        }
    }
    
    func clearCache(for deviceId: String? = nil) {
        if let deviceId = deviceId {
            let key = "\(cacheKeyPrefix)\(deviceId)"
            userDefaults.removeObject(forKey: key)
            print("🗑️ Cleared cache for device: \(deviceId)")
        } else {
            // Clear all cache entries
            let keys = userDefaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(cacheKeyPrefix) }
            for key in keys {
                userDefaults.removeObject(forKey: key)
            }
            print("🗑️ Cleared all screen time cache")
        }
    }
    
    func getCacheSize() -> Int {
        let keys = userDefaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(cacheKeyPrefix) }
        return keys.count
    }
}

// MARK: - Cache Entry Model
private struct CacheEntry: Codable {
    let data: Data
    let timestamp: Date
    let deviceId: String
} 