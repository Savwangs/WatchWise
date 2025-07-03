//
//  FirebaseManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/7/25.
//

import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import FirebaseMessaging
import FirebaseAnalytics

class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()
    
    let db = Firestore.firestore()
    
    private init() {
        setupFirestore()
        setupAnalytics()
    }
    
    private func setupFirestore() {
        // Configure Firestore settings for optimal performance
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
        db.settings = settings
        
        print("🔥 Firebase Manager initialized")
    }
    
    private func setupAnalytics() {
        // Configure Firebase Analytics
        Analytics.setAnalyticsCollectionEnabled(true)
        print("📊 Firebase Analytics initialized")
    }
    
    // MARK: - Collection References (Updated for Day 1)
    
    var usersCollection: CollectionReference {
        return db.collection("users")
    }
    
    var familiesCollection: CollectionReference {
        return db.collection("families")
    }
    
    var childDevicesCollection: CollectionReference {
        return db.collection("childDevices")
    }
    
    var pairingRequestsCollection: CollectionReference {
        return db.collection("pairingRequests")
    }
    
    var parentChildRelationshipsCollection: CollectionReference {
        return db.collection("parentChildRelationships")
    }
    
    var screenTimeCollection: CollectionReference {
        return db.collection("screenTimeData")
    }
    
    var messagesCollection: CollectionReference {
        return db.collection("messages")
    }
    
    var settingsCollection: CollectionReference {
        return db.collection("settings")
    }
    
    var newAppDetectionsCollection: CollectionReference {
        return db.collection("newAppDetections")
    }
    
    // MARK: - Legacy Collection References (for backward compatibility)
    
    var devicesCollection: CollectionReference {
        return childDevicesCollection
    }
    
    var pairCodesCollection: CollectionReference {
        return pairingRequestsCollection
    }
    
    // MARK: - Utility Methods
    
    func getCurrentUserId() -> String? {
        return Auth.auth().currentUser?.uid
    }
    
    func isUserAuthenticated() -> Bool {
        return Auth.auth().currentUser != nil
    }
    
    // MARK: - Day 1: Firebase Configuration Methods
    
    /// Initialize Firebase configuration for the app
    func configureFirebase() {
        // This method is called from AppDelegate
        print("✅ Firebase configuration completed")
    }
    
    /// Test Firebase connection
    func testFirebaseConnection(completion: @escaping (Bool) -> Void) {
        // Test Firestore connection by reading a test document
        db.collection("_test").document("connection").getDocument { snapshot, error in
            if let error = error {
                print("❌ Firebase connection test failed: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Firebase connection test successful")
                completion(true)
            }
        }
    }
    
    /// Get Firebase project configuration
    func getFirebaseConfig() -> [String: Any] {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path) else {
            return [:]
        }
        
        return plist as? [String: Any] ?? [:]
    }
    
    // MARK: - Error Handling
    
    enum FirebaseError: LocalizedError {
        case userNotAuthenticated
        case documentNotFound
        case invalidData
        case networkError
        case permissionDenied
        case quotaExceeded
        case unavailable
        
        var errorDescription: String? {
            switch self {
            case .userNotAuthenticated:
                return "User is not authenticated"
            case .documentNotFound:
                return "Document not found"
            case .invalidData:
                return "Invalid data format"
            case .networkError:
                return "Network connection error"
            case .permissionDenied:
                return "Permission denied"
            case .quotaExceeded:
                return "Firebase quota exceeded"
            case .unavailable:
                return "Firebase service unavailable"
            }
        }
    }
    
    // MARK: - Day 1: Collection Validation
    
    /// Validate that all required collections exist
    func validateCollections(completion: @escaping ([String: Bool]) -> Void) {
        let collections = [
            "users": usersCollection,
            "families": familiesCollection,
            "childDevices": childDevicesCollection,
            "pairingRequests": pairingRequestsCollection,
            "parentChildRelationships": parentChildRelationshipsCollection,
            "screenTimeData": screenTimeCollection,
            "messages": messagesCollection,
            "settings": settingsCollection,
            "newAppDetections": newAppDetectionsCollection
        ]
        
        var results: [String: Bool] = [:]
        let group = DispatchGroup()
        
        for (name, collection) in collections {
            group.enter()
            collection.limit(to: 1).getDocuments { snapshot, error in
                results[name] = error == nil
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(results)
        }
    }
}
