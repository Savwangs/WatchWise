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
            
            // Continue to Permission (only after code is generated)
            if isCodeGenerated && !showNameInput {
                Button(action: {
                    stopTimer()
                    onPermissionRequested()
                }) {
                    Text("Continue to Permission Setup")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .padding(.bottom, 30)
            }
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
                case .success(let code):
                    pairCode = code
                    isCodeGenerated = true
                    timeRemaining = 600 // Reset to 10 minutes
                    onCodeGenerated(code)
                    startTimer()
                    
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
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

#Preview {
    GenerateCodeView(
        onCodeGenerated: { _ in },
        onPermissionRequested: { }
    )
}
