//
//  MessagesView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 7/2/25.
//

import SwiftUI
import FirebaseFirestore
import Foundation

struct MessagesView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var messagingManager = MessagingManager.shared
    @StateObject private var pairingManager = PairingManager.shared
    
    @State private var messageText = ""
    @State private var selectedChildId: String?
    @State private var isTyping = false
    @State private var typingTimer: Timer?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Quick Messages Section
                quickMessagesSection
                
                // Messages List
                if messagingManager.isLoading {
                    loadingView
                } else if messagingManager.messages.isEmpty {
                    emptyStateView
                } else {
                    messagesListView
                }
                
                // Typing Indicators
                typingIndicatorView
                
                // Message Input
                messageInputView
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            print("📱 Parent MessagesView appeared")
            setupMessaging()
        }
        .onDisappear {
            messagingManager.disconnect()
        }
        .alert("Error", isPresented: .constant(messagingManager.errorMessage != nil)) {
            Button("Retry") {
                messagingManager.clearError()
                setupMessaging()
            }
            Button("OK") {
                messagingManager.clearError()
            }
        } message: {
            Text(messagingManager.errorMessage ?? "")
        }
    }
    
    // MARK: - Sample Messages Data
    
    private let sampleMessages = [
        MessageCategory(
            title: "Encouragement",
            icon: "heart.fill",
            color: .green,
            messages: [
                "Great job on your homework!",
                "I'm so proud of you!",
                "You're doing amazing!",
                "Keep up the good work!",
                "You've got this!",
                "I believe in you!",
                "You're making great progress!",
                "Well done on your test!"
            ]
        ),
        MessageCategory(
            title: "Reminders",
            icon: "bell.fill",
            color: .blue,
            messages: [
                "Don't forget to do your homework",
                "Remember to clean your room",
                "Time to get ready for bed",
                "Don't forget your lunch",
                "Remember to brush your teeth",
                "Time to start your chores",
                "Don't forget to feed the pet",
                "Remember to pack your bag"
            ]
        ),
        MessageCategory(
            title: "Warnings",
            icon: "exclamationmark.triangle.fill",
            color: .orange,
            messages: [
                "You've been on your phone too long",
                "Please get off your device now",
                "Screen time limit reached",
                "You need to take a break",
                "Please focus on your work",
                "It's time to put the phone away",
                "You're over your daily limit",
                "Please respect the rules"
            ]
        ),
        MessageCategory(
            title: "Strict",
            icon: "hand.raised.fill",
            color: .red,
            messages: [
                "Put your phone away immediately",
                "You're grounded from devices",
                "No more screen time today",
                "I'm taking your phone away",
                "You've broken the rules",
                "This is your final warning",
                "No devices until tomorrow",
                "You need to earn back privileges"
            ]
        ),
        MessageCategory(
            title: "Care",
            icon: "heart.circle.fill",
            color: .purple,
            messages: [
                "How was your day?",
                "Are you feeling okay?",
                "Do you need help with anything?",
                "I'm here if you want to talk",
                "How are you doing?",
                "Is everything alright?",
                "Do you want to talk about it?",
                "I care about you"
            ]
        ),
        MessageCategory(
            title: "Fun",
            icon: "star.fill",
            color: .yellow,
            messages: [
                "Want to play a game?",
                "Let's do something fun together",
                "How about we watch a movie?",
                "Want to go for a walk?",
                "Let's bake some cookies!",
                "Want to play outside?",
                "How about a family game night?",
                "Let's have some fun!"
            ]
        )
    ]
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Messages")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Connection status
                HStack(spacing: 4) {
                    Circle()
                        .fill(messagingManager.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(messagingManager.isConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Child selector
            if !pairingManager.pairedChildren.isEmpty {
                HStack {
                    Text("Chat with:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Select Child", selection: $selectedChildId) {
                        ForEach(pairingManager.pairedChildren, id: \.childUserId) { child in
                            Text(child.childName)
                                .tag(Optional(child.childUserId))
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    private var quickMessagesSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Quick Messages")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("Tap to send")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(sampleMessages, id: \.title) { category in
                        QuickMessageCategoryView(category: category) { message in
                            sendQuickMessage(message)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading messages...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "message.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Messages Yet")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Start a conversation with your child by sending a message below.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var messagesListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messagingManager.messages) { message in
                        MessageBubble(message: message, isFromCurrentUser: message.senderId == authManager.currentUser?.id)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: messagingManager.messages.count) { _ in
                if let lastMessage = messagingManager.messages.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var typingIndicatorView: some View {
        Group {
            if messagingManager.isChildTyping {
                HStack {
                    Text("Child is typing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            } else if messagingManager.isParentTyping {
                HStack {
                    Spacer()
                    
                    Text("You are typing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private var messageInputView: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                TextField("Type a message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(1...4)
                    .onChange(of: messageText) { _ in
                        handleTyping()
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                        .clipShape(Circle())
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - Methods
    
    private func setupMessaging() {
        guard let currentUser = authManager.currentUser else {
            print("❌ Parent setupMessaging: No current user")
            return
        }
        
        let childId = selectedChildId ?? pairingManager.pairedChildren.first?.childUserId
        
        if let childId = childId {
            print("✅ Parent setupMessaging: Connecting with parentId: \(currentUser.id), childId: \(childId)")
            messagingManager.connect(parentId: currentUser.id, childId: childId)
        } else {
            print("❌ Parent setupMessaging: No child ID found")
            print("   - selectedChildId: \(selectedChildId ?? "nil")")
            print("   - pairedChildren count: \(pairingManager.pairedChildren.count)")
            if let firstChild = pairingManager.pairedChildren.first {
                print("   - first child childUserId: \(firstChild.childUserId)")
            }
        }
    }
    
    private func sendMessage() {
        guard let currentUser = authManager.currentUser,
              let childId = selectedChildId ?? pairingManager.pairedChildren.first?.childUserId,
              !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        messageText = ""
        
        Task {
            await messagingManager.sendMessage(message, from: currentUser.id, to: childId)
        }
        
        // Stop typing indicator
        stopTyping()
    }
    
    private func sendQuickMessage(_ message: String) {
        guard let currentUser = authManager.currentUser,
              let childId = selectedChildId ?? pairingManager.pairedChildren.first?.childUserId else {
            return
        }
        
        Task {
            await messagingManager.sendMessage(message, from: currentUser.id, to: childId)
        }
    }
    
    private func handleTyping() {
        guard let currentUser = authManager.currentUser,
              let childId = selectedChildId ?? pairingManager.pairedChildren.first?.childUserId else {
            return
        }
        
        // Start typing indicator
        if !isTyping {
            isTyping = true
            Task {
                await messagingManager.setTypingStatus(isTyping: true, userId: currentUser.id, chatId: getChatId(parentId: currentUser.id, childId: childId))
            }
        }
        
        // Reset typing timer
        typingTimer?.invalidate()
        typingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            stopTyping()
        }
    }
    
    private func stopTyping() {
        guard let currentUser = authManager.currentUser,
              let childId = selectedChildId ?? pairingManager.pairedChildren.first?.childUserId else {
            return
        }
        
        isTyping = false
        Task {
            await messagingManager.setTypingStatus(isTyping: false, userId: currentUser.id, chatId: getChatId(parentId: currentUser.id, childId: childId))
        }
    }
    
    private func getChatId(parentId: String, childId: String) -> String {
        let sortedIds = [parentId, childId].sorted()
        return "\(sortedIds[0])_\(sortedIds[1])"
    }
}

// MARK: - Message Bubble View
struct MessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool
    
    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer(minLength: 50)
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    
                    HStack(spacing: 4) {
                        Text(message.formattedTimestamp)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if message.isRead {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        } else {
                            Image(systemName: "checkmark.circle")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    
                    Text(message.formattedTimestamp)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer(minLength: 50)
            }
        }
    }
}

// MARK: - Supporting Data Structures

struct MessageCategory {
    let title: String
    let icon: String
    let color: Color
    let messages: [String]
}

// MARK: - Quick Message Views

struct QuickMessageCategoryView: View {
    let category: MessageCategory
    let onMessageSelected: (String) -> Void
    @State private var showingMessages = false
    
    var body: some View {
        Button(action: {
            showingMessages = true
        }) {
            VStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.title2)
                    .foregroundColor(category.color)
                
                Text(category.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 80, height: 80)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .sheet(isPresented: $showingMessages) {
            QuickMessageListView(category: category, onMessageSelected: onMessageSelected)
        }
    }
}

struct QuickMessageListView: View {
    let category: MessageCategory
    let onMessageSelected: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(category.messages, id: \.self) { message in
                    Button(action: {
                        onMessageSelected(message)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: category.icon)
                                .foregroundColor(category.color)
                                .frame(width: 24)
                            
                            Text(message)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "paperplane")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(category.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}