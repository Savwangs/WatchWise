//
//  SplashScreen.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//

import SwiftUI
import FirebaseCore

struct SplashScreen: View {
    @State private var isLoading = true
    @State private var firebaseStatus = "Initializing..."
    @State private var showFirebaseTest = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.blue, .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // App Icon
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.white)
                
                // App Name
                Text("WatchWise")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                // Tagline
                Text("Smart Screen Time Management")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
                
                // Loading indicator
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text(firebaseStatus)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                
                // Firebase test button (for development)
                if showFirebaseTest {
                    Button("Test Firebase Config") {
                        testFirebaseConfiguration()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(10)
                }
            }
        }
        .onAppear {
            startLoadingSequence()
        }
    }
    
    private func startLoadingSequence() {
        // Simulate loading sequence
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            firebaseStatus = "Configuring Firebase..."
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            firebaseStatus = "Testing connection..."
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            firebaseStatus = "Validating collections..."
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            firebaseStatus = "Ready!"
            isLoading = false
            showFirebaseTest = true
        }
    }
    
    private func testFirebaseConfiguration() {
        isLoading = true
        firebaseStatus = "Testing Firebase..."
        
        let firebaseManager = FirebaseManager.shared
        
        // Test Firebase connection
        firebaseManager.testFirebaseConnection { success in
            DispatchQueue.main.async {
                if success {
                    firebaseStatus = "Firebase: ✅ Connected"
                } else {
                    firebaseStatus = "Firebase: ❌ Failed"
                }
                
                // Test collections
                firebaseManager.validateCollections { results in
                    DispatchQueue.main.async {
                        var validCollections = 0
                        var totalCollections = results.count
                        
                        for (_, isValid) in results {
                            if isValid {
                                validCollections += 1
                            }
                        }
                        
                        firebaseStatus = "Collections: \(validCollections)/\(totalCollections) ✅"
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isLoading = false
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    SplashScreen()
}
