//
//  AuthenticationView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//
import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isLoading = false
    @State private var showUserTypeSelection = false
    
    var body: some View {
        NavigationStack {
            if showUserTypeSelection {
                // Show parent/child selection ONLY for new users during sign up
                ParentChildSelectionView(isNewUser: true)
            } else {
                // Original authentication form
                ScrollView {
                    VStack(spacing: 32) {
                        // Top Navigation Bar
                        HStack {
                            Button("Back") {
                                // Go back to onboarding
                                NotificationCenter.default.post(name: .showOnboarding, object: nil)
                            }
                            .foregroundColor(.blue)
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "eye.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("WatchWise")
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        .padding(.top, 20)
                        
                        // Toggle between Sign In / Sign Up
                        Picker("Auth Mode", selection: $isSignUp) {
                            Text("Sign In").tag(false)
                            Text("Sign Up").tag(true)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal, 32)
                        
                        // Form Fields
                        VStack(spacing: 16) {
                            TextField("Email", text: $email)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                            
                            SecureField("Password", text: $password)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .textContentType(isSignUp ? .newPassword : .password)
                            
                            if isSignUp {
                                SecureField("Confirm Password", text: $confirmPassword)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .textContentType(.newPassword)
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        // Action Buttons
                        VStack(spacing: 16) {
                            Button(action: handleAuthentication) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text(isSignUp ? "Create Account" : "Sign In")
                                        .font(.headline)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                            .disabled(isLoading || !isFormValid)
                            
                            // Sign in with Apple
                            SignInWithAppleButton(
                                onRequest: { request in
                                    request.requestedScopes = [.fullName, .email]
                                },
                                onCompletion: { result in
                                    handleAppleSignIn(result: result)
                                }
                            )
                            .frame(height: 50)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 32)
                        
                        Spacer()
                    }
                }
                .navigationBarHidden(true)
            }
        }
        .alert("Error", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private var isFormValid: Bool {
        if isSignUp {
            return !email.isEmpty &&
                   !password.isEmpty &&
                   !confirmPassword.isEmpty &&
                   password == confirmPassword &&
                   password.count >= 6
        } else {
            return !email.isEmpty && !password.isEmpty
        }
    }
    
    private func handleAuthentication() {
        isLoading = true
        
        if isSignUp {
            // This is a new user - show user type selection after successful account creation
            authManager.signUp(email: email, password: password) { result in
                DispatchQueue.main.async {
                    isLoading = false
                    switch result {
                    case .success:
                        // Show user type selection for new accounts ONLY
                        showUserTypeSelection = true
                    case .failure(let error):
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }
            }
        } else {
            // This is an existing user - just sign them in (no user type selection)
            authManager.signIn(email: email, password: password) { result in
                DispatchQueue.main.async {
                    isLoading = false
                    switch result {
                    case .success:
                        print("✅ Sign in successful")
                        // Force a slight delay to ensure auth state is fully updated
                        self.checkExistingChildAccount()
                    case .failure(let error):
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }
            }
        }
    }
    
    private func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            // Handle Apple Sign In - treat as new user and show selection
            authManager.handleAppleSignIn(authorization: authorization) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        showUserTypeSelection = true
                    case .failure(let error):
                        alertMessage = "Apple Sign In failed: \(error.localizedDescription)"
                        showAlert = true
                    }
                }
            }
        case .failure(let error):
            alertMessage = "Apple Sign In failed: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func checkExistingChildAccount() {
        guard let userId = authManager.currentUser?.id else {
            print("✅ No current user, proceeding with normal flow")
            return
        }
        
        // DEMO DATA - START (Add delay to ensure auth state is fully loaded)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Check if user has a stored user type
            let storedUserType = UserDefaults.standard.string(forKey: "userType")
            
            if storedUserType == "Child" {
                // This is a child account, check if already paired
                DatabaseManager.shared.checkChildAccountPairing(userId: userId) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let isPaired):
                            if isPaired {
                                // Child is already paired, complete onboarding and go straight to PairedConfirmationView
                                print("✅ Child account already paired, skipping setup")
                                self.authManager.completeOnboarding()
                            } else {
                                // Child exists but not paired, go through normal pairing flow
                                print("✅ Child account exists but not paired, continuing setup")
                            }
                        case .failure(let error):
                            print("🔥 Error checking child pairing: \(error)")
                            // On error, continue with normal flow
                        }
                    }
                }
            } else {
                // Not a child account or no stored type, continue normal flow
                print("✅ Not a child account or no stored type, continuing normal flow")
            }
        }
        // DEMO DATA - END
    }
}
