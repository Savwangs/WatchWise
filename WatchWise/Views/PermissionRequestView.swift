//
//  PermissionRequestView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/6/25.
//

import SwiftUI
import FamilyControls

struct PermissionRequestView: View {
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var permissionGranted = false
    @State private var navigateToCodeGeneration = false
    
    let onPermissionGranted: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Privacy & Permissions")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("To connect with your parent, we need your permission to monitor screen time")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 60)
                
                // Privacy Info Card
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("What We Monitor")
                            .font(.headline)
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        PermissionItem(
                            icon: "clock.fill",
                            text: "Daily app usage time and frequency"
                        )
                        
                        PermissionItem(
                            icon: "app.fill",
                            text: "Which apps you use most often"
                        )
                        
                        PermissionItem(
                            icon: "calendar",
                            text: "Screen time patterns throughout the day"
                        )
                        
                        PermissionItem(
                            icon: "bell.fill",
                            text: "Receive gentle reminders from your parent"
                        )
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.green)
                            Text("Your Privacy is Protected")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        Text("• We NEVER access your messages, photos, or personal content\n• We NEVER track your location or browsing history\n• We ONLY monitor app usage time (same data you see in iOS Settings)\n• Your parent can ONLY see which apps you use and for how long\n• You can revoke access anytime in iOS Settings > Screen Time > Family Controls")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .foregroundColor(.orange)
                            Text("Apple's Privacy Standards")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        Text("• This app uses Apple's official FamilyControls framework\n• All data collection follows Apple's strict privacy guidelines\n• Your data is encrypted and stored securely\n• We comply with COPPA and GDPR regulations\n• You have full control over your data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 16) {
                    if permissionGranted {
                        // Success State
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.green)
                            
                            Text("Permission Granted!")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        .padding()
                        
                        Button(action: {
                            navigateToCodeGeneration = true
                        }) {
                            Text("Continue to Setup")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                        }
                    } else {
                        // Grant Access Button
                        Button(action: requestPermission) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Grant Permission")
                                    .font(.headline)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                        .disabled(isLoading)
                        
                        // Skip Button (Demo Mode)
                        Button(action: {
                            // In demo mode, simulate permission granted
                            simulatePermissionGranted()
                        }) {
                            Text("Skip (Demo Mode)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
            .navigationBarHidden(true)
            .alert("Permission Required", isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .navigationDestination(isPresented: $navigateToCodeGeneration) {
                GenerateCodeView(
                    onCodeGenerated: { code in
                        print("Code generated: \(code)")
                    },
                    onPermissionRequested: {
                        // This will be handled by the GenerateCodeView navigation
                    }
                )
            }
        }
    }
    
    private func requestPermission() {
        isLoading = true
        
        // Request Family Controls authorization
        AuthorizationCenter.shared.requestAuthorization { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success:
                    permissionGranted = true
                    // Auto-continue after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        navigateToCodeGeneration = true
                    }
                    
                case .failure(let error):
                    alertMessage = "Failed to grant permission: \(error.localizedDescription)\n\nPlease try again or contact support if the issue persists."
                    showAlert = true
                }
            }
        }
    }
    
    private func simulatePermissionGranted() {
        isLoading = true
        
        // Simulate permission request delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isLoading = false
            permissionGranted = true
            
            // Auto-continue after showing success
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                navigateToCodeGeneration = true
            }
        }
    }
}

struct PermissionItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

#Preview {
    PermissionRequestView(
        onPermissionGranted: { }
    )
}
