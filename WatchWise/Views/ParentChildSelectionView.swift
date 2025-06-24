//
//  ParentChildSelectionView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/6/25.
//

import SwiftUI

struct ParentChildSelectionView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedUserType: UserType?
    let isNewUser: Bool // Pass this from AuthenticationView
    
    // Default initializer for backwards compatibility
    init(isNewUser: Bool = true) {
        self.isNewUser = isNewUser
    }
    
    enum UserType: String, CaseIterable {
        case parent = "Parent"
        case child = "Child"
        
        var icon: String {
            switch self {
            case .parent:
                return "person.2.fill"
            case .child:
                return "person.fill"
            }
        }
        
        var description: String {
            switch self {
            case .parent:
                return "Monitor and guide your child's screen time"
            case .child:
                return "Connect with your parent for healthy screen habits"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                // Header
                VStack(spacing: 16) {
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
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(isNewUser ? "Welcome! Are you a parent or child?" : "Please select your role")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                // User Type Selection Cards
                VStack(spacing: 20) {
                    ForEach(UserType.allCases, id: \.self) { userType in
                        UserTypeCard(
                            userType: userType,
                            isSelected: selectedUserType == userType
                        ) {
                            selectedUserType = userType
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Continue Button
                Button(action: handleContinue) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedUserType != nil ? Color.blue : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(selectedUserType == nil)
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
            .navigationBarHidden(true)
        }
    }
    
    private func handleContinue() {
        guard let userType = selectedUserType else { return }
        
        // Update user type in Firebase and locally
        updateUserType(userType)
        
        // Navigate based on selection
        switch userType {
        case .parent:
            // Parent completes onboarding immediately after selection
            authManager.completeOnboarding()
        case .child:
            // DEMO DATA - START (For new child users, mark them as new signups for proper flow)
            authManager.isNewSignUp = true
            // DEMO DATA - END
            // Child does NOT complete onboarding here - they need to finish full setup first
            // Set a flag to indicate this is a new child user going through setup
            authManager.isChildInSetup = true
        }
    }
    
    private func updateUserType(_ userType: UserType) {
        // Save user type preference locally
        UserDefaults.standard.set(userType.rawValue, forKey: "userType")
        
        // Save to Firebase as well
        authManager.updateUserType(userType.rawValue)
    }
}

struct UserTypeCard: View {
    let userType: ParentChildSelectionView.UserType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: userType.icon)
                    .font(.system(size: 30))
                    .foregroundColor(isSelected ? .white : .blue)
                    .frame(width: 50, height: 50)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(userType.rawValue)
                        .font(.headline)
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(userType.description)
                        .font(.subheadline)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ParentChildSelectionView()
        .environmentObject(AuthenticationManager())
}
