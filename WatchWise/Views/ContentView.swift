//
//  ContentView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//

import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @StateObject private var authManager = AuthenticationManager()
    @State private var showSplashScreen = true
    @State private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    
    var body: some View {
        ZStack {
            if showSplashScreen {
                SplashScreen()
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                showSplashScreen = false
                            }
                        }
                    }
            } else if authManager.isLoading {
                // Show a loading screen while checking auth state
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .padding(.top)
                }
            } else {
                if authManager.isAuthenticated {
                    // User is signed in - check navigation flow
                    if let userType = authManager.currentUser?.userType {
                        // User has selected their type - route based on type
                        if userType == "Child" {
                            // FIXED: Child flow - check if they've completed initial setup
                            if authManager.hasCompletedOnboarding {
                                // DEMO DATA - START (Child has completed setup, show child home with welcome back)
                                // Existing child user - go directly to child home with welcome back message
                                ChildHomeView()
                                // DEMO DATA - END
                                
                                /* PRODUCTION CODE - Uncomment when ready for production
                                // Check if device is actually paired in production
                                if let currentUser = authManager.currentUser, currentUser.isDevicePaired {
                                    ChildHomeView()
                                } else {
                                    // Device not paired - should not happen in normal flow
                                    GenerateCodeView(onCodeGenerated: { _ in }, onPermissionRequested: { })
                                }
                                */
                            } else {
                                // New child user - hasn't completed setup yet
                                if authManager.isChildInSetup {
                                    // DEMO DATA - START (New child going through setup - start with code generation)
                                    NavigationView {
                                        GenerateCodeView(
                                            onCodeGenerated: { code in
                                                print("Code generated: \(code)")
                                            },
                                            onPermissionRequested: {
                                                // After code generation, go to permission request
                                                // This will be handled by the GenerateCodeView navigation
                                            }
                                        )
                                    }
                                    // DEMO DATA - END
                                } else {
                                    // Fallback - shouldn't happen in normal flow
                                    ChildHomeView()
                                }
                            }
                        } else {
                            // Parent flow - check device pairing and onboarding
                            if authManager.hasCompletedOnboarding {
                                if let currentUser = authManager.currentUser, currentUser.isDevicePaired {
                                    // Device is paired - go to main parent app
                                    MainTabView()
                                } else {
                                    // Not paired yet - go to device pairing
                                    DevicePairingView()
                                }
                            } else {
                                // Still need to complete onboarding
                                DevicePairingView()
                            }
                        }
                    } else {
                        // User signed up but didn't complete user type selection
                        // This should only happen for users who signed up but didn't complete the flow
                        ParentChildSelectionView(isNewUser: false)
                    }
                } else {
                    // User is not signed in
                    if hasSeenOnboarding && !showOnboarding {
                        // Show auth screen after onboarding
                        AuthenticationView()
                            .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
                                showOnboarding = true
                            }
                    } else {
                        // Show onboarding first for new users or when requested
                        OnboardingView()
                            .onReceive(NotificationCenter.default.publisher(for: .onboardingCompleted)) { _ in
                                hasSeenOnboarding = true
                                showOnboarding = false
                            }
                    }
                }
            }
        }
        .environmentObject(authManager)
    }
}

#Preview {
    ContentView()
}


