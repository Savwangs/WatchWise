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

class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()
    
    let db = Firestore.firestore()
    
    private init() {
        setupFirestore()
    }
    
    private func setupFirestore() {
        // Configure Firestore settings for optimal performance
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
        db.settings = settings
        
        print("🔥 Firebase Manager initialized")
    }
    
    // MARK: - Collection References
    
    var usersCollection: CollectionReference {
        return db.collection("users")
    }
    
    var familiesCollection: CollectionReference {
        return db.collection("families")
    }
    
    var devicesCollection: CollectionReference {
        return db.collection("devices")
    }
    
    var screenTimeCollection: CollectionReference {
        return db.collection("screenTimeData")
    }
    
    var messagesCollection: CollectionReference {
        return db.collection("messages")
    }
    
    var pairCodesCollection: CollectionReference {
        return db.collection("pairCodes")
    }
    
    // MARK: - Utility Methods
    
    func getCurrentUserId() -> String? {
        return Auth.auth().currentUser?.uid
    }
    
    func isUserAuthenticated() -> Bool {
        return Auth.auth().currentUser != nil
    }
    
    // MARK: - Error Handling
    
    enum FirebaseError: LocalizedError {
        case userNotAuthenticated
        case documentNotFound
        case invalidData
        case networkError
        
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
            }
        }
    }
}
