//
//  DatabaseManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/7/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    private let db = FirebaseManager.shared.db
    
    private init() {}
    
    func createUserProfile(user: AppUser, completion: @escaping (Result<Void, Error>) -> Void) {
        let userData: [String: Any] = [
            "email": user.email,
            "isDevicePaired": user.isDevicePaired,
            "hasCompletedOnboarding": user.hasCompletedOnboarding,
            "userType": user.userType ?? NSNull(),
            "createdAt": Timestamp(date: user.createdAt)
        ]
        
        FirebaseManager.shared.usersCollection.document(user.id).setData(userData) { error in
            if let error = error {
                print("🔥 Error creating user profile: \(error)")
                completion(.failure(error))
            } else {
                print("✅ User profile created successfully")
                completion(.success(()))
            }
        }
    }
    
    func updateUserProfile(userId: String, data: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        FirebaseManager.shared.usersCollection.document(userId).updateData(data) { error in
            if let error = error {
                print("🔥 Error updating user profile: \(error)")
                completion(.failure(error))
            } else {
                print("✅ User profile updated successfully")
                completion(.success(()))
            }
        }
    }
    
    func getUserProfile(userId: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        FirebaseManager.shared.usersCollection.document(userId).getDocument { snapshot, error in
            if let error = error {
                print("🔥 Error fetching user profile: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let data = snapshot?.data() else {
                completion(.failure(FirebaseManager.FirebaseError.documentNotFound))
                return
            }
            
            let appUser = AppUser(
                id: userId,
                email: data["email"] as? String ?? "",
                isDevicePaired: data["isDevicePaired"] as? Bool ?? false,
                hasCompletedOnboarding: data["hasCompletedOnboarding"] as? Bool ?? false,
                userType: data["userType"] as? String,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            )
            
            completion(.success(appUser))
        }
    }
    
    func createFamily(parentId: String, completion: @escaping (Result<String, Error>) -> Void) {
        let familyData: [String: Any] = [
            "parentId": parentId,
            "createdAt": Timestamp(),
            "isActive": true
        ]
        
        let familyRef = FirebaseManager.shared.familiesCollection.document()
        familyRef.setData(familyData) { error in
            if let error = error {
                print("🔥 Error creating family: \(error)")
                completion(.failure(error))
            } else {
                print("✅ Family created successfully: \(familyRef.documentID)")
                completion(.success(familyRef.documentID))
            }
        }
    }
    
    func getFamilyByParentId(parentId: String, completion: @escaping (Result<String?, Error>) -> Void) {
        FirebaseManager.shared.familiesCollection
            .whereField("parentId", isEqualTo: parentId)
            .whereField("isActive", isEqualTo: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("🔥 Error fetching family: \(error)")
                    completion(.failure(error))
                    return
                }
                
                let familyId = snapshot?.documents.first?.documentID
                completion(.success(familyId))
            }
    }
    
    func addChildDevice(_ device: ChildDevice, to familyId: String, completion: @escaping (Result<String, Error>) -> Void) {
        let deviceData: [String: Any] = [
            "childName": device.childName,
            "deviceName": device.deviceName,
            "pairCode": device.pairCode,
            "parentId": device.parentId,
            "familyId": familyId,
            "pairedAt": device.pairedAt,
            "isActive": device.isActive
        ]
        
        let deviceRef = FirebaseManager.shared.devicesCollection.document()
        deviceRef.setData(deviceData) { error in
            if let error = error {
                print("🔥 Error adding child device: \(error)")
                completion(.failure(error))
            } else {
                print("✅ Child device added successfully: \(deviceRef.documentID)")
                completion(.success(deviceRef.documentID))
            }
        }
    }
    
    func getChildDevices(for parentId: String, completion: @escaping (Result<[ChildDevice], Error>) -> Void) {
        FirebaseManager.shared.devicesCollection
            .whereField("parentId", isEqualTo: parentId)
            .whereField("isActive", isEqualTo: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("🔥 Error fetching child devices: \(error)")
                    completion(.failure(error))
                    return
                }
                
                var devices: [ChildDevice] = []
                
                for document in snapshot?.documents ?? [] {
                    let data = document.data()
                    let device = ChildDevice(
                        childName: data["childName"] as? String ?? "",
                        deviceName: data["deviceName"] as? String ?? "",
                        pairCode: data["pairCode"] as? String ?? "",
                        parentId: data["parentId"] as? String ?? "",
                        pairedAt: data["pairedAt"] as? Timestamp ?? Timestamp(),
                        isActive: data["isActive"] as? Bool ?? true
                    )
                    devices.append(device)
                }
                
                print("✅ Fetched \(devices.count) child devices")
                completion(.success(devices))
            }
    }
    
    func saveScreenTimeData(_ data: ScreenTimeData, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🔍 Saving screen time data for device: \(data.deviceId)")
        
        // Ensure all string fields are actually strings
        let safeDeviceId = String(describing: data.deviceId)
        
        let screenTimeData: [String: Any] = [
            "deviceId": safeDeviceId,
            "date": Timestamp(date: data.date),
            "totalScreenTime": data.totalScreenTime,
            "appUsages": data.appUsages.map { usage in
                [
                    "appName": String(describing: usage.appName),
                    "bundleIdentifier": String(describing: usage.bundleIdentifier),
                    "duration": usage.duration,
                    "timestamp": Timestamp(date: usage.timestamp)
                ]
            },
            // Convert all keys to strings for Firestore
            "hourlyBreakdown": Dictionary(uniqueKeysWithValues: data.hourlyBreakdown.map { (String($0.key), $0.value) })
        ]
        
        print("🔍 Screen time data prepared:")
        print("   - Device ID: \(safeDeviceId)")
        print("   - App usages count: \(data.appUsages.count)")
        print("   - Hourly breakdown count: \(data.hourlyBreakdown.count)")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateKey = dateFormatter.string(from: data.date)
        let documentId = "\(data.deviceId)_\(dateKey)"
        
        FirebaseManager.shared.screenTimeCollection.document(documentId).setData(screenTimeData, merge: true) { error in
            if let error = error {
                print("🔥 Error saving screen time data: \(error)")
                completion(.failure(error))
            } else {
                print("✅ Screen time data saved successfully")
                completion(.success(()))
            }
        }
    }
    
    func getScreenTimeData(for deviceId: String, date: Date, completion: @escaping (Result<ScreenTimeData?, Error>) -> Void) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateKey = dateFormatter.string(from: date)
        let documentId = "\(deviceId)_\(dateKey)"
        
        FirebaseManager.shared.screenTimeCollection.document(documentId).getDocument { snapshot, error in
            if let error = error {
                print("🔥 Error fetching screen time data: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let data = snapshot?.data() else {
                completion(.success(nil))
                return
            }
            
            let appUsagesData = data["appUsages"] as? [[String: Any]] ?? []
            let appUsages = appUsagesData.compactMap { usageData -> AppUsage? in
                // Safely extract appName with type conversion
                let appName: String
                if let nameData = usageData["appName"] {
                    if let stringName = nameData as? String {
                        appName = stringName
                    } else if let numberName = nameData as? NSNumber {
                        appName = numberName.stringValue
                    } else {
                        appName = String(describing: nameData)
                    }
                } else {
                    appName = "Unknown App"
                }
                // Safely extract bundleIdentifier with type conversion
                let bundleId: String
                if let bundleData = usageData["bundleIdentifier"] {
                    if let stringBundle = bundleData as? String {
                        bundleId = stringBundle
                    } else if let numberBundle = bundleData as? NSNumber {
                        bundleId = numberBundle.stringValue
                    } else {
                        bundleId = String(describing: bundleData)
                    }
                } else {
                    bundleId = "unknown.bundle"
                }
                guard let duration = usageData["duration"] as? TimeInterval,
                      let timestamp = (usageData["timestamp"] as? Timestamp)?.dateValue() else {
                    return nil
                }
                return AppUsage(
                    appName: appName,
                    bundleIdentifier: bundleId,
                    duration: duration,
                    timestamp: timestamp,
                    usageRanges: nil
                )
            }
            
            let hourlyBreakdown = data["hourlyBreakdown"] as? [String: TimeInterval] ?? [:]
            let hourlyBreakdownInt = Dictionary(uniqueKeysWithValues: hourlyBreakdown.compactMap { key, value in
                Int(key).map { ($0, value) }
            })
            
            let screenTimeData = ScreenTimeData(
                deviceId: data["deviceId"] as? String ?? deviceId,
                date: (data["date"] as? Timestamp)?.dateValue() ?? date,
                totalScreenTime: data["totalScreenTime"] as? TimeInterval ?? 0,
                appUsages: appUsages,
                hourlyBreakdown: hourlyBreakdownInt
            )
            
            completion(.success(screenTimeData))
        }
    }
    
    func listenToScreenTimeUpdates(for deviceId: String, completion: @escaping (ScreenTimeData?) -> Void) -> ListenerRegistration {
        let today = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateKey = dateFormatter.string(from: today)
        let documentId = "\(deviceId)_\(dateKey)"
        
        return FirebaseManager.shared.screenTimeCollection.document(documentId).addSnapshotListener { snapshot, error in
            if let error = error {
                print("🔥 Error listening to screen time updates: \(error)")
                completion(nil)
                return
            }
            
            guard let data = snapshot?.data() else {
                completion(nil)
                return
            }
            
            // Convert data to ScreenTimeData object (same logic as getScreenTimeData)
            let appUsagesData = data["appUsages"] as? [[String: Any]] ?? []
            let appUsages = appUsagesData.compactMap { usageData -> AppUsage? in
                // Safely extract appName with type conversion
                let appName: String
                if let nameData = usageData["appName"] {
                    if let stringName = nameData as? String {
                        appName = stringName
                    } else if let numberName = nameData as? NSNumber {
                        appName = numberName.stringValue
                    } else {
                        appName = String(describing: nameData)
                    }
                } else {
                    appName = "Unknown App"
                }
                // Safely extract bundleIdentifier with type conversion
                let bundleId: String
                if let bundleData = usageData["bundleIdentifier"] {
                    if let stringBundle = bundleData as? String {
                        bundleId = stringBundle
                    } else if let numberBundle = bundleData as? NSNumber {
                        bundleId = numberBundle.stringValue
                    } else {
                        bundleId = String(describing: bundleData)
                    }
                } else {
                    bundleId = "unknown.bundle"
                }
                guard let duration = usageData["duration"] as? TimeInterval,
                      let timestamp = (usageData["timestamp"] as? Timestamp)?.dateValue() else {
                    return nil
                }
                return AppUsage(
                    appName: appName,
                    bundleIdentifier: bundleId,
                    duration: duration,
                    timestamp: timestamp,
                    usageRanges: nil
                )
            }
            
            let hourlyBreakdown = data["hourlyBreakdown"] as? [String: TimeInterval] ?? [:]
            let hourlyBreakdownInt = Dictionary(uniqueKeysWithValues: hourlyBreakdown.compactMap { key, value in
                Int(key).map { ($0, value) }
            })
            
            let screenTimeData = ScreenTimeData(
                deviceId: data["deviceId"] as? String ?? deviceId,
                date: (data["date"] as? Timestamp)?.dateValue() ?? today,
                totalScreenTime: data["totalScreenTime"] as? TimeInterval ?? 0,
                appUsages: appUsages,
                hourlyBreakdown: hourlyBreakdownInt
            )
            
            completion(screenTimeData)
        }
    }
    
    func updateDeviceLastSync(deviceId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let updateData: [String: Any] = [
            "lastSyncAt": Timestamp(),
            "lastActiveAt": Timestamp()
        ]
        
        // Use setData with merge option to create document if it doesn't exist
        FirebaseManager.shared.devicesCollection.document(deviceId).setData(updateData, merge: true) { error in
            if let error = error {
                print("🔥 Error updating device last sync: \(error)")
                completion(.failure(error))
            } else {
                print("✅ Device last sync updated successfully")
                completion(.success(()))
            }
        }
    }
    
    // Check if a child account already has pairing data
    func checkChildAccountPairing(userId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        FirebaseManager.shared.devicesCollection
            .whereField("childUserId", isEqualTo: userId)
            .whereField("isActive", isEqualTo: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("🔥 Error checking child pairing: \(error)")
                    completion(.failure(error))
                    return
                }
                
                let isPaired = !(snapshot?.documents.isEmpty ?? true)
                completion(.success(isPaired))
            }
    }
    
    // MARK: - New App Detection
    
    func saveNewAppDetection(_ detection: NewAppDetection, completion: @escaping (Result<Void, Error>) -> Void) {
        let detectionData: [String: Any] = [
            "appName": detection.appName,
            "bundleIdentifier": detection.bundleIdentifier,
            "category": detection.category,
            "detectedAt": Timestamp(date: detection.detectedAt),
            "deviceId": detection.deviceId,
            "isNotified": false
        ]
        
        FirebaseManager.shared.db.collection("newAppDetections").addDocument(data: detectionData) { error in
            if let error = error {
                print("🔥 Error saving new app detection: \(error)")
                completion(.failure(error))
            } else {
                print("✅ New app detection saved successfully")
                completion(.success(()))
            }
        }
    }
    
    func getNewAppDetections(for deviceId: String, completion: @escaping (Result<[NewAppDetection], Error>) -> Void) {
        FirebaseManager.shared.db.collection("newAppDetections")
            .whereField("deviceId", isEqualTo: deviceId)
            .order(by: "detectedAt", descending: true)
            .limit(to: 50)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("🔥 Error fetching new app detections: \(error)")
                    completion(.failure(error))
                    return
                }
                
                let detections = snapshot?.documents.compactMap { document -> NewAppDetection? in
                    let data = document.data()
                    guard let appName = data["appName"] as? String,
                          let bundleIdentifier = data["bundleIdentifier"] as? String,
                          let detectedAt = (data["detectedAt"] as? Timestamp)?.dateValue(),
                          let deviceId = data["deviceId"] as? String else {
                        return nil
                    }
                    
                    return NewAppDetection(
                        appName: appName,
                        bundleIdentifier: bundleIdentifier,
                        category: data["category"] as? String ?? "Unknown",
                        detectedAt: detectedAt,
                        deviceId: deviceId
                    )
                } ?? []
                
                print("✅ Fetched \(detections.count) new app detections")
                completion(.success(detections))
            }
    }
    
    func markNewAppDetectionAsNotified(_ detectionId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        FirebaseManager.shared.db.collection("newAppDetections")
            .document(detectionId)
            .updateData([
                "isNotified": true,
                "notifiedAt": Timestamp()
            ]) { error in
                if let error = error {
                    print("🔥 Error marking detection as notified: \(error)")
                    completion(.failure(error))
                } else {
                    print("✅ New app detection marked as notified")
                    completion(.success(()))
                }
            }
    }
    
    // MARK: - Enhanced Screen Time Methods
    
    func saveScreenTimeDataWithRealtime(_ data: ScreenTimeData, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🔍 Saving screen time data with real-time updates for device: \(data.deviceId)")
        
        // Ensure all string fields are actually strings
        let safeDeviceId = String(describing: data.deviceId)
        
        let screenTimeData: [String: Any] = [
            "deviceId": safeDeviceId,
            "date": Timestamp(date: data.date),
            "totalScreenTime": data.totalScreenTime,
            "appUsages": data.appUsages.map { usage in
                [
                    "appName": String(describing: usage.appName),
                    "bundleIdentifier": String(describing: usage.bundleIdentifier),
                    "duration": usage.duration,
                    "timestamp": Timestamp(date: usage.timestamp),
                    "usageRanges": usage.usageRanges?.map { range in
                        [
                            "startTime": Timestamp(date: range.startTime),
                            "endTime": Timestamp(date: range.endTime),
                            "duration": range.duration,
                            "sessionId": range.sessionId
                        ]
                    } ?? []
                ]
            },
            // Convert all keys to strings for Firestore
            "hourlyBreakdown": Dictionary(uniqueKeysWithValues: data.hourlyBreakdown.map { (String($0.key), $0.value) }),
            "lastUpdated": Timestamp(),
            "isRealtime": true
        ]
        
        print("🔍 Enhanced screen time data prepared:")
        print("   - Device ID: \(safeDeviceId)")
        print("   - App usages count: \(data.appUsages.count)")
        print("   - Hourly breakdown count: \(data.hourlyBreakdown.count)")
        print("   - Real-time enabled: true")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateKey = dateFormatter.string(from: data.date)
        let documentId = "\(data.deviceId)_\(dateKey)"
        
        FirebaseManager.shared.screenTimeCollection.document(documentId).setData(screenTimeData, merge: true) { error in
            if let error = error {
                print("🔥 Error saving enhanced screen time data: \(error)")
                completion(.failure(error))
            } else {
                print("✅ Enhanced screen time data saved successfully")
                completion(.success(()))
            }
        }
    }
    
    func getAggregatedScreenTimeData(for deviceId: String, days: Int = 7, completion: @escaping (Result<ScreenTimeAggregation, Error>) -> Void) {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: endDate) ?? endDate
        
        FirebaseManager.shared.screenTimeCollection
            .whereField("deviceId", isEqualTo: deviceId)
            .whereField("date", isGreaterThanOrEqualTo: startDate)
            .whereField("date", isLessThanOrEqualTo: endDate)
            .order(by: "date", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("🔥 Error fetching aggregated screen time data: \(error)")
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.failure(FirebaseManager.FirebaseError.documentNotFound))
                    return
                }
                
                var totalScreenTime: TimeInterval = 0
                var appUsageTotals: [String: TimeInterval] = [:]
                var dailyAverages: [TimeInterval] = []
                var processedDays = 0
                
                for document in documents {
                    let data = document.data()
                    
                    if let screenTime = data["totalScreenTime"] as? TimeInterval {
                        totalScreenTime += screenTime
                        dailyAverages.append(screenTime)
                        processedDays += 1
                    }
                    
                    if let appUsagesData = data["appUsages"] as? [[String: Any]] {
                        for usageData in appUsagesData {
                            if let appName = usageData["appName"] as? String,
                               let duration = usageData["duration"] as? TimeInterval {
                                appUsageTotals[appName, default: 0] += duration
                            }
                        }
                    }
                }
                
                let averageDailyScreenTime = dailyAverages.isEmpty ? 0 : dailyAverages.reduce(0, +) / Double(dailyAverages.count)
                
                let topApps = appUsageTotals.sorted { $0.value > $1.value }.prefix(5).map { (appName, duration) in
                    AppUsage(
                        appName: appName,
                        bundleIdentifier: "",
                        duration: duration,
                        timestamp: Date(),
                        usageRanges: nil
                    )
                }
                
                let aggregation = ScreenTimeAggregation(
                    totalScreenTime: totalScreenTime,
                    averageDailyScreenTime: averageDailyScreenTime,
                    topApps: Array(topApps),
                    daysAnalyzed: processedDays
                )
                
                completion(.success(aggregation))
            }
    }
    
    func listenToRealtimeScreenTimeUpdates(for deviceId: String, completion: @escaping (ScreenTimeData?) -> Void) -> ListenerRegistration {
        let today = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateKey = dateFormatter.string(from: today)
        let documentId = "\(deviceId)_\(dateKey)"
        
        return FirebaseManager.shared.screenTimeCollection.document(documentId).addSnapshotListener { snapshot, error in
            if let error = error {
                print("🔥 Error listening to real-time screen time updates: \(error)")
                completion(nil)
                return
            }
            
            guard let data = snapshot?.data() else {
                completion(nil)
                return
            }
            
            // Convert data to ScreenTimeData object with enhanced parsing
            let appUsagesData = data["appUsages"] as? [[String: Any]] ?? []
            let appUsages = appUsagesData.compactMap { usageData -> AppUsage? in
                // Safely extract appName with type conversion
                let appName: String
                if let nameData = usageData["appName"] {
                    if let stringName = nameData as? String {
                        appName = stringName
                    } else if let numberName = nameData as? NSNumber {
                        appName = numberName.stringValue
                    } else {
                        appName = String(describing: nameData)
                    }
                } else {
                    appName = "Unknown App"
                }
                
                // Safely extract bundleIdentifier with type conversion
                let bundleId: String
                if let bundleData = usageData["bundleIdentifier"] {
                    if let stringBundle = bundleData as? String {
                        bundleId = stringBundle
                    } else if let numberBundle = bundleData as? NSNumber {
                        bundleId = numberBundle.stringValue
                    } else {
                        bundleId = String(describing: bundleData)
                    }
                } else {
                    bundleId = "unknown.bundle"
                }
                
                guard let duration = usageData["duration"] as? TimeInterval,
                      let timestamp = (usageData["timestamp"] as? Timestamp)?.dateValue() else {
                    return nil
                }
                
                // Parse usage ranges if available
                let usageRangesData = usageData["usageRanges"] as? [[String: Any]] ?? []
                let usageRanges = usageRangesData.compactMap { rangeData -> AppUsageRange? in
                    guard let startTime = (rangeData["startTime"] as? Timestamp)?.dateValue(),
                          let endTime = (rangeData["endTime"] as? Timestamp)?.dateValue(),
                          let duration = rangeData["duration"] as? TimeInterval,
                          let sessionId = rangeData["sessionId"] as? String else {
                        return nil
                    }
                    
                    return AppUsageRange(
                        startTime: startTime,
                        endTime: endTime,
                        duration: duration,
                        sessionId: sessionId
                    )
                }
                
                return AppUsage(
                    appName: appName,
                    bundleIdentifier: bundleId,
                    duration: duration,
                    timestamp: timestamp,
                    usageRanges: usageRanges.isEmpty ? nil : usageRanges
                )
            }
            
            let hourlyBreakdown = data["hourlyBreakdown"] as? [String: TimeInterval] ?? [:]
            let hourlyBreakdownInt = Dictionary(uniqueKeysWithValues: hourlyBreakdown.compactMap { key, value in
                Int(key).map { ($0, value) }
            })
            
            let screenTimeData = ScreenTimeData(
                deviceId: data["deviceId"] as? String ?? deviceId,
                date: (data["date"] as? Timestamp)?.dateValue() ?? today,
                totalScreenTime: data["totalScreenTime"] as? TimeInterval ?? 0,
                appUsages: appUsages,
                hourlyBreakdown: hourlyBreakdownInt
            )
            
            completion(screenTimeData)
        }
    }
    
    func saveAppUsageData(_ appUsage: AppUsage, for deviceId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let appUsageData: [String: Any] = [
            "deviceId": deviceId,
            "appName": appUsage.appName,
            "bundleIdentifier": appUsage.bundleIdentifier,
            "duration": appUsage.duration,
            "timestamp": Timestamp(date: appUsage.timestamp),
            "usageRanges": appUsage.usageRanges?.map { range in
                [
                    "startTime": Timestamp(date: range.startTime),
                    "endTime": Timestamp(date: range.endTime),
                    "duration": range.duration,
                    "sessionId": range.sessionId
                ]
            } ?? [],
            "createdAt": Timestamp()
        ]
        
        FirebaseManager.shared.appUsageCollection.addDocument(data: appUsageData) { error in
            if let error = error {
                print("🔥 Error saving app usage data: \(error)")
                completion(.failure(error))
            } else {
                print("✅ App usage data saved successfully")
                completion(.success(()))
            }
        }
    }
    
    func getAppUsageHistory(for deviceId: String, days: Int = 7, completion: @escaping (Result<[AppUsage], Error>) -> Void) {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        
        FirebaseManager.shared.appUsageCollection
            .whereField("deviceId", isEqualTo: deviceId)
            .whereField("timestamp", isGreaterThanOrEqualTo: startDate)
            .whereField("timestamp", isLessThanOrEqualTo: endDate)
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("🔥 Error fetching app usage history: \(error)")
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                let appUsages = documents.compactMap { document -> AppUsage? in
                    let data = document.data()
                    
                    guard let appName = data["appName"] as? String,
                          let bundleIdentifier = data["bundleIdentifier"] as? String,
                          let duration = data["duration"] as? TimeInterval,
                          let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                        return nil
                    }
                    
                    // Parse usage ranges if available
                    let usageRangesData = data["usageRanges"] as? [[String: Any]] ?? []
                    let usageRanges = usageRangesData.compactMap { rangeData -> AppUsageRange? in
                        guard let startTime = (rangeData["startTime"] as? Timestamp)?.dateValue(),
                              let endTime = (rangeData["endTime"] as? Timestamp)?.dateValue(),
                              let duration = rangeData["duration"] as? TimeInterval,
                              let sessionId = rangeData["sessionId"] as? String else {
                            return nil
                        }
                        
                        return AppUsageRange(
                            startTime: startTime,
                            endTime: endTime,
                            duration: duration,
                            sessionId: sessionId
                        )
                    }
                    
                    return AppUsage(
                        appName: appName,
                        bundleIdentifier: bundleIdentifier,
                        duration: duration,
                        timestamp: timestamp,
                        usageRanges: usageRanges.isEmpty ? nil : usageRanges
                    )
                }
                
                completion(.success(appUsages))
            }
    }
    
    // MARK: - Cross-Device Synchronization
    func syncScreenTimeDataAcrossDevices(parentId: String, completion: @escaping (Result<[String: ScreenTimeData], Error>) -> Void) {
        // First get all child devices for the parent
        getChildDevices(for: parentId) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let devices):
                let group = DispatchGroup()
                var allScreenTimeData: [String: ScreenTimeData] = [:]
                var syncError: Error?
                
                for device in devices {
                    guard let deviceId = device.id else { continue }
                    
                    group.enter()
                    self.getScreenTimeData(for: deviceId, date: Date()) { result in
                        defer { group.leave() }
                        
                        switch result {
                        case .success(let screenTimeData):
                            if let data = screenTimeData {
                                allScreenTimeData[deviceId] = data
                            }
                        case .failure(let error):
                            syncError = error
                        }
                    }
                }
                
                group.notify(queue: .main) {
                    if let error = syncError {
                        completion(.failure(error))
                    } else {
                        completion(.success(allScreenTimeData))
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Data Export Methods
    func exportScreenTimeDataToCSV(for deviceId: String, days: Int = 30, completion: @escaping (Result<Data, Error>) -> Void) {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        
        FirebaseManager.shared.screenTimeCollection
            .whereField("deviceId", isEqualTo: deviceId)
            .whereField("date", isGreaterThanOrEqualTo: startDate)
            .whereField("date", isLessThanOrEqualTo: endDate)
            .order(by: "date", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.failure(FirebaseManager.FirebaseError.documentNotFound))
                    return
                }
                
                var csvContent = "Date,Total Screen Time (minutes),Top App,Top App Duration (minutes),App Count\n"
                
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                
                for document in documents {
                    let data = document.data()
                    
                    let date = (data["date"] as? Timestamp)?.dateValue() ?? Date()
                    let totalScreenTime = data["totalScreenTime"] as? TimeInterval ?? 0
                    let totalMinutes = Int(totalScreenTime / 60)
                    
                    let appUsagesData = data["appUsages"] as? [[String: Any]] ?? []
                    let topApp = appUsagesData.first
                    let topAppName = topApp?["appName"] as? String ?? "N/A"
                    let topAppMinutes = Int((topApp?["duration"] as? TimeInterval ?? 0) / 60)
                    
                    csvContent += "\(formatter.string(from: date)),\(totalMinutes),\(topAppName),\(topAppMinutes),\(appUsagesData.count)\n"
                }
                
                if let csvData = csvContent.data(using: .utf8) {
                    completion(.success(csvData))
                } else {
                    completion(.failure(FirebaseManager.FirebaseError.encodingError))
                }
            }
    }
    
    func exportScreenTimeDataToJSON(for deviceId: String, days: Int = 30, completion: @escaping (Result<Data, Error>) -> Void) {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        
        FirebaseManager.shared.screenTimeCollection
            .whereField("deviceId", isEqualTo: deviceId)
            .whereField("date", isGreaterThanOrEqualTo: startDate)
            .whereField("date", isLessThanOrEqualTo: endDate)
            .order(by: "date", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.failure(FirebaseManager.FirebaseError.documentNotFound))
                    return
                }
                
                var exportData: [String: Any] = [:]
                
                for document in documents {
                    let data = document.data()
                    let date = (data["date"] as? Timestamp)?.dateValue() ?? Date()
                    let dateKey = ISO8601DateFormatter().string(from: date)
                    
                    exportData[dateKey] = data
                }
                
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
                    completion(.success(jsonData))
                } catch {
                    completion(.failure(error))
                }
            }
    }
}


