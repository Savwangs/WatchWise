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
    private var activePairingRequestId: String?
    private var cleanupTimer: Timer?
    
    // MARK: - Day 3: Enhanced Child Device Code Generation
    
    /// Generates a new pairing code for child device
    func generatePairingCode(childUserId: String, childName: String, deviceName: String) async -> Result<String, PairingError> {
        print("🔄 Starting pairing code generation...")
        print("🔄 Child User ID: \(childUserId)")
        print("🔄 Child Name: \(childName)")
        print("🔄 Device Name: \(deviceName)")
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Generate a random 6-digit code
            let code = String(format: "%06d", Int.random(in: 100000...999999))
            print("✅ Generated code: \(code)")
            
            // Set expiration time (10 minutes from now)
            let expiresAt = Timestamp(date: Date().addingTimeInterval(10 * 60))
            print("⏰ Code expires at: \(expiresAt.dateValue())")
            
            // Create pairing request document
            let pairingRequest = [
                "childUserId": childUserId,
                "childName": childName,
                "deviceName": deviceName,
                "pairCode": code,
                "isActive": false,
                "isExpired": false,
                "expiresAt": expiresAt,
                "createdAt": Timestamp()
            ] as [String : Any]
            
            print("📄 Creating pairing request document...")
            print("📄 Document data: \(pairingRequest)")
            
            let documentRef = try await firebaseManager.pairingRequestsCollection.addDocument(data: pairingRequest)
            print("✅ Pairing request created with ID: \(documentRef.documentID)")
            
            // Store the document ID for cleanup
            activePairingRequestId = documentRef.documentID
            print("💾 Stored active pairing request ID: \(activePairingRequestId ?? "nil")")
            
            // Start cleanup timer
            startCleanupTimer()
            print("⏰ Started cleanup timer")
            
            isLoading = false
            successMessage = "Pairing code generated successfully!"
            
            return .success(code)
            
        } catch {
            print("🔥 Error during code generation: \(error)")
            print("🔥 Error type: \(type(of: error))")
            if let nsError = error as NSError? {
                print("🔥 Error code: \(nsError.code)")
                print("🔥 Error domain: \(nsError.domain)")
                print("🔥 Error description: \(nsError.localizedDescription)")
            }
            
            isLoading = false
            let pairingError = PairingError.databaseError(error.localizedDescription)
            errorMessage = pairingError.localizedDescription
            return .failure(pairingError)
        }
    }
    
    // MARK: - Day 3: QR Code Generation
    
    /// Generates QR code from pairing code
    func generateQRCode(from code: String) -> UIImage? {
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
        
        print("🔄 Starting device pairing with code: \(code)")
        print("🔄 Parent User ID: \(parentUserId)")
        
        isLoading = true
        errorMessage = nil
        
        do {
            print("🔍 Querying for pairing request...")
            print("🔍 Current authenticated user: \(Auth.auth().currentUser?.uid ?? "nil")")
            print("🔍 Query conditions: pairCode=\(code), isActive=false, isExpired=false")
            
            // Query for active pairing request with matching code
            let snapshot = try await firebaseManager.pairingRequestsCollection
                .whereField("pairCode", isEqualTo: code)
                .whereField("isActive", isEqualTo: false)
                .whereField("isExpired", isEqualTo: false)
                .getDocuments()
            
            print("✅ Query completed, found \(snapshot.documents.count) documents")
            
            guard let document = snapshot.documents.first else {
                print("❌ No matching pairing request found")
                print("❌ This could mean:")
                print("   - Code doesn't exist")
                print("   - Code is already active (already paired)")
                print("   - Code has expired")
                print("   - Permission issue accessing the document")
                isLoading = false
                let error = PairingError.codeNotFound
                errorMessage = error.localizedDescription
                return .failure(error)
            }
            
            print("✅ Found pairing request document: \(document.documentID)")
            let data = document.data()
            print("📄 Document data: \(data)")
            
            // Check if code has expired
            if let expiresAt = data["expiresAt"] as? Timestamp,
               expiresAt.dateValue() < Date() {
                print("❌ Pairing code has expired")
                print("❌ Expires at: \(expiresAt.dateValue())")
                print("❌ Current time: \(Date())")
                isLoading = false
                let error = PairingError.codeExpired
                errorMessage = error.localizedDescription
                return .failure(error)
            }
            
            guard let childUserId = data["childUserId"] as? String,
                  let childName = data["childName"] as? String,
                  let deviceName = data["deviceName"] as? String else {
                print("❌ Invalid document data structure")
                print("❌ Available fields: \(data.keys)")
                isLoading = false
                let error = PairingError.invalidData
                errorMessage = error.localizedDescription
                return .failure(error)
            }
            
            print("✅ Extracted data - Child: \(childName), Device: \(deviceName), ChildUserID: \(childUserId)")
            
            // Check if relationship already exists
            print("🔍 Checking for existing relationship...")
            let relationshipExists = await validateParentChildRelationship(parentUserId: parentUserId, childUserId: childUserId)
            if relationshipExists {
                print("❌ Relationship already exists")
                isLoading = false
                let error = PairingError.alreadyPaired
                errorMessage = error.localizedDescription
                return .failure(error)
            }
            
            print("✅ No existing relationship found, creating new one...")
            
            // Create parent-child relationship
            let relationshipId = try await createParentChildRelationship(
                parentUserId: parentUserId,
                childUserId: childUserId,
                childName: childName,
                deviceName: deviceName,
                pairingCode: code
            )
            
            print("✅ Parent-child relationship created: \(relationshipId)")
            
            // Mark pairing request as active
            print("🔍 Updating pairing request status...")
            try await document.reference.updateData([
                "isActive": true,
                "parentUserId": parentUserId,
                "pairedAt": Timestamp()
            ])
            
            print("✅ Pairing request marked as active")
            
            // Update child's device pairing status
            print("🔍 Updating child's device pairing status...")
            try await firebaseManager.usersCollection.document(childUserId).updateData([
                "isDevicePaired": true,
                "pairedWithParent": parentUserId,
                "pairedAt": Timestamp()
            ])
            
            print("✅ Child's device pairing status updated")
            
            isLoading = false
            successMessage = "Successfully paired with \(childName)'s device!"
            
            return .success(PairingSuccess(
                relationshipId: relationshipId,
                childUserId: childUserId,
                childName: childName,
                deviceName: deviceName
            ))
            
        } catch {
            print("🔥 Error during pairing process: \(error)")
            print("🔥 Error type: \(type(of: error))")
            if let nsError = error as NSError? {
                print("🔥 Error code: \(nsError.code)")
                print("🔥 Error domain: \(nsError.domain)")
                print("🔥 Error description: \(nsError.localizedDescription)")
                print("🔥 Error user info: \(nsError.userInfo)")
            }
            
            // Check if it's a permission error
            if let nsError = error as NSError?, nsError.domain == "FIRFirestoreErrorDomain" {
                switch nsError.code {
                case 7: // Permission denied
                    print("🔥 PERMISSION DENIED: User doesn't have permission to access this document")
                    print("🔥 This usually means the Firebase security rules are blocking access")
                    break
                case 5: // Not found
                    print("🔥 NOT FOUND: The document or collection doesn't exist")
                    break
                default:
                    print("🔥 Other Firestore error: \(nsError.code)")
                }
            }
            
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
                    lastSyncAt: data["lastSyncAt"] as? Timestamp ?? Timestamp(date: Date().addingTimeInterval(-300)) // 5 minutes ago as default
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
    
    /// Test Firebase permissions and connection
    func testFirebasePermissions() async {
        print("🧪 Testing Firebase permissions...")
        
        guard let currentUser = Auth.auth().currentUser else {
            print("❌ No authenticated user")
            return
        }
        
        print("✅ Authenticated user: \(currentUser.uid)")
        
        do {
            // Test 1: Try to read from pairingRequests collection
            print("🧪 Test 1: Reading from pairingRequests collection...")
            let snapshot = try await firebaseManager.pairingRequestsCollection.limit(to: 1).getDocuments()
            print("✅ Successfully read from pairingRequests collection")
            
            // Test 2: Try to create a test document
            print("🧪 Test 2: Creating test document...")
            let testDoc = try await firebaseManager.pairingRequestsCollection.addDocument(data: [
                "test": true,
                "timestamp": Timestamp(),
                "userId": currentUser.uid
            ])
            print("✅ Successfully created test document: \(testDoc.documentID)")
            
            // Test 3: Try to read the test document
            print("🧪 Test 3: Reading test document...")
            let testSnapshot = try await testDoc.getDocument()
            print("✅ Successfully read test document")
            
            // Test 4: Try to update the test document
            print("🧪 Test 4: Updating test document...")
            try await testDoc.updateData([
                "updated": true,
                "updateTime": Timestamp()
            ])
            print("✅ Successfully updated test document")
            
            // Test 5: Try to delete the test document
            print("🧪 Test 5: Deleting test document...")
            try await testDoc.delete()
            print("✅ Successfully deleted test document")
            
            print("🎉 All Firebase permission tests passed!")
            
        } catch {
            print("❌ Firebase permission test failed: \(error)")
            if let nsError = error as NSError? {
                print("❌ Error code: \(nsError.code)")
                print("❌ Error domain: \(nsError.domain)")
                print("❌ Error description: \(nsError.localizedDescription)")
            }
        }
    }
    
    /// Test specific pairing scenario
    func testPairingScenario() async {
        print("🧪 Testing specific pairing scenario...")
        
        guard let currentUser = Auth.auth().currentUser else {
            print("❌ No authenticated user")
            return
        }
        
        print("✅ Authenticated user: \(currentUser.uid)")
        
        do {
            // Create a test pairing request (simulating child device)
            print("🧪 Creating test pairing request...")
            let testPairingRequest = [
                "childUserId": "test-child-user-id",
                "childName": "Test Child",
                "deviceName": "Test Device",
                "pairCode": "123456",
                "isActive": false,
                "isExpired": false,
                "expiresAt": Timestamp(date: Date().addingTimeInterval(600)), // 10 minutes from now
                "createdAt": Timestamp()
            ] as [String : Any]
            
            let testDoc = try await firebaseManager.pairingRequestsCollection.addDocument(data: testPairingRequest)
            print("✅ Created test pairing request: \(testDoc.documentID)")
            
            // Try to read the test pairing request (simulating parent device)
            print("🧪 Reading test pairing request...")
            let snapshot = try await firebaseManager.pairingRequestsCollection
                .whereField("pairCode", isEqualTo: "123456")
                .whereField("isActive", isEqualTo: false)
                .whereField("isExpired", isEqualTo: false)
                .getDocuments()
            
            print("✅ Found \(snapshot.documents.count) matching documents")
            
            if let document = snapshot.documents.first {
                print("✅ Successfully read pairing request")
                
                // Try to update the pairing request (this is where the error occurs)
                print("🧪 Updating pairing request...")
                try await document.reference.updateData([
                    "isActive": true,
                    "parentUserId": currentUser.uid,
                    "pairedAt": Timestamp()
                ])
                print("✅ Successfully updated pairing request")
                
                // Clean up
                try await document.reference.delete()
                print("✅ Cleaned up test document")
            }
            
            print("🎉 Pairing scenario test passed!")
            
        } catch {
            print("❌ Pairing scenario test failed: \(error)")
            if let nsError = error as NSError? {
                print("❌ Error code: \(nsError.code)")
                print("❌ Error domain: \(nsError.domain)")
                print("❌ Error description: \(nsError.localizedDescription)")
            }
        }
    }
    
    /// Test the exact same update operation that's failing
    func testExactPairingUpdate() async {
        print("🧪 Testing exact pairing update operation...")
        
        guard let currentUser = Auth.auth().currentUser else {
            print("❌ No authenticated user")
            return
        }
        
        print("✅ Authenticated user: \(currentUser.uid)")
        
        do {
            // Try to update the specific document that's failing
            print("🧪 Attempting to update the existing pairing request...")
            
            // First, let's find the document that was created
            let snapshot = try await firebaseManager.pairingRequestsCollection
                .whereField("pairCode", isEqualTo: "948127") // Use the actual code from your test
                .getDocuments()
            
            if let document = snapshot.documents.first {
                print("✅ Found document: \(document.documentID)")
                print("📄 Current data: \(document.data())")
                
                // Try the exact same update operation
                try await document.reference.updateData([
                    "isActive": true,
                    "parentUserId": currentUser.uid,
                    "pairedAt": Timestamp()
                ])
                print("✅ SUCCESS: Update operation worked!")
                
            } else {
                print("❌ Document not found")
            }
            
        } catch {
            print("❌ Update test failed: \(error)")
            if let nsError = error as NSError? {
                print("❌ Error code: \(nsError.code)")
                print("❌ Error domain: \(nsError.domain)")
                print("❌ Error description: \(nsError.localizedDescription)")
            }
        }
    }
    
    /// Starts cleanup timer for active pairing request
    private func startCleanupTimer() {
        // Cancel existing timer if any
        cleanupTimer?.invalidate()
        
        // Start new timer for code expiration
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: codeExpirationTime, repeats: false) { [weak self] _ in
            Task {
                await self?.cleanupExpiredCodes()
            }
        }
    }
    
    /// Stops cleanup timer
    private func stopCleanupTimer() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }
    
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
    
    /// Updates the last sync time for a child device (called from child device)
    func updateLastSyncTime(childUserId: String) async {
        do {
            let snapshot = try await firebaseManager.parentChildRelationshipsCollection
                .whereField("childUserId", isEqualTo: childUserId)
                .whereField("isActive", isEqualTo: true)
                .getDocuments()
            
            for doc in snapshot.documents {
                try await doc.reference.updateData([
                    "lastSyncAt": Timestamp()
                ])
            }
            
            print("✅ Updated last sync time for child: \(childUserId)")
        } catch {
            print("❌ Failed to update last sync time: \(error)")
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }
    
    /// Test very basic Firebase operations
    func testBasicFirebaseOperations() async {
        print("🧪 Testing very basic Firebase operations...")
        
        guard let currentUser = Auth.auth().currentUser else {
            print("❌ No authenticated user")
            return
        }
        
        print("✅ Authenticated user: \(currentUser.uid)")
        
        do {
            // Test 1: Try to read from a simple collection
            print("🧪 Test 1: Reading from users collection...")
            let userSnapshot = try await firebaseManager.usersCollection.document(currentUser.uid).getDocument()
            print("✅ Successfully read user document")
            
            // Test 2: Try to write to users collection
            print("🧪 Test 2: Writing to users collection...")
            try await firebaseManager.usersCollection.document(currentUser.uid).setData([
                "lastTested": Timestamp(),
                "testUser": true
            ], merge: true)
            print("✅ Successfully wrote to user document")
            
            // Test 3: Try to read from pairingRequests collection
            print("🧪 Test 3: Reading from pairingRequests collection...")
            let pairingSnapshot = try await firebaseManager.pairingRequestsCollection.limit(to: 1).getDocuments()
            print("✅ Successfully read from pairingRequests collection")
            
            // Test 4: Try to create a document in pairingRequests
            print("🧪 Test 4: Creating document in pairingRequests...")
            let testDoc = try await firebaseManager.pairingRequestsCollection.addDocument(data: [
                "test": true,
                "userId": currentUser.uid,
                "timestamp": Timestamp()
            ])
            print("✅ Successfully created document: \(testDoc.documentID)")
            
            // Test 5: Try to update the document
            print("🧪 Test 5: Updating document...")
            try await testDoc.updateData([
                "updated": true,
                "updateTime": Timestamp()
            ])
            print("✅ Successfully updated document")
            
            // Test 6: Try to delete the document
            print("🧪 Test 6: Deleting document...")
            try await testDoc.delete()
            print("✅ Successfully deleted document")
            
            print("🎉 All basic Firebase operations passed!")
            
        } catch {
            print("❌ Basic Firebase test failed: \(error)")
            if let nsError = error as NSError? {
                print("❌ Error code: \(nsError.code)")
                print("❌ Error domain: \(nsError.domain)")
                print("❌ Error description: \(nsError.localizedDescription)")
            }
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
        // Simple online check based on last sync time (within 30 minutes for demo)
        let thirtyMinutesAgo = Date().addingTimeInterval(-1800)
        return lastSyncAt.dateValue() > thirtyMinutesAgo
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
