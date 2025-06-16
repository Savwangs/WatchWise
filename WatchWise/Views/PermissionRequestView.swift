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
    
    let onPermissionGranted: () -> Void
    
    var body: some View {
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
                
                Text("Grant Permission")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("To let your parent monitor your screen time, please allow access")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 60)
            
            // Permission Info Card
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("What This Allows")
                        .font(.headline)
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    PermissionItem(
                        icon: "clock.fill",
                        text: "View your daily app usage time"
                    )
                    
                    PermissionItem(
                        icon: "app.fill",
                        text: "See which apps you use most"
                    )
                    
                    PermissionItem(
                        icon: "bell.fill",
                        text: "Send gentle reminders about screen time"
                    )
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                        Text("Your Privacy")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Text("• Your messages and personal content stay private\n• Only app usage times are shared\n• You can revoke access anytime in Settings")
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
                    
                    Button(action: onPermissionGranted) {
                        Text("Continue")
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
                            Text("Grant Access")
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
        .alert("Permission Required", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
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
                        onPermissionGranted()
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
                onPermissionGranted()
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
