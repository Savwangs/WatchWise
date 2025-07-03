//
//  GenerateCodeView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/6/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct GenerateCodeView: View {
    @StateObject private var pairingManager = PairingManager()
    @State private var pairingCodeData: PairingCodeData?
    @State private var isCodeGenerated = false
    @State private var timeRemaining = 600 // 10 minutes in seconds
    @State private var timer: Timer?
    @State private var childName = ""
    @State private var deviceName = ""
    @State private var showNameInput = true
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isPairingCompleted = false
    @State private var pairingCheckTimer: Timer?
    @State private var firebaseListener: ListenerRegistration?
    @EnvironmentObject var authManager: AuthenticationManager
    
    let onCodeGenerated: (String) -> Void
    let onPermissionRequested: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            // Header with Sign Out Button
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button(action: signOut) {
                        Text("Sign Out")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 50) // Add top padding to avoid status bar
                
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Connect with Parent")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Generate a code to pair with your parent's device")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Name Input Section (shown first)
            if showNameInput {
                VStack(spacing: 20) {
                    Spacer()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Name")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("Enter your name", text: $childName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.body)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Device Name")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("e.g., My iPhone", text: $deviceName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.body)
                    }
                    
                    Button(action: proceedToCodeGeneration) {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canProceed ? Color.blue : Color.gray)
                            .cornerRadius(12)
                    }
                    .disabled(!canProceed)
                }
                .padding(.horizontal, 32)
            }
            
            // Code Generation Section
            else {
                VStack(spacing: 20) {
                    if isCodeGenerated, let codeData = pairingCodeData {
                        // Display Generated Code with QR Code
                        VStack(spacing: 20) {
                            Text("Your Pairing Code")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            // QR Code Display
                            if let qrCodeImage = codeData.qrCodeImage {
                                VStack(spacing: 12) {
                                    Image(uiImage: qrCodeImage)
                                        .interpolation(.none)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 200, height: 200)
                                        .background(Color.white)
                                        .cornerRadius(12)
                                        .shadow(radius: 4)
                                    
                                    Text("Scan this QR code with your parent's device")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            
                            // Code Display
                            VStack(spacing: 8) {
                                Text("Or enter this code manually:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text(codeData.code)
                                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                                    .foregroundColor(.blue)
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                    .onTapGesture {
                                        UIPasteboard.general.string = codeData.code
                                        // Show copy feedback
                                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                        impactFeedback.impactOccurred()
                                    }
                            }
                            
                            // Timer
                            VStack(spacing: 8) {
                                Text("Code expires in:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(formatTime(timeRemaining))
                                    .font(.headline)
                                    .foregroundColor(timeRemaining < 120 ? .red : .primary)
                            }
                            
                            // Instructions
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Share this code with your parent:")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("1. Have your parent register on the WatchWise app")
                                    Text("2. Then have them scan the QR code or manually enter the 6-digit code")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemBlue).opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        // Regenerate Button
                        Button(action: regenerateCode) {
                            Text("Generate New Code")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                        .padding(.top, 20)
                        .disabled(pairingManager.isLoading)
                        
                        // Manual navigation button (fallback)
                        VStack(spacing: 16) {
                            Button(action: navigateToChildHome) {
                                VStack(spacing: 4) {
                                    Text("Go to My Home Page")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Wait for your parent to pair the devices, then click this")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                            }
                            
                            Button(action: regenerateCode) {
                                Text("Generate New Code")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                            .disabled(pairingManager.isLoading)
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 40) // Add bottom padding to ensure buttons are visible
                        
                    } else {
                        Spacer()
                        // Generate Code Button
                        Button(action: generateCode) {
                            if pairingManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Generate Pairing Code")
                                    .font(.headline)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                        .disabled(pairingManager.isLoading)
                        .padding(.bottom, 40) // Add bottom padding
                    }
                }
                .padding(.horizontal, 32)
            }
        }
        .onDisappear {
            stopTimer()
            stopPairingCheckTimer()
            stopFirebaseListener()
        }
        .alert("Error", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .onChange(of: pairingManager.errorMessage) { errorMessage in
            if let error = errorMessage {
                alertMessage = error
                showAlert = true
            }
        }
    }
    
    private var canProceed: Bool {
        // Add safety checks to ensure we're working with strings
        let safeChildName = String(describing: childName).trimmingCharacters(in: .whitespacesAndNewlines)
        let safeDeviceName = String(describing: deviceName).trimmingCharacters(in: .whitespacesAndNewlines)
        
        return !safeChildName.isEmpty && !safeDeviceName.isEmpty
    }
    
    private func proceedToCodeGeneration() {
        showNameInput = false
    }
    
    private func generateCode() {
        guard let currentUser = Auth.auth().currentUser else {
            alertMessage = "You must be signed in to generate a pairing code."
            showAlert = true
            return
        }
        
        Task {
            // Ensure we're working with strings
            let safeChildName = String(describing: childName).trimmingCharacters(in: .whitespacesAndNewlines)
            let safeDeviceName = String(describing: deviceName).trimmingCharacters(in: .whitespacesAndNewlines)
            
            print("🔍 Generating pairing code with:")
            print("   - Child Name: '\(safeChildName)' (type: \(type(of: safeChildName)))")
            print("   - Device Name: '\(safeDeviceName)' (type: \(type(of: safeDeviceName)))")
            
            let result = await pairingManager.generatePairingCode(
                childUserId: currentUser.uid,
                childName: safeChildName,
                deviceName: safeDeviceName
            )
            
            await MainActor.run {
                switch result {
                case .success(let code):
                    // Create PairingCodeData for display
                    let codeData = PairingCodeData(
                        code: code,
                        qrCodeImage: pairingManager.generateQRCode(from: code),
                        expiresAt: Date().addingTimeInterval(600), // 10 minutes
                        documentId: ""
                    )
                    pairingCodeData = codeData
                    isCodeGenerated = true
                    startTimer(expirationDate: codeData.expiresAt)
                    startPairingCheckTimer(code: codeData.code)
                    startFirebaseListener()
                    onCodeGenerated(codeData.code)
                    
                case .failure(let error):
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
    
    private func regenerateCode() {
        isCodeGenerated = false
        pairingCodeData = nil
        stopTimer()
        generateCode()
    }
    
    private func startTimer(expirationDate: Date) {
        stopTimer()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let remaining = Int(expirationDate.timeIntervalSinceNow)
            if remaining > 0 {
                timeRemaining = remaining
            } else {
                stopTimer()
                timeRemaining = 0
                // Code expired
                alertMessage = "Your pairing code has expired. Please generate a new one."
                showAlert = true
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func startPairingCheckTimer(code: String) {
        stopPairingCheckTimer()
        
        // Check every 2 seconds if pairing is completed
        pairingCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            let isFirebasePaired = self.authManager.currentUser?.isDevicePaired ?? false
            
            if isFirebasePaired {
                self.stopPairingCheckTimer()
                self.navigateToChildHome()
            }
        }
    }
    
    private func stopPairingCheckTimer() {
        pairingCheckTimer?.invalidate()
        pairingCheckTimer = nil
    }
    
    private func startFirebaseListener() {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        // Listen for changes to the user's pairing status
        firebaseListener = FirebaseManager.shared.usersCollection.document(currentUser.uid)
            .addSnapshotListener { snapshot, error in
                guard let data = snapshot?.data() else { return }
                
                let isPaired = data["isDevicePaired"] as? Bool ?? false
                let hasCompletedOnboarding = data["hasCompletedOnboarding"] as? Bool ?? false
                
                if isPaired && hasCompletedOnboarding {
                    // Pairing is completed, navigate to child home
                    DispatchQueue.main.async {
                        self.navigateToChildHome()
                    }
                }
            }
    }
    
    private func stopFirebaseListener() {
        firebaseListener?.remove()
        firebaseListener = nil
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
    
    private func navigateToChildHome() {
        print("🔍 Navigating to child home...")
        
        // Add safety checks before navigation
        guard let currentUser = authManager.currentUser else {
            print("❌ No current user available for navigation")
            return
        }
        
        print("🔍 Current user before navigation:")
        print("   - ID: \(currentUser.id)")
        print("   - Email: \(currentUser.email)")
        print("   - User Type: \(currentUser.userType ?? "nil")")
        print("   - Onboarding: \(currentUser.hasCompletedOnboarding)")
        print("   - Device Paired: \(currentUser.isDevicePaired)")
        
        // Mark pairing as completed
        authManager.markPairingCompleted()
        
        // Update device pairing status in Firebase
        authManager.updateDevicePairingStatus(isPaired: true)
        
        // Complete onboarding for child
        authManager.completeOnboarding()
        
        // Navigate to child home
        print("🔍 Posting showChildHome notification")
        NotificationCenter.default.post(name: .showChildHome, object: nil)
    }
    
    // MARK: - Sign Out
    
    private func signOut() {
        do {
            try Auth.auth().signOut()
            authManager.signOut()
        } catch {
            alertMessage = "Error signing out: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

#Preview {
    GenerateCodeView(
        onCodeGenerated: { _ in },
        onPermissionRequested: { }
    )
}
