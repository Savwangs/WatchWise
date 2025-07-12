//
//  PermissionRequestView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/6/25.
//

import SwiftUI
import FamilyControls
import FirebaseAuth

struct PermissionRequestView: View {
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var permissionGranted = false
    @State private var navigateToCodeGeneration = false
    @EnvironmentObject var authManager: AuthenticationManager
    
    let onPermissionGranted: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
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
                    
                    Text("To connect with your parent, we need your permission to monitor screen time and app usage")
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
                        
                        PermissionItem(
                            icon: "shield.checkered",
                            text: "App installation and removal tracking"
                        )
                        
                        PermissionItem(
                            icon: "chart.bar.fill",
                            text: "Detailed usage analytics and reports"
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
                        
                        Text("• We NEVER access your messages, photos, or personal content\n• We NEVER track your location or browsing history\n• We ONLY monitor app usage time and screen time (same data you see in iOS Settings)\n• We track which apps you install or remove\n• Your parent can ONLY see which apps you use, for how long, when you install new apps or delete previos apps, and if you delete the WatchWise app")
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
        Task {
            do {
                print("🔄 Requesting Family Controls authorization...")
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                
                await MainActor.run {
                    isLoading = false
                    permissionGranted = true
                    
                    // Store authorization status permanently
                    UserDefaults.standard.set(true, forKey: "hasRequestedScreenTimePermission")
                    UserDefaults.standard.set(true, forKey: "screenTimeAuthorized")
                    UserDefaults.standard.set(Date(), forKey: "screenTimeAuthorizationDate")
                    
                    print("✅ Family Controls authorization granted and stored")
                    
                    // Auto-continue after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        navigateToCodeGeneration = true
                    }
                }
                
            } catch {
                await MainActor.run {
                    isLoading = false
                    alertMessage = "Failed to grant permission: \(error.localizedDescription)\n\nPlease try again or contact support if the issue persists."
                    showAlert = true
                    print("🔥 Authorization error: \(error)")
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
