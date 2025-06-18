//
//  PairedConfirmationView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/6/25.
//

import SwiftUI

struct PairedConfirmationView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    let isPaired: Bool
    @State private var currentScreenTime = "2h 45m"
    @State private var showSignOutAlert = false
    
    var body: some View {
        VStack(spacing: 40) {
            // Success Header - Modified to not show "Connection Successful" for existing accounts
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                
                // DEMO DATA - START (Remove in production)
                if authManager.isReturningChildUser() {
                    Text("Welcome back, Savir!")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Your device (Savir's iPhone) is connected to your parent")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Connection Successful!")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Your device (Savir's iPhone) is now connected to your parent")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                // DEMO DATA - END (Remove in production)
                
                /* PRODUCTION CODE - Uncomment when ready for production
                Text("Welcome back!")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Your device is connected to your parent")
                
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                 */
            }
            .padding(.top, 80)
            
            // Status Card
            VStack(spacing: 20) {
                HStack {
                    Image(systemName: "link.circle.fill")
                        .foregroundColor(.green)
                    Text("Connection Status")
                        .font(.headline)
                    Spacer()
                    Text("Active")
                        .font(.subheadline)
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(8)
                }
                
                Divider()
                
                // Today's Screen Time (Optional)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today's Screen Time")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(currentScreenTime)
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "clock.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal, 32)
            
            // Info Section
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("How It Works")
                        .font(.headline)
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    InfoItem(
                        icon: "arrow.up.circle.fill",
                        text: "Your screen time data is shared automatically",
                        color: .blue
                    )
                    
                    InfoItem(
                        icon: "bell.fill",
                        text: "You'll receive gentle reminders from your parent",
                        color: .orange
                    )
                    
                    InfoItem(
                        icon: "gear.circle.fill",
                        text: "Change settings anytime in your device Settings",
                        color: .gray
                    )
                }
            }
            .padding()
            .background(Color(.systemBlue).opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Bottom Actions
            VStack(spacing: 12) {
                Text("This app will now run in the background to track your screen time securely.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Button(action: {
                    showSignOutAlert = true
                }) {
                    Text("Sign Out")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
            }
            .padding(.bottom, 50)
        }
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                authManager.signOut()
                UserDefaults.standard.removeObject(forKey: "isChildMode")
                UserDefaults.standard.removeObject(forKey: "userType")
            }
        } message: {
            Text("Are you sure you want to sign out? This will disconnect your device from your parent.")
        }
        .onAppear {
            // Simulate updating screen time
            updateScreenTime()
        }
    }
    
    private func updateScreenTime() {
        // DEMO DATA - START (Remove in production)
        // Use demo data from ScreenTimeData for consistency
        let demoData = ScreenTimeData.demoData
        let hours = Int(demoData.totalScreenTime) / 3600
        let minutes = Int(demoData.totalScreenTime) % 3600 / 60
        currentScreenTime = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        // DEMO DATA - END (Remove in production)
        
        /* PRODUCTION CODE - Uncomment when ready for production
            // In a real app, this would fetch actual screen time data from Firebase
            // Example implementation:
            // Task {
            //     if let userId = authManager.currentUser?.id {
            //         let screenTimeData = try await databaseManager.getScreenTimeData(for: userId, date: Date())
            //         await MainActor.run {
            //             let hours = Int(screenTimeData.totalScreenTime) / 3600
            //             let minutes = Int(screenTimeData.totalScreenTime) % 3600 / 60
            //             currentScreenTime = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
            //         }
            //     }
            // }
        */
        // In a real app, this would fetch actual screen time data

        
    }
}

struct InfoItem: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

#Preview {
    PairedConfirmationView(isPaired: true)
        .environmentObject(AuthenticationManager())
}
