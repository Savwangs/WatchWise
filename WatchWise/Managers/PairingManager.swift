//
//  PairingManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/7/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreImage.CIFilterBuiltins

@MainActor
class PairingManager: ObservableObject {
    static let shared = PairingManager()
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var isPaired = false
    @Published var currentDeviceId: String?
    @Published var pairedChildren: [PairedChildDevice] = []
    
    private let firebaseManager = FirebaseManager.shared
    private let codeExpirationTime: TimeInterval = 600 // 10 minutes
    
    // MARK: - Day 3: Enhanced Child Device Code Generation
    
    /// Generates a 6-digit pairing code for child device with QR code
    func generatePairingCode(childName: String, deviceName: String) async -> Result<PairingCodeData, PairingError> {
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
                "isExpired": false,
                "deviceInfo": getDeviceInfo()
            ]
            
            // Store in Firestore using FirebaseManager
            let docRef = try await firebaseManager.pairingRequestsCollection.addDocument(data: pairingData)
            
            print("✅ Pairing code generated successfully: \(pairCode)")
            
            // Generate QR code
            let qrCodeImage = generateQRCode(from: pairCode)
            
            // Schedule cleanup for expired code
            scheduleCodeCleanup(documentId: docRef.documentID, expirationDate: expirationDate)
            
            isLoading = false
            
            let pairingCodeData = PairingCodeData(
                code: pairCode,
                qrCodeImage: qrCodeImage,
                expiresAt: expirationDate,
                documentId: docRef.documentID
            )
            
            return .success(pairingCodeData)
            
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
    
    // MARK: - Day 3: QR Code Generation
    
