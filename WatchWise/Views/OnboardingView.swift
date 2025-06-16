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
                        OnboardingPageView(page: onboardingPages[index])
                            .tag(index)
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
                        Text(currentPage < onboardingPages.count - 1 ? "Next" : "Get Started")
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

#Preview {
    OnboardingView()
        .environmentObject(AuthenticationManager())
}
