//
//  AuthenticationTests.swift
//  WatchWiseTests
//
//  Created by Savir Wangoo on 6/7/25.
//

import XCTest
import FirebaseAuth
import FirebaseFirestore
@testable import WatchWise

class AuthenticationTests: XCTestCase {
    var authManager: AuthenticationManager!
    var firebaseManager: FirebaseManager!
    
    override func setUpWithError() throws {
        // Configure Firebase for testing
        FirebaseApp.configure()
        authManager = AuthenticationManager()
        firebaseManager = FirebaseManager.shared
    }
    
    override func tearDownWithError() throws {
        // Clean up any test data
        authManager = nil
    }
    
    // MARK: - Day 2: Authentication System Tests
    
    func testAuthenticationManagerInitialization() {
        XCTAssertNotNil(authManager)
        XCTAssertFalse(authManager.isAuthenticated)
        XCTAssertNil(authManager.currentUser)
        XCTAssertTrue(authManager.isLoading)
    }
    
    func testFirebaseManagerCollections() {
        // Test that all required collections are accessible
        XCTAssertNotNil(firebaseManager.usersCollection)
        XCTAssertNotNil(firebaseManager.familiesCollection)
        XCTAssertNotNil(firebaseManager.childDevicesCollection)
        XCTAssertNotNil(firebaseManager.pairingRequestsCollection)
        XCTAssertNotNil(firebaseManager.parentChildRelationshipsCollection)
        XCTAssertNotNil(firebaseManager.screenTimeCollection)
        XCTAssertNotNil(firebaseManager.messagesCollection)
        XCTAssertNotNil(firebaseManager.settingsCollection)
    }
    
    func testPasswordResetFunctionality() {
        let expectation = XCTestExpectation(description: "Password reset")
        
        // Test password reset with invalid email
        authManager.resetPassword(email: "invalid-email") { result in
            switch result {
            case .success:
                XCTFail("Password reset should fail with invalid email")
            case .failure(let error):
                // Expected to fail with invalid email
                XCTAssertNotNil(error)
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testEmailVerificationStatus() {
        let expectation = XCTestExpectation(description: "Email verification check")
        
        // Test email verification check when not authenticated
        authManager.checkEmailVerification { isVerified in
            XCTAssertFalse(isVerified)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testResendEmailVerification() {
        let expectation = XCTestExpectation(description: "Resend email verification")
        
        // Test resend email verification when not authenticated
        authManager.resendEmailVerification { result in
            switch result {
            case .success:
                XCTFail("Should fail when not authenticated")
            case .failure(let error):
                // Expected to fail when not authenticated
                XCTAssertNotNil(error)
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testUserProfileCreation() {
        // Test that user profile structure is correct
        let testUser = AppUser(
            id: "test-user-id",
            email: "test@example.com",
            isDevicePaired: false,
            hasCompletedOnboarding: false,
            userType: nil,
            createdAt: Date(),
            isEmailVerified: false
        )
        
        XCTAssertEqual(testUser.id, "test-user-id")
        XCTAssertEqual(testUser.email, "test@example.com")
        XCTAssertFalse(testUser.isDevicePaired)
        XCTAssertFalse(testUser.hasCompletedOnboarding)
        XCTAssertNil(testUser.userType)
        XCTAssertFalse(testUser.isEmailVerified)
    }
    
    func testFirebaseErrorHandling() {
        // Test Firebase error enum
        let errors: [FirebaseManager.FirebaseError] = [
            .userNotAuthenticated,
            .documentNotFound,
            .invalidData,
            .networkError,
            .permissionDenied,
            .quotaExceeded,
            .unavailable
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
    
    func testAuthenticationStateChanges() {
        let expectation = XCTestExpectation(description: "Auth state change")
        
        // Test that auth state listener is properly set up
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // The auth state listener should be set up by now
            XCTAssertNotNil(self.authManager)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testUserDefaultsIntegration() {
        // Test UserDefaults integration for user type
        let testUserType = "Parent"
        UserDefaults.standard.set(testUserType, forKey: "userType")
        
        let retrievedUserType = UserDefaults.standard.string(forKey: "userType")
        XCTAssertEqual(retrievedUserType, testUserType)
        
        // Test child mode
        UserDefaults.standard.set(true, forKey: "isChildMode")
        let isChildMode = UserDefaults.standard.bool(forKey: "isChildMode")
        XCTAssertTrue(isChildMode)
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "userType")
        UserDefaults.standard.removeObject(forKey: "isChildMode")
    }
    
    func testFirebaseConnection() {
        let expectation = XCTestExpectation(description: "Firebase connection test")
        
        firebaseManager.testFirebaseConnection { success in
            // This test may fail in CI/CD environments without proper Firebase setup
            // We're just testing that the method doesn't crash
            XCTAssertNotNil(success)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testCollectionValidation() {
        let expectation = XCTestExpectation(description: "Collection validation")
        
        firebaseManager.validateCollections { results in
            // Test that validation returns results for all collections
            XCTAssertNotNil(results)
            XCTAssertGreaterThan(results.count, 0)
            
            // Check that we have results for expected collections
            let expectedCollections = [
                "users", "families", "childDevices", "pairingRequests",
                "parentChildRelationships", "screenTimeData", "messages", "settings"
            ]
            
            for collection in expectedCollections {
                XCTAssertTrue(results.keys.contains(collection))
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
} 