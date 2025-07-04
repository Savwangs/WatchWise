//
//  NotificationsView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 7/2/25.
//

import SwiftUI
import FirebaseFirestore

struct NotificationsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var notificationManager = NotificationManager()
    @StateObject private var appDeletionManager = AppDeletionManager()
    
    @State private var selectedFilter: NotificationType?
    @State private var showingFilterSheet = false
    @State private var showingActionSheet = false
    @State private var selectedNotification: AppNotification?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Filter Bar
                filterBar
                
                // Notifications List
                if notificationManager.isLoading {
                    loadingView
                } else if filteredNotifications.isEmpty {
                    emptyStateView
                } else {
                    notificationsListView
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            setupNotifications()
        }
        .onDisappear {
            notificationManager.disconnect()
        }
        .sheet(isPresented: $showingFilterSheet) {
            filterSheet
        }
        .actionSheet(isPresented: $showingActionSheet) {
            actionSheet
        }
        .alert("Error", isPresented: .constant(notificationManager.errorMessage != nil)) {
            Button("OK") {
                notificationManager.clearError()
            }
        } message: {
            Text(notificationManager.errorMessage ?? "")
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredNotifications: [AppNotification] {
        if let filter = selectedFilter {
            return notificationManager.notifications.filter { $0.type == filter }
        }
        return notificationManager.notifications
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Notifications")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Unread count badge
                if notificationManager.unreadCount > 0 {
                    Text("\(notificationManager.unreadCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.red)
                        .clipShape(Circle())
                }
            }
            
            HStack {
                Text("\(filteredNotifications.count) notifications")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Filter") {
                    showingFilterSheet = true
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    private var filterBar: some View {
        HStack {
            if let filter = selectedFilter {
                HStack {
                    Image(systemName: filter.icon)
                        .foregroundColor(Color(filter.color))
                    
                    Text(filter.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Button(action: { selectedFilter = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(filter.color).opacity(0.1))
                .cornerRadius(16)
            }
            
            Spacer()
            
            if notificationManager.unreadCount > 0 {
                Button("Mark All Read") {
                    Task {
                        await notificationManager.markAllAsRead()
                    }
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading notifications...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Notifications")
                .font(.title3)
                .fontWeight(.medium)
            
            if selectedFilter != nil {
                Text("No notifications match your current filter.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("You're all caught up! New notifications will appear here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var notificationsListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredNotifications) { notification in
                    NotificationCard(
                        notification: notification,
                        onTap: {
                            selectedNotification = notification
                            showingActionSheet = true
                        },
                        onMarkRead: {
                            Task {
                                await notificationManager.markAsRead(notification.id)
                            }
                        }
                    )
                }
            }
            .padding()
        }
    }
    
    private var filterSheet: some View {
        NavigationStack {
            List {
                Section("Filter by Type") {
                    Button("All Notifications") {
                        selectedFilter = nil
                        showingFilterSheet = false
                    }
                    .foregroundColor(.primary)
                    
                    ForEach(NotificationType.allCases, id: \.self) { type in
                        Button(action: {
                            selectedFilter = type
                            showingFilterSheet = false
                        }) {
                            HStack {
                                Image(systemName: type.icon)
                                    .foregroundColor(Color(type.color))
                                    .frame(width: 20)
                                
                                Text(type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if selectedFilter == type {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingFilterSheet = false
                    }
                }
            }
        }
    }
    
    private var actionSheet: ActionSheet {
        ActionSheet(
            title: Text(selectedNotification?.title ?? ""),
            message: Text(selectedNotification?.message ?? ""),
            buttons: [
                .default(Text("Mark as Read")) {
                    if let notification = selectedNotification {
                        Task {
                            await notificationManager.markAsRead(notification.id)
                        }
                    }
                },
                .destructive(Text("Delete")) {
                    if let notification = selectedNotification {
                        Task {
                            await notificationManager.deleteNotification(notification.id)
                        }
                    }
                },
                .cancel()
            ]
        )
    }
    
    // MARK: - Methods
    
    private func setupNotifications() {
        guard let currentUser = authManager.currentUser else { return }
        
        notificationManager.setup()
        notificationManager.connect(userId: currentUser.id)
        appDeletionManager.loadDeletedApps()
    }
}

// MARK: - Notification Card View
struct NotificationCard: View {
    let notification: AppNotification
    let onTap: () -> Void
    let onMarkRead: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: notification.type.icon)
                    .font(.title2)
                    .foregroundColor(Color(notification.type.color))
                    .frame(width: 32, height: 32)
                    .background(Color(notification.type.color).opacity(0.1))
                    .clipShape(Circle())
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(notification.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if !notification.isRead {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                        }
                    }
                    
                    Text(notification.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack {
                        Text(notification.formattedTimestamp)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if !notification.isRead {
                            Button("Mark Read") {
                                onMarkRead()
                            }
                            .font(.caption2)
                            .foregroundColor(.blue)
                        }
                    }
                }
            }
            .padding()
            .background(notification.isRead ? Color(.systemGray6) : Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(notification.isRead ? Color.clear : Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
} 