    /// Generates QR code from pairing code
    private func generateQRCode(from code: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        filter.message = Data(code.utf8)
        filter.correctionLevel = "M"
        
        if let outputImage = filter.outputImage {
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        
        return nil
    }
    
    // MARK: - Day 3: Enhanced Parent Device Pairing
    
    /// Validates pairing code and creates parent-child relationship
    func pairWithChild(code: String, parentUserId: String) async -> Result<PairingSuccess, PairingError> {
        guard !code.isEmpty && code.count == 6 else {
            return .failure(.invalidCode)
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Query for active pairing request with matching code
            let snapshot = try await firebaseManager.pairingRequestsCollection
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
            
            // Check if relationship already exists
            let relationshipExists = await validateParentChildRelationship(parentUserId: parentUserId, childUserId: childUserId)
            if relationshipExists {
                isLoading = false
                let error = PairingError.alreadyPaired
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
            
            // Update child's device pairing status
            try await firebaseManager.usersCollection.document(childUserId).updateData([
                "isDevicePaired": true,
                "pairedWithParent": parentUserId,
                "pairedAt": Timestamp()
            ])
            
            isLoading = false
            successMessage = "Successfully paired with \(childName)'s device!"
            
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
    
    // MARK: - Day 3: Enhanced Relationship Management
    
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
            "lastSyncAt": Timestamp(),
            "deviceInfo": getDeviceInfo()
        ]
        
        let docRef = try await firebaseManager.parentChildRelationshipsCollection.addDocument(data: relationshipData)
        return docRef.documentID
    }
    
    /// Gets all children for a parent
    func getChildrenForParent(parentUserId: String) async -> Result<[PairedChildDevice], PairingError> {
        do {
            let snapshot = try await firebaseManager.parentChildRelationshipsCollection
                .whereField("parentUserId", isEqualTo: parentUserId)
                .whereField("isActive", isEqualTo: true)
                .getDocuments()
            
            let children = snapshot.documents.compactMap { doc -> PairedChildDevice? in
                let data = doc.data()
                guard let childUserId = data["childUserId"] as? String,
                      let childName = data["childName"] as? String,
                      let deviceName = data["deviceName"] as? String else {
                    return nil
                }
                
                return PairedChildDevice(
                    id: doc.documentID,
                    childUserId: childUserId,
                    childName: childName,
                    deviceName: deviceName,
                    pairCode: data["pairingCode"] as? String ?? "",
                    parentId: parentUserId,
                    pairedAt: data["createdAt"] as? Timestamp ?? Timestamp(),
                    isActive: data["isActive"] as? Bool ?? true,
                    lastSyncAt: data["lastSyncAt"] as? Timestamp ?? Timestamp()
                )
            }
            
            await MainActor.run {
                self.pairedChildren = children
            }
            
            return .success(children)
        } catch {
            return .failure(.databaseError(error.localizedDescription))
        }
    }
    
    /// Unpairs a child device
    func unpairChild(relationshipId: String) async -> Result<Void, PairingError> {
        do {
            // Get the relationship document to find child user ID
            let docSnapshot = try await firebaseManager.parentChildRelationshipsCollection
                .document(relationshipId)
                .getDocument()
            
            guard let data = docSnapshot.data(),
                  let childUserId = data["childUserId"] as? String else {
                return .failure(.invalidData)
            }
            
            // Update relationship status
            try await firebaseManager.parentChildRelationshipsCollection
                .document(relationshipId)
                .updateData([
                    "isActive": false,
                    "unpairedAt": Timestamp()
                ])
            
            // Update child's device pairing status
            try await firebaseManager.usersCollection.document(childUserId).updateData([
                "isDevicePaired": false,
                "pairedWithParent": FieldValue.delete(),
                "unpairedAt": Timestamp()
            ])
            
            // Refresh paired children list
            if let parentUserId = Auth.auth().currentUser?.uid {
                _ = await getChildrenForParent(parentUserId: parentUserId)
            }
            
            return .success(())
        } catch {
            return .failure(.databaseError(error.localizedDescription))
        }
    }
    
    // MARK: - Day 3: Device Information
    
    /// Gets current device information
    private func getDeviceInfo() -> [String: Any] {
        let device = UIDevice.current
        return [
            "name": device.name,
            "model": device.model,
            "systemName": device.systemName,
            "systemVersion": device.systemVersion,
            "identifierForVendor": device.identifierForVendor?.uuidString ?? "",
            "timestamp": Timestamp()
        ]
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
            try await firebaseManager.pairingRequestsCollection
                .document(documentId)
                .updateData(["isExpired": true])
        } catch {
            print("Error marking code as expired: \(error)")
        }
    }
    
    /// Validates if a relationship exists between parent and child
    func validateParentChildRelationship(parentUserId: String, childUserId: String) async -> Bool {
        do {
            let snapshot = try await firebaseManager.parentChildRelationshipsCollection
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
    
    // MARK: - Day 3: Enhanced Cleanup Methods
    
    /// Cleans up expired pairing requests (call periodically)
    func cleanupExpiredCodes() async {
        do {
            let snapshot = try await firebaseManager.pairingRequestsCollection
                .whereField("expiresAt", isLessThan: Timestamp())
                .whereField("isExpired", isEqualTo: false)
                .getDocuments()
            
            for document in snapshot.documents {
                try await document.reference.updateData(["isExpired": true])
            }
            
            print("✅ Cleaned up \(snapshot.documents.count) expired pairing codes")
        } catch {
            print("Error cleaning up expired codes: \(error)")
        }
    }
    
    /// Loads paired children for current user
    func loadPairedChildren() async {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        let result = await getChildrenForParent(parentUserId: currentUser.uid)
        switch result {
        case .success(let children):
            await MainActor.run {
                self.pairedChildren = children
                self.isPaired = !children.isEmpty
            }
        case .failure(let error):
            print("Error loading paired children: \(error)")
        }
    }
}

// MARK: - Day 3: Enhanced Data Models

struct PairingCodeData {
    let code: String
    let qrCodeImage: UIImage?
    let expiresAt: Date
    let documentId: String
}

struct PairingSuccess {
    let relationshipId: String
    let childUserId: String
    let childName: String
    let deviceName: String
}

struct PairedChildDevice: Identifiable {
    let id: String
    let childUserId: String
    let childName: String
    let deviceName: String
    let pairCode: String
    let parentId: String
    let pairedAt: Timestamp
    let isActive: Bool
    let lastSyncAt: Timestamp
    
    var isOnline: Bool {
        // Simple online check based on last sync time (within 5 minutes)
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        return lastSyncAt.dateValue() > fiveMinutesAgo
    }
}

// MARK: - Day 3: Enhanced Error Handling

enum PairingError: LocalizedError {
    case notAuthenticated
    case invalidCode
    case codeNotFound
    case codeExpired
    case invalidData
    case alreadyPaired
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
        case .alreadyPaired:
            return "This device is already paired with your account."
        case .databaseError(let message):
            return "Database error: \(message)"
        case .networkError:
            return "Network error. Please check your connection and try again."
        }
    }
}
