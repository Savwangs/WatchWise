//
//  GenerateCodeView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/6/25.
//

import SwiftUI

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
    @EnvironmentObject var authManager: AuthenticationManager
    
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
                                
                                Text("Tap to copy")
                                    .font(.caption)
                                    .foregroundColor(.blue)
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
                                    Text("1. Have your parent open WatchWise")
                                    Text("2. They should tap 'Pair Device'")
                                    Text("3. Scan the QR code or enter the 6-digit code")
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
                        
                        // DEMO DATA - START (Manual navigation button for child)
                        VStack(spacing: 12) {
                            Text("Once your parent has entered this code in their app, click the button below to go to your home page.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Button(action: navigateToChildHome) {
                                Text("Go to My Home Page")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.top, 20)
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
                case .success(let codeData):
                    pairingCodeData = codeData
                    isCodeGenerated = true
                    startTimer(expirationDate: codeData.expiresAt)
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
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
    
    // DEMO DATA - START
    private func navigateToChildHome() {
        // Mark pairing as completed for demo
        authManager.markPairingCompleted()
        
        // Complete onboarding for child
        authManager.completeOnboarding()
        
        // Navigate to child home
        NotificationCenter.default.post(name: .showChildHome, object: nil)
    }
    // DEMO DATA - END
}

#Preview {
    GenerateCodeView(
        onCodeGenerated: { _ in },
        onPermissionRequested: { }
    )
}
