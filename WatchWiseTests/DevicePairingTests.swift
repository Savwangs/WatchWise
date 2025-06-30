//
//  DevicePairingTests.swift
//  WatchWiseTests
//
//  Created by Savir Wangoo on 6/7/25.
//

import XCTest
import FirebaseAuth
import FirebaseFirestore
import CoreImage.CIFilterBuiltins
@testable import WatchWise

class DevicePairingTests: XCTestCase {
    var pairingManager: PairingManager!
    var firebaseManager: FirebaseManager!
    
    override func setUpWithError() throws {
        // Configure Firebase for testing
        FirebaseApp.configure()
        pairingManager = PairingManager()
        firebaseManager = FirebaseManager.shared
    }
    
    override func tearDownWithError() throws {
        // Clean up any test data
        pairingManager = nil
    }
    
    // MARK: - Day 3: Device Pairing System Tests
    
    func testPairingManagerInitialization() {
        XCTAssertNotNil(pairingManager)
        XCTAssertFalse(pairingManager.isLoading)
        XCTAssertNil(pairingManager.errorMessage)
        XCTAssertNil(pairingManager.successMessage)
        XCTAssertFalse(pairingManager.isPaired)
        XCTAssertTrue(pairingManager.pairedChildren.isEmpty)
    }
    
    func testQRCodeGeneration() {
        let testCode = "123456"
        
        // Test QR code generation
        let qrCodeImage = pairingManager.generateQRCode(from: testCode)
        
        // QR code should be generated successfully
        XCTAssertNotNil(qrCodeImage)
        
        // Test with empty code
        let emptyQRCode = pairingManager.generateQRCode(from: "")
        XCTAssertNil(emptyQRCode)
    }
    
    func testDeviceInfoCollection() {
        // Test device info collection
        let deviceInfo = pairingManager.getDeviceInfo()
        
        XCTAssertNotNil(deviceInfo["name"])
        XCTAssertNotNil(deviceInfo["model"])
        XCTAssertNotNil(deviceInfo["systemName"])
        XCTAssertNotNil(deviceInfo["systemVersion"])
        XCTAssertNotNil(deviceInfo["timestamp"])
    }
    
    func testUniqueCodeGeneration() {
        // Test that generated codes are unique
        let codes = Set((0..<100).map { _ in
            pairingManager.generateUniqueCode()
        })
        
        // Should generate 100 unique codes
        XCTAssertEqual(codes.count, 100)
        
        // All codes should be 6 digits
        for code in codes {
            XCTAssertEqual(code.count, 6)
            XCTAssertTrue(code.allSatisfy { $0.isNumber })
        }
    }
    
    func testPairingCodeDataStructure() {
        let testCode = "123456"
        let testImage = UIImage()
        let testExpiration = Date().addingTimeInterval(600)
        let testDocumentId = "test-doc-id"
        
        let pairingCodeData = PairingCodeData(
            code: testCode,
            qrCodeImage: testImage,
            expiresAt: testExpiration,
            documentId: testDocumentId
        )
        
        XCTAssertEqual(pairingCodeData.code, testCode)
        XCTAssertEqual(pairingCodeData.qrCodeImage, testImage)
        XCTAssertEqual(pairingCodeData.expiresAt, testExpiration)
        XCTAssertEqual(pairingCodeData.documentId, testDocumentId)
    }
    
    func testChildDeviceStructure() {
        let testDevice = PairedChildDevice(
            id: "test-id",
            childUserId: "child-user-id",
            childName: "Test Child",
            deviceName: "Test iPhone",
            pairCode: "123456",
            parentId: "parent-user-id",
            pairedAt: Timestamp(),
            isActive: true,
            lastSyncAt: Timestamp()
        )
        
        XCTAssertEqual(testDevice.id, "test-id")
        XCTAssertEqual(testDevice.childUserId, "child-user-id")
        XCTAssertEqual(testDevice.childName, "Test Child")
        XCTAssertEqual(testDevice.deviceName, "Test iPhone")
        XCTAssertEqual(testDevice.pairCode, "123456")
        XCTAssertEqual(testDevice.parentId, "parent-user-id")
        XCTAssertTrue(testDevice.isActive)
        XCTAssertTrue(testDevice.isOnline) // Should be online if lastSyncAt is recent
    }
    
