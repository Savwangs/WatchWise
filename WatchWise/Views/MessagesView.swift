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
            setupMessaging()
        }
        .onDisappear {
            messagingManager.disconnect()
        }
        .alert("Error", isPresented: .constant(messagingManager.errorMessage != nil)) {
            Button("OK") {
                messagingManager.clearError()
            }
        } message: {
            Text(messagingManager.errorMessage ?? "")
        }
    }
    
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
        guard let currentUser = authManager.currentUser,
              let childId = selectedChildId ?? pairingManager.pairedChildren.first?.childUserId else {
            return
        }
        
        messagingManager.connect(parentId: currentUser.id, childId: childId)
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