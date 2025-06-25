//
//  PairingManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/7/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class PairingManager: ObservableObject {
    static let shared = PairingManager()
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var isPaired = false
    @Published var currentDeviceId: String?
    
    private let db = Firestore.firestore()
    private let codeExpirationTime: TimeInterval = 600 // 10 minutes
    
    // MARK: - Child Device Code Generation
    
    /// Generates a 6-digit pairing code for child device
    func generatePairingCode(childName: String, deviceName: String) async -> Result<String, PairingError> {
        guard let currentUser = Auth.auth().currentUser else {
            return .failure(.notAuthenticated)
        }
        
        // Add authentication check
        if currentUser.uid.isEmpty {
            return .failure(.notAuthenticated)
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Generate unique 6-digit code
            let pairCode = generateUniqueCode()
            let expirationDate = Date().addingTimeInterval(codeExpirationTime)
            
            // Create pairing request document
            let pairingData: [String: Any] = [
                "pairCode": pairCode,
                "childUserId": currentUser.uid,
                "childName": childName,
                "deviceName": deviceName,
                "createdAt": Timestamp(),
                "expiresAt": Timestamp(date: expirationDate),
                "isActive": false,
                "isExpired": false
            ]
            
            // Store in Firestore with explicit error handling
            let docRef = try await db.collection("pairingRequests").addDocument(data: pairingData)
            
            print("✅ Pairing code generated successfully: \(pairCode)")
            
            // Schedule cleanup for expired code
            scheduleCodeCleanup(documentId: docRef.documentID, expirationDate: expirationDate)
            
            isLoading = false
            return .success(pairCode)
            
        } catch let error as NSError {
            isLoading = false
            print("🔥 Firebase Error: \(error.localizedDescription)")
            print("🔥 Error Code: \(error.code)")
            print("🔥 Error Domain: \(error.domain)")
            
            let pairingError = PairingError.databaseError(error.localizedDescription)
            errorMessage = pairingError.localizedDescription
            return .failure(pairingError)
        }
    }
    
    // MARK: - Parent Device Pairing
    
    /// Validates pairing code and creates parent-child relationship
    func pairWithChild(code: String, parentUserId: String) async -> Result<PairingSuccess, PairingError> {
        guard !code.isEmpty && code.count == 6 else {
            return .failure(.invalidCode)
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Query for active pairing request with matching code
            let snapshot = try await db.collection("pairingRequests")
                .whereField("pairCode", isEqualTo: code)
                .whereField("isActive", isEqualTo: false)
                .whereField("isExpired", isEqualTo: false)
                .getDocuments()
            
            guard let document = snapshot.documents.first else {
                isLoading = false
                let error = PairingError.codeNotFound
                errorMessage = error.localizedDescription
                return .failure(error)
            }
            
            let data = document.data()
            
            // Check if code has expired
            if let expiresAt = data["expiresAt"] as? Timestamp,
               expiresAt.dateValue() < Date() {
                isLoading = false
                let error = PairingError.codeExpired
                errorMessage = error.localizedDescription
                return .failure(error)
            }
            
            guard let childUserId = data["childUserId"] as? String,
                  let childName = data["childName"] as? String,
                  let deviceName = data["deviceName"] as? String else {
                isLoading = false
                let error = PairingError.invalidData
                errorMessage = error.localizedDescription
                return .failure(error)
            }
            
            // Create parent-child relationship
            let relationshipId = try await createParentChildRelationship(
                parentUserId: parentUserId,
                childUserId: childUserId,
                childName: childName,
                deviceName: deviceName,
                pairingCode: code
            )
            
            // Mark pairing request as active
            try await document.reference.updateData([
                "isActive": true,
                "parentUserId": parentUserId,
                "pairedAt": Timestamp()
            ])
            
            isLoading = false
            successMessage = "Successfully paired with \(childName)'s device!"
            
            // DEMO DATA - START (Set pairing completion flag for child device)
            UserDefaults.standard.set(true, forKey: "demoChildPaired_\(code)")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "demoPairingTimestamp_\(code)")
            // DEMO DATA - END
            
            return .success(PairingSuccess(
                relationshipId: relationshipId,
                childUserId: childUserId,
                childName: childName,
                deviceName: deviceName
            ))
            
        } catch {
            isLoading = false
            let pairingError = PairingError.databaseError(error.localizedDescription)
            errorMessage = pairingError.localizedDescription
            return .failure(pairingError)
        }
    }
    
    // MARK: - Relationship Management
    
    /// Creates a parent-child relationship document in Firestore
    private func createParentChildRelationship(
        parentUserId: String,
        childUserId: String,
        childName: String,
        deviceName: String,
        pairingCode: String
    ) async throws -> String {
        
        let relationshipData: [String: Any] = [
            "parentUserId": parentUserId,
            "childUserId": childUserId,
            "childName": childName,
            "deviceName": deviceName,
            "pairingCode": pairingCode,
            "createdAt": Timestamp(),
            "isActive": true,
            "lastSyncAt": Timestamp()
        ]
        
        let docRef = try await db.collection("parentChildRelationships").addDocument(data: relationshipData)
        return docRef.documentID
    }
    
    /// Gets all children for a parent
    func getChildrenForParent(parentUserId: String) async -> Result<[ChildDevice], PairingError> {
        do {
            let snapshot = try await db.collection("parentChildRelationships")
                .whereField("parentUserId", isEqualTo: parentUserId)
                .whereField("isActive", isEqualTo: true)
                .getDocuments()
            
            let children = snapshot.documents.compactMap { doc -> ChildDevice? in
                let data = doc.data()
                guard let childUserId = data["childUserId"] as? String,
                      let childName = data["childName"] as? String,
                      let deviceName = data["deviceName"] as? String else {
                    return nil
                }
                
                return ChildDevice(
                    childName: childName,
                    deviceName: deviceName,
                    pairCode: data["pairingCode"] as? String ?? "",
                    parentId: parentUserId,
                    pairedAt: data["createdAt"] as? Timestamp ?? Timestamp(),
                    isActive: data["isActive"] as? Bool ?? true
                )
            }
            
            return .success(children)
        } catch {
            return .failure(.databaseError(error.localizedDescription))
        }
    }
    
    /// Unpairs a child device
    func unpairChild(relationshipId: String) async -> Result<Void, PairingError> {
        do {
            try await db.collection("parentChildRelationships")
                .document(relationshipId)
                .updateData([
                    "isActive": false,
                    "unpairedAt": Timestamp()
                ])
            
            return .success(())
        } catch {
            return .failure(.databaseError(error.localizedDescription))
        }
    }
    
    // MARK: - Code Management
    
    /// Generates a unique 6-digit numerical code
    private func generateUniqueCode() -> String {
        let digits = "0123456789"
        return String((0..<6).map { _ in digits.randomElement()! })
    }
    
    /// Schedules cleanup of expired pairing codes
    private func scheduleCodeCleanup(documentId: String, expirationDate: Date) {
        Task {
            let timeInterval = expirationDate.timeIntervalSinceNow
            if timeInterval > 0 {
                try await Task.sleep(nanoseconds: UInt64(timeInterval * 1_000_000_000))
                await markCodeAsExpired(documentId: documentId)
            }
        }
    }
    
    /// Marks a pairing code as expired
    private func markCodeAsExpired(documentId: String) async {
        do {
            try await db.collection("pairingRequests")
                .document(documentId)
                .updateData(["isExpired": true])
        } catch {
            print("Error marking code as expired: \(error)")
        }
    }
    
    /// Validates if a relationship exists between parent and child
    func validateParentChildRelationship(parentUserId: String, childUserId: String) async -> Bool {
        do {
            let snapshot = try await db.collection("parentChildRelationships")
                .whereField("parentUserId", isEqualTo: parentUserId)
                .whereField("childUserId", isEqualTo: childUserId)
                .whereField("isActive", isEqualTo: true)
                .getDocuments()
            
            return !snapshot.documents.isEmpty
        } catch {
            print("Error validating relationship: \(error)")
            return false
        }
    }
    
    // MARK: - Cleanup Methods
    
    /// Cleans up expired pairing requests (call periodically)
    func cleanupExpiredCodes() async {
        do {
            let snapshot = try await db.collection("pairingRequests")
                .whereField("expiresAt", isLessThan: Timestamp())
                .whereField("isExpired", isEqualTo: false)
                .getDocuments()
            
            for document in snapshot.documents {
                try await document.reference.updateData(["isExpired": true])
            }
        } catch {
            print("Error cleaning up expired codes: \(error)")
        }
    }
}

// MARK: - Data Models

struct PairingSuccess {
    let relationshipId: String
    let childUserId: String
    let childName: String
    let deviceName: String
}

// MARK: - Error Handling

enum PairingError: LocalizedError {
    case notAuthenticated
    case invalidCode
    case codeNotFound
    case codeExpired
    case invalidData
    case databaseError(String)
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to pair devices."
        case .invalidCode:
            return "Please enter a valid 6-digit pairing code."
        case .codeNotFound:
            return "Invalid pairing code. Please check the code and try again."
        case .codeExpired:
            return "This pairing code has expired. Please generate a new code."
        case .invalidData:
            return "Invalid pairing data. Please try generating a new code."
        case .databaseError(let message):
            return "Database error: \(message)"
        case .networkError:
            return "Network error. Please check your connection and try again."
        }
    }
}
