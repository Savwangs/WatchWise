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

// Custom User model to hold our app-specific data
struct AppUser {
    let id: String
    let email: String
    var isDevicePaired: Bool
    var hasCompletedOnboarding: Bool
    var userType: String? // Add userType field
    let createdAt: Date
    
    init(id: String, email: String, isDevicePaired: Bool = false, hasCompletedOnboarding: Bool = false, userType: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.email = email
        self.isDevicePaired = isDevicePaired
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.userType = userType
        self.createdAt = createdAt
    }
}

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: AppUser?
    @Published var isLoading = true
    // DEMO DATA - START (Track if user just signed up)
    @Published var isNewSignUp = false
    @Published var isChildInSetup: Bool = false
    // DEMO DATA - END
    
    private let db = Firestore.firestore()
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
    
    func signUp(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🚀 Starting sign up process for email: \(email)")
        
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Firebase Auth Error: \(error)")
                    completion(.failure(error))
                } else if let firebaseUser = result?.user {
                    print("✅ User created successfully: \(firebaseUser.uid)")
                    // DEMO DATA - START (Mark as new sign up)
                    self?.isNewSignUp = true
                    // DEMO DATA - END
                    // Create user profile in Firestore WITHOUT userType (will be set later)
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
                    // DEMO DATA - START (Mark as existing sign in)
                    self?.isNewSignUp = false
                    // DEMO DATA - END
                    // Explicitly load the user profile to ensure state is updated
                    self?.loadUserProfile(userId: firebaseUser.uid)
                    completion(.success(()))
                }
            }
        }
    }
    
    func handleAppleSignIn(authorization: ASAuthorization, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            completion(.failure(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Apple ID credential"])))
            return
        }
        
        guard let nonce = getCurrentNonce() else {
            completion(.failure(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid nonce"])))
            return
        }
        
        guard let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            completion(.failure(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch identity token"])))
            return
        }
        
        let credential = OAuthProvider.credential(withProviderID: "apple.com",
                                                  idToken: idTokenString,
                                                  rawNonce: nonce)
        
        Auth.auth().signIn(with: credential) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else if let firebaseUser = result?.user {
                    print("✅ Apple Sign In successful: \(firebaseUser.uid)")
                    // Create user profile for Apple users
                    self?.createUserProfile(firebaseUser: firebaseUser, completion: completion)
                }
            }
        }
    }
    
    // Helper method for Apple Sign In nonce (you'll need to implement this)
    private func getCurrentNonce() -> String? {
        // Implement nonce generation for Apple Sign In
        // This is a simplified version - you should implement proper nonce generation
        return UUID().uuidString
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            // DEMO DATA - START (Reset sign up flag)
            isNewSignUp = false
            // DEMO DATA - END
            print("✅ User signed out successfully")
        } catch {
            print("🔥 Sign out error: \(error.localizedDescription)")
        }
    }
    
    private func createUserProfile(firebaseUser: FirebaseAuth.User, completion: @escaping (Result<Void, Error>) -> Void) {
        print("📝 Creating user profile for: \(firebaseUser.uid)")
        
        let userData: [String: Any] = [
            "email": firebaseUser.email ?? "",
            "isDevicePaired": false,
            "hasCompletedOnboarding": false,
            "userType": NSNull(), // Explicitly set as null for new users - will be set after user selection
            "createdAt": Timestamp()
        ]
        
        db.collection("parents").document(firebaseUser.uid).setData(userData) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🔥 Firestore Error: \(error)")
                    completion(.failure(error))
                } else {
                    print("✅ User profile created successfully")
                    // Don't set the user here - let the auth state listener handle it
                    completion(.success(()))
                }
            }
        }
    }
    
    private func loadUserProfile(userId: String) {
        print("📖 Loading user profile for: \(userId)")
        
        db.collection("parents").document(userId).getDocument { [weak self] snapshot, error in
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
                
                let appUser = AppUser(
                    id: userId,
                    email: data["email"] as? String ?? "",
                    isDevicePaired: data["isDevicePaired"] as? Bool ?? false,
                    hasCompletedOnboarding: data["hasCompletedOnboarding"] as? Bool ?? false,
                    userType: userType,
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
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

                // DEMO DATA - START (Reset new signup flag after successful pairing for new users)
                if self?.isNewSignUp == true && appUser.hasCompletedOnboarding {
                    self?.isNewSignUp = false
                }
                // DEMO DATA - END
            }
        }
    }
    
    // Method to update user type - only called from ParentChildSelectionView
    func updateUserType(_ userType: String) {
        guard let userId = currentUser?.id else { return }
        
        print("📝 Updating user type to: \(userType) for user: \(userId)")
        
        db.collection("parents").document(userId).updateData([
            "userType": userType
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
        
        db.collection("parents").document(userId).updateData([
            "hasCompletedOnboarding": true
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
    
    // DEMO DATA - START (Methods for managing child setup status)
    func updateChildSetupStatus(isInSetup: Bool) {
        self.isChildInSetup = isInSetup
    }
    // DEMO DATA - END
    
    func updateDevicePairingStatus(isPaired: Bool) {
        guard let userId = currentUser?.id else { return }
        
        db.collection("parents").document(userId).updateData([
            "isDevicePaired": isPaired
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
        
        db.collection("parents").document(userId).updateData([
            "hasCompletedOnboarding": completed
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
    
    // Debug method to check current state
    func debugCurrentState() {
        print("🔍 DEBUG STATE:")
        print("  - isAuthenticated: \(isAuthenticated)")
        print("  - isLoading: \(isLoading)")
        print("  - currentUser: \(currentUser?.email ?? "nil")")
        print("  - userType: \(currentUser?.userType ?? "nil")")
        print("  - hasCompletedOnboarding: \(hasCompletedOnboarding)")
    }
    
    // DEMO DATA - START (Helper method to check if child is returning user)
    func isReturningChildUser() -> Bool {
        guard let currentUser = currentUser else { return false }
        // Return true only if it's a Child user, has completed onboarding, AND is not a new sign up
        return currentUser.userType == "Child" &&
               currentUser.hasCompletedOnboarding &&
               !isNewSignUp
    }
    // DEMO DATA - END
    
    // DEMO DATA - START (Function to mark pairing as completed)
    func markPairingCompleted() {
        if isNewSignUp {
            isNewSignUp = false
            print("✅ Pairing completed - reset new signup flag")
        }
    }
    // DEMO DATA - END

    /* PRODUCTION CODE - Uncomment when ready for production
    func isReturningChildUser() -> Bool {
        guard let currentUser = currentUser else { return false }
        return currentUser.userType == "Child" &&
               currentUser.hasCompletedOnboarding &&
               currentUser.isDevicePaired
    }
    */
}
