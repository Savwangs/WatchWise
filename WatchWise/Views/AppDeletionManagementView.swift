//
//  AppDeletionManagementView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 7/2/25.
//

import SwiftUI
import FirebaseFirestore

struct AppDeletionManagementView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var appDeletionManager = AppDeletionManager()
    @State private var showingActionSheet = false
    @State private var selectedDeletion: DeletedApp?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Content
                if appDeletionManager.isLoading {
                    loadingView
                } else if appDeletionManager.deletedApps.isEmpty {
                    emptyStateView
                } else {
                    deletedAppsListView
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            appDeletionManager.loadDeletedApps()
        }
        .actionSheet(isPresented: $showingActionSheet) {
            actionSheet
        }
        .alert("Error", isPresented: .constant(appDeletionManager.errorMessage != nil)) {
            Button("OK") {
                appDeletionManager.clearError()
            }
        } message: {
            Text(appDeletionManager.errorMessage ?? "")
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("App Deletions")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                if !appDeletionManager.deletedApps.isEmpty {
                    Text("\(appDeletionManager.deletedApps.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.purple)
                        .clipShape(Circle())
                }
            }
            
            Text("Manage apps that have been deleted from your child's device")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading deleted apps...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "app.badge.minus")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Deleted Apps")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("When your child deletes apps that you're monitoring, they'll appear here for you to manage.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var deletedAppsListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(appDeletionManager.deletedApps) { deletedApp in
                    DeletedAppCard(
                        deletedApp: deletedApp,
                        onTap: {
                            selectedDeletion = deletedApp
                            showingActionSheet = true
                        }
                    )
                }
            }
            .padding()
        }
    }
    
    private var actionSheet: ActionSheet {
        guard let deletedApp = selectedDeletion else {
            return ActionSheet(title: Text(""), buttons: [.cancel()])
        }
        
        return ActionSheet(
            title: Text(deletedApp.appName),
            message: Text("This app was deleted from your child's device on \(deletedApp.formattedDeletedAt)"),
            buttons: [
                .default(Text("Restore to Monitoring")) {
                    Task {
                        await appDeletionManager.restoreAppToMonitoring(deletedApp)
                    }
                },
                .destructive(Text("Remove from Monitoring")) {
                    Task {
                        await appDeletionManager.removeAppFromMonitoring(deletedApp)
                    }
                },
                .cancel()
            ]
        )
    }
}

// MARK: - Deleted App Card
struct DeletedAppCard: View {
    let deletedApp: DeletedApp
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // App Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "app.badge.minus")
                        .foregroundColor(.purple)
                        .font(.title2)
                }
                
                // App Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(deletedApp.appName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Deleted \(deletedApp.formattedDeletedAt)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if deletedApp.wasMonitored {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            
                            Text("Was being monitored")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Spacer()
                
                // Status
                VStack(alignment: .trailing, spacing: 4) {
                    if deletedApp.isProcessed {
                        Text("Processed")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("Pending")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(deletedApp.isProcessed ? Color.clear : Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    AppDeletionManagementView()
        .environmentObject(AuthenticationManager())
} 