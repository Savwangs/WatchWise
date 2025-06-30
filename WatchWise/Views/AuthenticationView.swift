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
    @State private var showPasswordReset = false
    @State private var showEmailVerificationAlert = false
    
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
                        
                        // Password Reset Link (only for sign in)
                        if !isSignUp {
                            Button("Forgot Password?") {
                                showPasswordReset = true
                            }
                            .foregroundColor(.blue)
                            .font(.footnote)
                        }
                        
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
                            
                            // Sign in with Apple (placeholder for Day 14)
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
                            .onTapGesture {
                                handleAppleSignInButtonTap()
                            }
                            .opacity(0.7)
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
        .alert("Email Verification Required", isPresented: $authManager.showEmailVerificationAlert) {
            Button("Resend Email") {
                resendEmailVerification()
            }
            Button("Check Again") {
                checkEmailVerification()
            }
            Button("OK") { }
        } message: {
            Text("Please check your email and verify your account before continuing. You can resend the verification email or check if you've already verified.")
        }
        .sheet(isPresented: $showPasswordReset) {
            PasswordResetView()
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
    
    // Add this method to handle Apple Sign In button tap
    private func handleAppleSignInButtonTap() {
        alertMessage = "Apple Sign In will be available on Day 14 when we set up the Apple Developer account. For now, please use email/password authentication."
        showAlert = true
    }
    
    private func resendEmailVerification() {
        authManager.resendEmailVerification { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    alertMessage = "Verification email sent successfully!"
                    showAlert = true
                case .failure(let error):
                    alertMessage = "Failed to send verification email: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func checkEmailVerification() {
        authManager.checkEmailVerification { isVerified in
            DispatchQueue.main.async {
                if isVerified {
                    alertMessage = "Email verified successfully! You can now sign in."
                    showAlert = true
                    authManager.showEmailVerificationAlert = false
                } else {
                    alertMessage = "Email not yet verified. Please check your inbox and click the verification link."
                    showAlert = true
                }
            }
        }
    }
    
    private func checkExistingChildAccount() {
        // This method checks if the user is a returning child user
        // and handles the appropriate navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if authManager.isReturningChildUser() {
                // Navigate to child home view
                NotificationCenter.default.post(name: .showChildHome, object: nil)
            }
        }
    }
}

// MARK: - Password Reset View

struct PasswordResetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "lock.rotation")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("Reset Password")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Enter your email address and we'll send you a link to reset your password.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // Email Field
                TextField("Email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding(.horizontal)
                
                // Reset Button
                Button(action: resetPassword) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Send Reset Link")
                            .font(.headline)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
                .disabled(isLoading || email.isEmpty)
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Password Reset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert(isSuccess ? "Success" : "Error", isPresented: $showAlert) {
            Button("OK") {
                if isSuccess {
                    dismiss()
                }
            }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func resetPassword() {
        isLoading = true
        
        AuthenticationManager().resetPassword(email: email) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success:
                    isSuccess = true
                    alertMessage = "Password reset email sent successfully! Please check your inbox."
                    showAlert = true
                case .failure(let error):
                    isSuccess = false
                    alertMessage = "Failed to send reset email: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
}