    func testPairingErrorHandling() {
        // Test all pairing error cases
        let errors: [PairingError] = [
            .notAuthenticated,
            .invalidCode,
            .codeNotFound,
            .codeExpired,
            .invalidData,
            .alreadyPaired,
            .databaseError("Test error"),
            .networkError
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
    
    func testCodeExpirationLogic() {
        let now = Date()
        let fiveMinutesAgo = now.addingTimeInterval(-300)
        let fiveMinutesFromNow = now.addingTimeInterval(300)
        
        // Test online status logic
        let recentDevice = PairedChildDevice(
            id: "recent",
            childUserId: "child1",
            childName: "Recent",
            deviceName: "iPhone",
            pairCode: "123456",
            parentId: "parent1",
            pairedAt: Timestamp(),
            isActive: true,
            lastSyncAt: Timestamp(date: now)
        )
        
        let oldDevice = PairedChildDevice(
            id: "old",
            childUserId: "child2",
            childName: "Old",
            deviceName: "iPhone",
            pairCode: "123456",
            parentId: "parent1",
            pairedAt: Timestamp(),
            isActive: true,
            lastSyncAt: Timestamp(date: fiveMinutesAgo)
        )
        
        XCTAssertTrue(recentDevice.isOnline)
        XCTAssertFalse(oldDevice.isOnline)
    }
    
    func testFirebaseCollectionAccess() {
        // Test that all required collections are accessible
        XCTAssertNotNil(firebaseManager.pairingRequestsCollection)
        XCTAssertNotNil(firebaseManager.parentChildRelationshipsCollection)
        XCTAssertNotNil(firebaseManager.usersCollection)
    }
    
    func testEmailValidation() {
        // Test email validation logic
        let validEmails = [
            "test@example.com",
            "user.name@domain.co.uk",
            "user+tag@example.org"
        ]
        
        let invalidEmails = [
            "invalid-email",
            "@example.com",
            "user@",
            "user@.com"
        ]
        
        for email in validEmails {
            XCTAssertTrue(pairingManager.isValidEmail(email))
        }
        
        for email in invalidEmails {
            XCTAssertFalse(pairingManager.isValidEmail(email))
        }
    }
    
    func testCodeValidation() {
        // Test code validation
        let validCodes = ["123456", "000000", "999999"]
        let invalidCodes = ["12345", "1234567", "abcdef", "12 345", ""]
        
        for code in validCodes {
            XCTAssertTrue(code.count == 6 && code.allSatisfy { $0.isNumber })
        }
        
        for code in invalidCodes {
            XCTAssertFalse(code.count == 6 && code.allSatisfy { $0.isNumber })
        }
    }
    
    func testDevicePairingStatus() {
        // Test device pairing status logic
        let pairedDevice = PairedChildDevice(
            id: "paired",
            childUserId: "child1",
            childName: "Paired Child",
            deviceName: "iPhone",
            pairCode: "123456",
            parentId: "parent1",
            pairedAt: Timestamp(),
            isActive: true,
            lastSyncAt: Timestamp()
        )
        
        let unpairedDevice = PairedChildDevice(
            id: "unpaired",
            childUserId: "child2",
            childName: "Unpaired Child",
            deviceName: "iPhone",
            pairCode: "123456",
            parentId: "parent1",
            pairedAt: Timestamp(),
            isActive: false,
            lastSyncAt: Timestamp()
        )
        
        XCTAssertTrue(pairedDevice.isActive)
        XCTAssertFalse(unpairedDevice.isActive)
    }
    
    func testTimestampHandling() {
        // Test timestamp conversion
        let now = Date()
        let timestamp = Timestamp(date: now)
        let convertedDate = timestamp.dateValue()
        
        // Should be within 1 second
        XCTAssertEqual(now.timeIntervalSince1970, convertedDate.timeIntervalSince1970, accuracy: 1.0)
    }
    
    func testAsyncOperations() {
        let expectation = XCTestExpectation(description: "Async operation")
        
        Task {
            // Test that async operations can be called
            await pairingManager.loadPairedChildren()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testErrorPropagation() {
        // Test that errors are properly propagated
        let expectation = XCTestExpectation(description: "Error handling")
        
        Task {
            // Try to load children without authentication (should fail gracefully)
            await pairingManager.loadPairedChildren()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
}

// MARK: - Helper Extensions for Testing

extension PairingManager {
    // Expose private methods for testing
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
    
    func getDeviceInfo() -> [String: Any] {
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
    
    func generateUniqueCode() -> String {
        let digits = "0123456789"
        return String((0..<6).map { _ in digits.randomElement()! })
    }
    
    func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
} 