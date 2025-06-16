//
//  SplashScreen.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//

import SwiftUI

struct SplashScreen: View {
    @State private var scale = 0.7
    @State private var opacity = 0.5
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Logo
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(scale)
                    .opacity(opacity)
                
                VStack(spacing: 8) {
                    // App Name
                    Text("WatchWise")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    // Tagline
                    Text("Helping you guide smart screen habits")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}

#Preview {
    SplashScreen()
}
