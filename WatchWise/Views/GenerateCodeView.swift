//
//  GenerateCodeView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/6/25.
//

import SwiftUI

struct GenerateCodeView: View {
    @StateObject private var pairingManager = PairingManager()
    @State private var pairCode: String = ""
    @State private var isCodeGenerated = false
    @State private var timeRemaining = 600 // 10 minutes in seconds
    @State private var timer: Timer?
    @State private var childName = ""
    @State private var deviceName = ""
    @State private var showNameInput = true
    @State private var showAlert = false
    @State private var alertMessage = ""
    // DEMO DATA - START (Add pairing status listener for demo flow)
    @State private var isPairingCompleted = false
    @EnvironmentObject var authManager: AuthenticationManager
    // DEMO DATA - END
    
    let onCodeGenerated: (String) -> Void
    let onPermissionRequested: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            // Header
            VStack(spacing: 16) {
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
            .padding(.top, 60)
            
            // Name Input Section (shown first)
            if showNameInput {
                VStack(spacing: 20) {
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
                VStack(spacing: 24) {
                    if isCodeGenerated {
                        // Display Generated Code
                        VStack(spacing: 16) {
                            Text("Your Pairing Code")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            // Code Display
                            Text(pairCode)
                                .font(.system(size: 36, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            
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
                                    Text("1. Have your parent open WatchWise")
                                    Text("2. They should tap 'Pair Device'")
                                    Text("3. Enter this 6-digit code")
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
                        .padding(.top)
                        .disabled(pairingManager.isLoading)
                        
                        // DEMO DATA - START (Test button for debugging)
                        Button(action: testPairingCompletion) {
                            Text("Test Pairing Completion")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.top, 8)
                        
                        Button(action: checkPairingStatus) {
                            Text("Check Pairing Status")
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                        .padding(.top, 4)
                        
                        Button(action: forceNavigateToChildHome) {
                            Text("Force Navigate to Child Home")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(.top, 4)
                        // DEMO DATA - END
                        
                    } else {
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
                    }
                }
                .padding(.horizontal, 32)
            }
            
            Spacer()
            
            // DEMO DATA - START (Remove continue to permission button for demo mode)
            // Continue to Permission button removed for demo mode
            // Will be added back in production
            // DEMO DATA - END
        }
        .onDisappear {
            stopTimer()
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
        .onAppear {
            // DEMO DATA - START (Clean up expired pairing attempts on view appear)
            cleanupExpiredPairingAttempts()
            // DEMO DATA - END
        }
    }
    
    private var canProceed: Bool {
        !childName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func proceedToCodeGeneration() {
        showNameInput = false
    }
    
    private func generateCode() {
        Task {
            let result = await pairingManager.generatePairingCode(
                childName: childName.trimmingCharacters(in: .whitespacesAndNewlines),
                deviceName: deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            
            await MainActor.run {
                switch result {
                case .success(let code):
                    pairCode = code
                    isCodeGenerated = true
                    timeRemaining = 600 // Reset to 10 minutes
                    onCodeGenerated(code)
                    startTimer()
                    // DEMO DATA - START (Start listening for pairing completion)
                    startPairingListener()
                    // DEMO DATA - END
                    
                case .failure(let error):
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
    
    private func regenerateCode() {
        stopTimer()
        isCodeGenerated = false
        pairCode = ""
        generateCode()
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                // Code expired
                stopTimer()
                isCodeGenerated = false
                pairCode = ""
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        // DEMO DATA - START (Only stop pairing listener if timer actually expired)
        // Don't set isPairingCompleted here - let the pairing listener handle it
        if timeRemaining <= 0 {
            print("⏰ Timer expired - code is no longer valid")
            isCodeGenerated = false
            pairCode = ""
        }
        // DEMO DATA - END
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
    
    // DEMO DATA - START (Listen for pairing completion)
    private func startPairingListener() {
        Task {
            print("🔍 Starting pairing listener for code: \(pairCode)")
            print("🔍 Current state - isCodeGenerated: \(isCodeGenerated), isPairingCompleted: \(isPairingCompleted), timeRemaining: \(timeRemaining)")
            
            // In demo mode, simulate listening for pairing completion
            // In production, this would listen to Firebase for real-time updates
            while isCodeGenerated && !isPairingCompleted && timeRemaining > 0 {
                // Check if pairing was completed by checking demo data
                let pairingFlag = UserDefaults.standard.bool(forKey: "demoChildPaired_\(pairCode)")
                print("🔍 Checking pairing flag for code \(pairCode): \(pairingFlag)")
                
                if pairingFlag {
                    print("✅ Pairing detected for code: \(pairCode)")
                    
                    await MainActor.run {
                        print("🔄 MainActor: Processing pairing completion")
                        isPairingCompleted = true
                        
                        // DEMO DATA - START (Set child data in UserDefaults for demo)
                        UserDefaults.standard.set(childName, forKey: "demoChildName")
                        UserDefaults.standard.set(deviceName, forKey: "demoDeviceName")
                        UserDefaults.standard.set(true, forKey: "demoChildDevicePaired")
                        print("📝 Set demo data - childName: \(childName), deviceName: \(deviceName)")
                        // DEMO DATA - END
                        
                        // Stop the timer since pairing is complete
                        stopTimer()
                        
                        // Clean up the pairing flags
                        UserDefaults.standard.removeObject(forKey: "demoChildPaired_\(pairCode)")
                        UserDefaults.standard.removeObject(forKey: "demoPairingTimestamp_\(pairCode)")
                        print("🧹 Cleaned up pairing flags")
                        
                        print("🔄 Navigating to child home after successful pairing")
                        
                        // Navigate directly to child home by completing onboarding
                        // DEMO DATA - START (Navigate directly to child home by completing onboarding)
                        print("📝 Updating auth manager state...")
                        authManager.updateChildSetupStatus(isInSetup: false)
                        authManager.updateDevicePairingStatus(isPaired: true)
                        authManager.completeOnboarding()
                        
                        // Debug the pairing status
                        authManager.debugPairingStatus()
                        
                        // Force ContentView to re-evaluate navigation by triggering objectWillChange
                        print("🔄 Triggering auth manager objectWillChange...")
                        DispatchQueue.main.async {
                            authManager.objectWillChange.send()
                            print("✅ objectWillChange sent")
                        }
                        // DEMO DATA - END
                    }
                    break
                }
                
                // Check every 500ms for faster response
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            // Clean up expired pairing attempts
            await MainActor.run {
                if !isPairingCompleted {
                    print("🧹 Cleaning up expired pairing attempt for code: \(pairCode)")
                    UserDefaults.standard.removeObject(forKey: "demoChildPaired_\(pairCode)")
                    UserDefaults.standard.removeObject(forKey: "demoPairingTimestamp_\(pairCode)")
                }
            }
        }
    }
    // DEMO DATA - END
    
    // DEMO DATA - START (Clean up old pairing attempts on app launch)
    private func cleanupExpiredPairingAttempts() {
        let userDefaults = UserDefaults.standard
        let currentTime = Date().timeIntervalSince1970
        let expiredTime: TimeInterval = 600 // 10 minutes
        
        // Get all keys that might be pairing-related
        let allKeys = userDefaults.dictionaryRepresentation().keys
        
        for key in allKeys {
            if key.hasPrefix("demoPairingTimestamp_") {
                let timestamp = userDefaults.double(forKey: key)
                if currentTime - timestamp > expiredTime {
                    // Remove expired pairing attempt
                    let codeKey = key.replacingOccurrences(of: "demoPairingTimestamp_", with: "demoChildPaired_")
                    userDefaults.removeObject(forKey: key)
                    userDefaults.removeObject(forKey: codeKey)
                }
            }
        }
    }
    // DEMO DATA - END
    
    // DEMO DATA - START (Test function for debugging pairing completion)
    private func testPairingCompletion() {
        print("🧪 Testing pairing completion for code: \(pairCode)")
        UserDefaults.standard.set(true, forKey: "demoChildPaired_\(pairCode)")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "demoPairingTimestamp_\(pairCode)")
    }
    // DEMO DATA - END
    
    // DEMO DATA - START (Debug function to check pairing status)
    private func checkPairingStatus() {
        print("🔍 DEBUG: Checking pairing status for code: \(pairCode)")
        let pairingFlag = UserDefaults.standard.bool(forKey: "demoChildPaired_\(pairCode)")
        let timestamp = UserDefaults.standard.double(forKey: "demoPairingTimestamp_\(pairCode)")
        print("🔍 Pairing flag: \(pairingFlag)")
        print("🔍 Timestamp: \(timestamp)")
        print("🔍 Current state - isCodeGenerated: \(isCodeGenerated), isPairingCompleted: \(isPairingCompleted), timeRemaining: \(timeRemaining)")
    }
    // DEMO DATA - END
    
    // DEMO DATA - START (Force navigation to child home for testing)
    private func forceNavigateToChildHome() {
        print("🚀 Force navigating to child home")
        authManager.updateChildSetupStatus(isInSetup: false)
        authManager.updateDevicePairingStatus(isPaired: true)
        authManager.completeOnboarding()
        authManager.debugPairingStatus()
        
        DispatchQueue.main.async {
            authManager.objectWillChange.send()
            print("✅ Force navigation objectWillChange sent")
        }
    }
    // DEMO DATA - END
    
    // DEMO DATA - START (Add navigation state for demo flow)
    @State private var navigateToPermissions = false
    // DEMO DATA - END
}

#Preview {
    GenerateCodeView(
        onCodeGenerated: { _ in },
        onPermissionRequested: { }
    )
}
