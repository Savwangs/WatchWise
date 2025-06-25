//
//  DevicePairingView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//

//When you're ready to remove the demo mode (before production), just delete the "Development Mode Section" and the skipPairingWithDemoData() function.

import SwiftUI
import FirebaseFirestore
import Foundation
import FirebaseAuth

struct DevicePairingView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var pairingManager = PairingManager()
    @State private var pairCode = ""
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Top Navigation Bar
                HStack {
                    Spacer()
                    
                    Button("Sign Out") {
                        authManager.signOut()
                    }
                    .foregroundColor(.red)
                    .padding(.trailing)
                }
                .padding(.top, 10)
                
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("Connect to Your Child's Device")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                // Instructions
                VStack(alignment: .leading, spacing: 16) {
                    InstructionRow(
                        number: "1",
                        text: "Install the WatchWise Kids app on your child's iPhone"
                    )
                    
                    InstructionRow(
                        number: "2",
                        text: "Open that app and tap 'Generate Code'"
                    )
                    
                    InstructionRow(
                        number: "3",
                        text: "Enter the 6-digit code below:"
                    )
                }
                .padding(.horizontal, 32)
                
                // Code Input
                VStack(spacing: 16) {
                    TextField("Enter 6-digit code", text: $pairCode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .onChange(of: pairCode) { newValue in
                            // Limit to 6 digits and only numbers
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered.count > 6 {
                                pairCode = String(filtered.prefix(6))
                            } else {
                                pairCode = filtered
                            }
                        }
                    
                    Button(action: pairDevice) {
                        if pairingManager.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Pair Devices")
                                .font(.headline)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(pairCode.count == 6 && !pairingManager.isLoading ? Color.blue : Color.gray)
                    .cornerRadius(12)
                    .disabled(pairCode.count != 6 || pairingManager.isLoading)
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Privacy Note
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                    
                    Text("Your child's privacy is protected. We only collect screen time data that you can already see in iOS Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .navigationBarHidden(true)
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {
                if isSuccess {
                    // The ContentView will automatically navigate based on isDevicePaired
                }
            }
        } message: {
            Text(alertMessage)
        }
        .onChange(of: pairingManager.errorMessage) { errorMessage in
            if let error = errorMessage {
                alertTitle = "Pairing Failed"
                alertMessage = error
                isSuccess = false
                showAlert = true
            }
        }
        .onChange(of: pairingManager.successMessage) { successMessage in
            if let success = successMessage {
                alertTitle = "Success!"
                alertMessage = success
                isSuccess = true
                showAlert = true
            }
        }
    }
    
    private func pairDevice() {
        guard let parentId = authManager.currentUser?.id else {
            alertTitle = "Authentication Error"
            alertMessage = "Please sign in again."
            isSuccess = false
            showAlert = true
            return
        }
        
        Task {
            let result = await pairingManager.pairWithChild(
                code: pairCode,
                parentUserId: parentId
            )
            
            await MainActor.run {
                switch result {
                case .success(let pairingSuccess):
                    // Update the parent's device pairing status
                    authManager.updateDevicePairingStatus(isPaired: true)
                    
                    // DEMO DATA - START (Store demo data for parent dashboard)
                    UserDefaults.standard.set(pairingSuccess.childName, forKey: "demoChildName")
                    UserDefaults.standard.set(pairingSuccess.deviceName, forKey: "demoDeviceName")
                    UserDefaults.standard.set(true, forKey: "demoParentDevicePaired")
                    
                    // Set the pairing completion flag for the child device to detect
                    print("🔗 Setting pairing completion flag for child device with code: \(pairCode)")
                    print("🔗 Pairing success - childName: \(pairingSuccess.childName), deviceName: \(pairingSuccess.deviceName)")
                    UserDefaults.standard.set(true, forKey: "demoChildPaired_\(pairCode)")
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "demoPairingTimestamp_\(pairCode)")
                    
                    // Verify the flag was set
                    let flagSet = UserDefaults.standard.bool(forKey: "demoChildPaired_\(pairCode)")
                    print("🔗 Verification - pairing flag set for \(pairCode): \(flagSet)")
                    
                    // Debug the pairing status
                    authManager.debugPairingStatus()
                    // DEMO DATA - END
                    
                    alertTitle = "Pairing Successful!"
                    alertMessage = "Successfully connected to \(pairingSuccess.childName)'s device. You can now monitor their screen time."
                    isSuccess = true
                    showAlert = true
                    
                case .failure:
                    // Error is handled by the onChange modifier above
                    break
                }
            }
        }
    }
}

struct InstructionRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

#Preview {
    DevicePairingView()
        .environmentObject(AuthenticationManager())
}
