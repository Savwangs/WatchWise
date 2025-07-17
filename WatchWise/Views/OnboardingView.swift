//
//  OnboardingView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var currentPage = 0
    @State private var showHelpGuides = false
    
    let onboardingPages = [
        OnboardingPage(
            image: "iphone.circle.fill",
            title: "Understanding Screen Time",
            description: "This app helps you understand how your child uses their phone in a privacy-first way."
        ),
        OnboardingPage(
            image: "chart.bar.fill",
            title: "App Usage Insights",
            description: "You'll see how much time they spend in apps like Instagram, YouTube, and games."
        ),
        OnboardingPage(
            image: "bell.circle.fill",
            title: "Gentle Guidance",
            description: "You can send gentle reminders or encouragement directly to their device."
        ),
        OnboardingPage(
            image: "person.2.circle.fill",
            title: "Account Requirements",
            description: "WatchWise works with Apple IDs or Email accounts for both parents and children."
        )
    ]
    
    var body: some View {
        NavigationStack {
            VStack {
                // Page Indicator
                HStack {
                    ForEach(0..<onboardingPages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 20)
                
                // Onboarding Content
                TabView(selection: $currentPage) {
                    ForEach(0..<onboardingPages.count, id: \.self) { index in
                        if index == 3 {
                            // Special page for authentication requirements
                            AuthenticationRequirementsView(showHelpGuides: $showHelpGuides)
                                .tag(index)
                        } else {
                            OnboardingPageView(page: onboardingPages[index])
                                .tag(index)
                        }
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                
                // Navigation Buttons
                VStack(spacing: 16) {
                    Button(action: {
                        if currentPage < onboardingPages.count - 1 {
                            withAnimation {
                                currentPage += 1
                            }
                        } else {
                            // Post notification to trigger navigation to AuthenticationView
                            NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
                        }
                    }) {
                        Text(currentPage < onboardingPages.count - 1 ? "Next" : "Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    
                    if currentPage > 0 {
                        Button(action: {
                            withAnimation {
                                currentPage -= 1
                            }
                        }) {
                            Text("Back")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showHelpGuides) {
                HelpGuidesView()
            }
        }
    }
}

struct OnboardingPage {
    let image: String
    let title: String
    let description: String
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            Image(systemName: page.image)
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(page.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
    }
}

// MARK: - Authentication Requirements View
struct AuthenticationRequirementsView: View {
    @Binding var showHelpGuides: Bool
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Icon
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Title
            Text("Account Requirements")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // Requirements
            VStack(alignment: .leading, spacing: 20) {
                Text("WatchWise works with Apple IDs or Email:")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Parents")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Must sign in with their own Apple ID or Email")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "person.2.circle.fill")
                            .foregroundColor(.purple)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kids also need an Apple ID or email")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundColor(.orange)
                                    Text("If under 13: Parent can help create a Child Apple ID")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundColor(.green)
                                    Text("If 13 or older: Can create their own Apple ID or Email account")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            
            // Need Help Button
            Button(action: {
                showHelpGuides = true
            }) {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                    Text("Need Help?")
                }
                .font(.subheadline)
                .foregroundColor(.blue)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(20)
            }
            
            Spacer()
        }
    }
}

// MARK: - Help Guides View
struct HelpGuidesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedGuide: HelpGuideType = .childEmail
    
    enum HelpGuideType: String, CaseIterable {
        case childEmail = "Child Email (13+)"
        case childAppleID = "Child Apple ID (13+)"
        case parentChildAppleID = "Child Apple ID (Under 13)"
        
        var title: String {
            switch self {
            case .childEmail:
                return "Creating an Email Account (Age 13+)"
            case .childAppleID:
                return "Creating an Apple ID (Age 13+)"
            case .parentChildAppleID:
                return "Creating a Child Apple ID (Under 13)"
            }
        }
        
        var steps: [String] {
            switch self {
            case .childEmail:
                return [
                    "1. Go to Gmail.com or any email provider",
                    "2. Click 'Create Account' or 'Sign Up'",
                    "3. Enter your child's information",
                    "4. Choose a strong password",
                    "5. Verify the email address",
                    "6. Keep the login information safe"
                ]
            case .childAppleID:
                return [
                    "1. Open Settings on the iPhone/iPad",
                    "2. Tap 'Sign in to iPhone' at the top",
                    "3. Tap 'Don't have an Apple ID?'",
                    "4. Tap 'Create Apple ID'",
                    "5. Enter your child's birth date (must be 13+)",
                    "6. Enter their name and email address",
                    "7. Create a strong password",
                    "8. Set up security questions",
                    "9. Verify the email address",
                    "10. Agree to terms and conditions"
                ]
            case .parentChildAppleID:
                return [
                    "1. Open Settings on your iPhone/iPad",
                    "2. Tap your name at the top",
                    "3. Tap 'Family Sharing'",
                    "4. Tap 'Add Family Member'",
                    "5. Tap 'Create a Child Account'",
                    "6. Enter your child's name and birth date",
                    "7. Create a username for the child",
                    "8. Set up a password (you'll need to remember this)",
                    "9. Choose security questions",
                    "10. Set up Ask to Buy (optional)",
                    "11. Verify with your Apple ID password"
                ]
            }
        }
        
        var icon: String {
            switch self {
            case .childEmail:
                return "envelope.circle.fill"
            case .childAppleID:
                return "person.circle.fill"
            case .parentChildAppleID:
                return "person.2.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .childEmail:
                return .blue
            case .childAppleID:
                return .green
            case .parentChildAppleID:
                return .orange
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    Text("Account Setup Help")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Choose a guide to get step-by-step instructions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                
                // Guide Selector
                Picker("Guide Type", selection: $selectedGuide) {
                    ForEach(HelpGuideType.allCases, id: \.self) { guide in
                        Text(guide.rawValue).tag(guide)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Guide Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Guide Header
                        HStack {
                            Image(systemName: selectedGuide.icon)
                                .font(.title)
                                .foregroundColor(selectedGuide.color)
                            
                            VStack(alignment: .leading) {
                                Text(selectedGuide.title)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Text("Follow these steps carefully")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(selectedGuide.color.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                        // Steps
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(selectedGuide.steps, id: \.self) { step in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("•")
                                        .foregroundColor(selectedGuide.color)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                    
                                    Text(step)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Additional Notes
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Important Notes:")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(selectedGuide.color)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• Keep login information safe and secure")
                                Text("• Write down passwords in a safe place")
                                Text("• Use strong, unique passwords")
                                Text("• Enable two-factor authentication if available")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                        Spacer(minLength: 50)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AuthenticationManager())
}
