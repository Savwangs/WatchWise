//
//  AuthenticationManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import CryptoKit

// Custom User model to hold our app-specific data
struct AppUser {
    let id: String
    let email: String
    var isDevicePaired: Bool
    var hasCompletedOnboarding: Bool
    var userType: String? // Add userType field
    let createdAt: Date
    var isEmailVerified: Bool
    var name: String?
    var deviceName: String?
    
    init(id: String, email: String, isDevicePaired: Bool = false, hasCompletedOnboarding: Bool = false, userType: String? = nil, createdAt: Date = Date(), isEmailVerified: Bool = false, name: String? = nil, deviceName: String? = nil) {
        self.id = id
        self.email = email
        self.isDevicePaired = isDevicePaired
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.userType = userType
        self.createdAt = createdAt
        self.isEmailVerified = isEmailVerified
        self.name = name
        self.deviceName = deviceName
    }
}

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: AppUser?
    @Published var isLoading = true
    @Published var isNewSignUp = false
    @Published var isChildInSetup: Bool = false
    @Published var showEmailVerificationAlert = false
    
    private let firebaseManager = FirebaseManager.shared
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    // Add this computed property:
    var hasCompletedOnboarding: Bool {
        return currentUser?.hasCompletedOnboarding ?? false
    }
    
    init() {
        setupAuthStateListener()
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
    
    private func setupAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] (auth, user) in
            print("🔄 Auth state changed - User: \(user?.uid ?? "nil")")
            
            DispatchQueue.main.async {
                if let firebaseUser = user {
                    print("✅ User is signed in: \(firebaseUser.uid)")
                    self?.loadUserProfile(userId: firebaseUser.uid)
                } else {
                    print("❌ User is signed out")
                    self?.isAuthenticated = false
                    self?.currentUser = nil
                    self?.isLoading = false
                    // Clear local storage on sign out
                    UserDefaults.standard.removeObject(forKey: "userType")
                    UserDefaults.standard.removeObject(forKey: "isChildMode")
                }
            }
        }
    }
    
    // MARK: - Day 2: Enhanced Authentication Methods
    
    func signUp(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🚀 Starting sign up process for email: \(email)")
        
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Firebase Auth Error: \(error)")
                    completion(.failure(error))
                } else if let firebaseUser = result?.user {
                    print("✅ User created successfully: \(firebaseUser.uid)")
                    self?.isNewSignUp = true
                    
                    // Send email verification
                    firebaseUser.sendEmailVerification { error in
                        if let error = error {
                            print("🔥 Email verification error: \(error)")
                        } else {
                            print("✅ Email verification sent")
                            self?.showEmailVerificationAlert = true
                        }
                    }
                    
                    // Create user profile in Firestore
                    self?.createUserProfile(firebaseUser: firebaseUser, completion: completion)
                }
            }
        }
    }
    
    func signIn(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🚀 Starting sign in process for email: \(email)")
        
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Sign in error: \(error)")
                    completion(.failure(error))
                } else if let firebaseUser = result?.user {
                    print("✅ User signed in successfully: \(firebaseUser.uid)")
                    self?.isNewSignUp = false
                    
                    // Check if email is verified
                    if !firebaseUser.isEmailVerified {
                        print("⚠️ Email not verified")
                        self?.showEmailVerificationAlert = true
                    }
                    
                    // Load user profile
                    self?.loadUserProfile(userId: firebaseUser.uid)
                    completion(.success(()))
                }
            }
        }
    }
    
    // MARK: - Day 2: Password Reset Functionality
    
    func resetPassword(email: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🔄 Starting password reset for email: \(email)")
        
        // Validate email format first
        guard isValidEmail(email) else {
            let error = NSError(domain: "Authentication", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid email format"])
            completion(.failure(error))
            return
        }
        
        Auth.auth().sendPasswordReset(withEmail: email) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Password reset error: \(error.localizedDescription)")
                    print("🔥 Error code: \(error._code)")
                    print("🔥 Error domain: \(error._domain)")
                    
                    // Provide more specific error messages
                    let specificError: Error
                    switch error._code {
                    case AuthErrorCode.userNotFound.rawValue:
                        specificError = NSError(domain: "Authentication", code: -1, userInfo: [NSLocalizedDescriptionKey: "No account found with this email address"])
                    case AuthErrorCode.invalidEmail.rawValue:
                        specificError = NSError(domain: "Authentication", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid email address"])
                    case AuthErrorCode.tooManyRequests.rawValue:
                        specificError = NSError(domain: "Authentication", code: -1, userInfo: [NSLocalizedDescriptionKey: "Too many requests. Please try again later"])
                    default:
                        specificError = error
                    }
                    
                    completion(.failure(specificError))
                } else {
                    print("✅ Password reset email sent successfully")
                    completion(.success(()))
                }
            }
        }
    }
    
    // Helper method to validate email format
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    // MARK: - Day 2: Email Verification
    
    func resendEmailVerification(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(.failure(FirebaseManager.FirebaseError.userNotAuthenticated))
            return
        }
        
        print("🔄 Resending email verification")
        
        currentUser.sendEmailVerification { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Email verification error: \(error)")
                    completion(.failure(error))
                } else {
                    print("✅ Email verification resent")
                    completion(.success(()))
                }
            }
        }
    }
    
    func checkEmailVerification(completion: @escaping (Bool) -> Void) {
        guard let currentUser = Auth.auth().currentUser else {
            completion(false)
            return
        }
        
        currentUser.reload { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Error reloading user: \(error)")
                    completion(false)
                } else {
                    let isVerified = currentUser.isEmailVerified
                    print("📧 Email verification status: \(isVerified)")
                    completion(isVerified)
                }
            }
        }
    }
    
    // MARK: - Apple Sign In Implementation
    
    // Store the current nonce for Apple Sign In
    private var currentNonce: String?
    
    func handleAppleSignIn(authorization: ASAuthorization, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🍎 Starting Apple Sign In process")
        
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            let error = NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Apple ID credential"])
            completion(.failure(error))
            return
        }
        
        guard let appleIDToken = appleIDCredential.identityToken else {
            let error = NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch identity token"])
            completion(.failure(error))
            return
        }
        
        guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            let error = NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to serialize token string"])
            completion(.failure(error))
            return
        }
        
        guard let nonce = currentNonce else {
            let error = NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid nonce"])
            completion(.failure(error))
            return
        }
        
        // Create Firebase credential
        let credential = OAuthProvider.credential(withProviderID: "apple.com", idToken: idTokenString, rawNonce: nonce)
        
        // Sign in with Firebase
        Auth.auth().signIn(with: credential) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Apple Sign In error: \(error)")
                    completion(.failure(error))
                } else if let firebaseUser = result?.user {
                    print("✅ Apple Sign In successful: \(firebaseUser.uid)")
                    
                    // Check if this is a new user or existing user
                    self?.checkIfNewUser(firebaseUser: firebaseUser) { isNewUser in
                        DispatchQueue.main.async {
                            if isNewUser {
                                print("🆕 New Apple Sign In user - showing user type selection")
                                self?.isNewSignUp = true
                                // Create user profile and show user type selection
                                self?.createUserProfile(firebaseUser: firebaseUser, completion: completion)
                            } else {
                                print("👤 Existing Apple Sign In user - direct sign in")
                                self?.isNewSignUp = false
                                // Load existing user profile
                                self?.loadUserProfile(userId: firebaseUser.uid)
                                completion(.success(()))
                            }
                        }
                    }
                } else {
                    let error = NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sign in failed"])
                    completion(.failure(error))
                }
            }
        }
    }
    
    func getCurrentNonce() -> String {
        // Generate a random nonce for Apple Sign In
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let rawNonce = String((0..<32).map { _ in letters.randomElement()! })
        
        // Store the raw nonce for later verification
        currentNonce = rawNonce
        
        // Return SHA256 hash of the nonce (this is what Apple expects)
        return sha256(rawNonce)
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }
    
    private func checkIfNewUser(firebaseUser: FirebaseAuth.User, completion: @escaping (Bool) -> Void) {
        // Check if user profile exists in Firestore
        firebaseManager.usersCollection.document(firebaseUser.uid).getDocument { snapshot, error in
            if let error = error {
                print("🔥 Error checking user profile: \(error)")
                // If error, assume new user
                completion(true)
                return
            }
            
            // If document doesn't exist or has no data, it's a new user
            let isNewUser = snapshot?.exists == false || snapshot?.data() == nil
            print("🔍 User profile check - isNewUser: \(isNewUser)")
            completion(isNewUser)
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            isNewSignUp = false
            showEmailVerificationAlert = false
            print("✅ User signed out successfully")
        } catch {
            print("🔥 Sign out error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Day 2: Updated User Profile Management
    
    private func createUserProfile(firebaseUser: FirebaseAuth.User, completion: @escaping (Result<Void, Error>) -> Void) {
        print("📝 Creating user profile for: \(firebaseUser.uid)")
        
        let userData: [String: Any] = [
            "email": firebaseUser.email ?? "",
            "isDevicePaired": false,
            "hasCompletedOnboarding": false,
            "userType": NSNull(), // Will be set after user selection
            "createdAt": Timestamp(),
            "lastActiveAt": Timestamp(),
            "isEmailVerified": firebaseUser.isEmailVerified
        ]
        
        // Use the correct collection from Day 1
        firebaseManager.usersCollection.document(firebaseUser.uid).setData(userData) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Firestore Error: \(error)")
                    completion(.failure(error))
                } else {
                    print("✅ User profile created successfully")
                    completion(.success(()))
                }
            }
        }
    }
    
    private func loadUserProfile(userId: String) {
        print("📖 Loading user profile for: \(userId)")
        
        // Use the correct collection from Day 1
        firebaseManager.usersCollection.document(userId).getDocument { [weak self] snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Error loading user profile: \(error.localizedDescription)")
                    // If there's a permissions error, try to create the profile
                    if error.localizedDescription.contains("permissions") || error.localizedDescription.contains("PERMISSION_DENIED") {
                        print("⚠️ Permissions error - attempting to create user profile")
                        if let currentFirebaseUser = Auth.auth().currentUser {
                            self?.createUserProfile(firebaseUser: currentFirebaseUser) { result in
                                switch result {
                                case .success:
                                    // Profile created, try loading again
                                    self?.loadUserProfile(userId: userId)
                                case .failure(let createError):
                                    print("🔥 Failed to create profile: \(createError)")
                                    self?.isLoading = false
                                }
                            }
                            return
                        }
                    }
                    self?.isLoading = false
                    return
                }
                
                guard let data = snapshot?.data() else {
                    print("⚠️ No user profile found, creating new one...")
                    // If no profile exists, create one
                    if let currentFirebaseUser = Auth.auth().currentUser {
                        self?.createUserProfile(firebaseUser: currentFirebaseUser) { result in
                            switch result {
                            case .success:
                                // Profile created, try loading again
                                self?.loadUserProfile(userId: userId)
                            case .failure(let createError):
                                print("🔥 Failed to create profile: \(createError)")
                                self?.isLoading = false
                            }
                        }
                        return
                    }
                    self?.isLoading = false
                    return
                }
                
                let userType = data["userType"] as? String
                
                // Safely extract name with type conversion
                let name: String?
                if let nameData = data["name"] {
                    if let stringName = nameData as? String {
                        name = stringName
                    } else if let numberName = nameData as? NSNumber {
                        name = numberName.stringValue
                    } else {
                        name = nil
                    }
                } else {
                    name = nil
                }
                
                // Safely extract deviceName with type conversion
                let deviceName: String?
                if let deviceNameData = data["deviceName"] {
                    if let stringDeviceName = deviceNameData as? String {
                        deviceName = stringDeviceName
                    } else if let numberDeviceName = deviceNameData as? NSNumber {
                        deviceName = numberDeviceName.stringValue
                    } else {
                        deviceName = nil
                    }
                } else {
                    deviceName = nil
                }
                
                let appUser = AppUser(
                    id: userId,
                    email: data["email"] as? String ?? "",
                    isDevicePaired: data["isDevicePaired"] as? Bool ?? false,
                    hasCompletedOnboarding: data["hasCompletedOnboarding"] as? Bool ?? false,
                    userType: userType,
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    isEmailVerified: data["isEmailVerified"] as? Bool ?? false,
                    name: name,
                    deviceName: deviceName
                )
                
                print("✅ User profile loaded: \(appUser.email), userType: \(userType ?? "nil"), onboarding: \(appUser.hasCompletedOnboarding)")
                
                // Sync userType to UserDefaults if it exists
                if let userType = userType {
                    UserDefaults.standard.set(userType, forKey: "userType")
                    if userType == "Child" {
                        UserDefaults.standard.set(true, forKey: "isChildMode")
                    }
                }
                
                self?.currentUser = appUser
                self?.isAuthenticated = true
                self?.isLoading = false

                // Reset new signup flag after successful pairing for new users
                if self?.isNewSignUp == true && appUser.hasCompletedOnboarding {
                    self?.isNewSignUp = false
                }
            }
        }
    }
    
    // MARK: - Day 2: Updated User Type Management
    
    func updateUserType(_ userType: String) {
        guard let userId = currentUser?.id else { return }
        
        print("📝 Updating user type to: \(userType) for user: \(userId)")
        
        // Use the correct collection from Day 1
        firebaseManager.usersCollection.document(userId).updateData([
            "userType": userType,
            "lastActiveAt": Timestamp()
        ]) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Error updating user type: \(error.localizedDescription)")
                } else {
                    print("✅ User type updated successfully")
                    // Update local user object
                    if var user = self?.currentUser {
                        user.userType = userType
                        self?.currentUser = user
                    }
                    
                    // Update UserDefaults
                    UserDefaults.standard.set(userType, forKey: "userType")
                    if userType == "Child" {
                        UserDefaults.standard.set(true, forKey: "isChildMode")
                    } else {
                        UserDefaults.standard.removeObject(forKey: "isChildMode")
                    }
                }
            }
        }
    }
    
    func completeOnboarding() {
        guard let userId = currentUser?.id else { return }
        
        print("🎯 Completing onboarding for: \(userId)")
        
        // Use the correct collection from Day 1
        firebaseManager.usersCollection.document(userId).updateData([
            "hasCompletedOnboarding": true,
            "lastActiveAt": Timestamp()
        ]) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Error completing onboarding: \(error.localizedDescription)")
                } else {
                    print("✅ Onboarding completed successfully")
                    // Update local user object
                    if var user = self?.currentUser {
                        user.hasCompletedOnboarding = true
                        self?.currentUser = user
                    }
                }
            }
        }
    }
    
    // MARK: - Day 2: Updated Device Pairing Status
    
    func updateDevicePairingStatus(isPaired: Bool) {
        guard let userId = currentUser?.id else { return }
        
        // Use the correct collection from Day 1
        firebaseManager.usersCollection.document(userId).updateData([
            "isDevicePaired": isPaired,
            "lastActiveAt": Timestamp()
        ]) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Error updating device pairing status: \(error.localizedDescription)")
                } else {
                    print("✅ Device pairing status updated: \(isPaired)")
                    // Update local user object
                    if var user = self?.currentUser {
                        user.isDevicePaired = isPaired
                        self?.currentUser = user
                    }
                }
            }
        }
    }
    
    func updateOnboardingStatus(_ completed: Bool) {
        guard let userId = currentUser?.id else { return }
        
        print("🎯 Updating onboarding status to: \(completed) for: \(userId)")
        
        // Use the correct collection from Day 1
        firebaseManager.usersCollection.document(userId).updateData([
            "hasCompletedOnboarding": completed,
            "lastActiveAt": Timestamp()
        ]) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Error updating onboarding status: \(error.localizedDescription)")
                } else {
                    print("✅ Onboarding status updated successfully")
                    // Update local user object
                    if var user = self?.currentUser {
                        user.hasCompletedOnboarding = completed
                        self?.currentUser = user
                    }
                }
            }
        }
    }
    
    // MARK: - Day 2: Helper Methods
    
    func updateChildSetupStatus(isInSetup: Bool) {
        self.isChildInSetup = isInSetup
    }
    
    func debugCurrentState() {
        print("🔍 DEBUG STATE:")
        print("  - isAuthenticated: \(isAuthenticated)")
        print("  - isLoading: \(isLoading)")
        print("  - currentUser: \(currentUser?.email ?? "nil")")
        print("  - userType: \(currentUser?.userType ?? "nil")")
        print("  - hasCompletedOnboarding: \(hasCompletedOnboarding)")
        print("  - isEmailVerified: \(currentUser?.isEmailVerified ?? false)")
    }
    
    func isReturningChildUser() -> Bool {
        guard let currentUser = currentUser else { return false }
        return currentUser.userType == "Child" &&
               currentUser.hasCompletedOnboarding &&
               !isNewSignUp
    }
    
    func markPairingCompleted() {
        if isNewSignUp {
            isNewSignUp = false
            print("✅ Pairing completed - reset new signup flag")
        }
    }
    
    func debugPairingStatus() {
        print("🔍 DEBUG PAIRING STATUS:")
        print("  - isAuthenticated: \(isAuthenticated)")
        print("  - currentUser?.userType: \(currentUser?.userType ?? "nil")")
        print("  - currentUser?.hasCompletedOnboarding: \(currentUser?.hasCompletedOnboarding ?? false)")
        print("  - currentUser?.isDevicePaired: \(currentUser?.isDevicePaired ?? false)")
        print("  - isChildInSetup: \(isChildInSetup)")
        print("  - hasCompletedOnboarding: \(hasCompletedOnboarding)")
    }
}

