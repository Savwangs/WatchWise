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
        let screenTimeData: [String: Any] = [
            "deviceId": data.deviceId,
            "date": Timestamp(date: data.date),
            "totalScreenTime": data.totalScreenTime,
            "appUsages": data.appUsages.map { usage in
                [
                    "appName": usage.appName,
                    "bundleIdentifier": usage.bundleIdentifier,
                    "duration": usage.duration,
                    "timestamp": Timestamp(date: usage.timestamp)
                ]
            },
            "hourlyBreakdown": data.hourlyBreakdown.mapValues { $0 }
        ]
        
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
                guard let appName = usageData["appName"] as? String,
                      let bundleId = usageData["bundleIdentifier"] as? String,
                      let duration = usageData["duration"] as? TimeInterval,
                      let timestamp = (usageData["timestamp"] as? Timestamp)?.dateValue() else {
                    return nil
                }
                
                return AppUsage(
                    appName: appName,
                    bundleIdentifier: bundleId,
                    duration: duration,
                    timestamp: timestamp
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
                guard let appName = usageData["appName"] as? String,
                      let bundleId = usageData["bundleIdentifier"] as? String,
                      let duration = usageData["duration"] as? TimeInterval,
                      let timestamp = (usageData["timestamp"] as? Timestamp)?.dateValue() else {
                    return nil
                }
                
                return AppUsage(
                    appName: appName,
                    bundleIdentifier: bundleId,
                    duration: duration,
                    timestamp: timestamp
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
        
        FirebaseManager.shared.devicesCollection.document(deviceId).updateData(updateData) { error in
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
        // DEMO DATA - START (Remove in production)
        // For demo purposes, always return true for existing child accounts
        // In production, this would check Firebase for actual pairing data
        completion(.success(true))
        // DEMO DATA - END (Remove in production)
        
        /* PRODUCTION CODE - Uncomment when ready for production
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
        */
    }
    
    // MARK: - New App Detection
    
    func saveNewAppDetection(_ detection: NewAppDetection, completion: @escaping (Result<Void, Error>) -> Void) {
        let detectionData: [String: Any] = [
            "appName": detection.appName,
            "bundleIdentifier": detection.bundleIdentifier,
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
}


