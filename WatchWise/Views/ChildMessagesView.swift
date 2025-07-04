//
//  ChildMessagesView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 7/2/25.
//

import SwiftUI
import FirebaseFirestore
import Foundation

struct ChildMessagesView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var messagingManager = MessagingManager.shared
    @StateObject private var pairingManager = PairingManager.shared
    
    @State private var messageText = ""
    @State private var selectedParentId: String?
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
            
            // Parent selector (if multiple parents)
            if !pairingManager.pairedChildren.isEmpty {
                HStack {
                    Text("Chat with:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Select Parent", selection: $selectedParentId) {
                        ForEach(pairingManager.pairedChildren, id: \.parentId) { child in
                            Text("Parent") // For child users, we show "Parent" since we don't have parent names
                                .tag(Optional(child.parentId))
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
            
            Text("Your parent will send you messages here. You can reply to them!")
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
                        ChildMessageBubble(
                            message: message,
                            isFromCurrentUser: message.senderId == authManager.currentUser?.id
                        )
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
            if messagingManager.isParentTyping {
                HStack {
                    Text("Parent is typing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            } else if messagingManager.isChildTyping {
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
                        .background(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.green)
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
              let parentId = selectedParentId ?? pairingManager.pairedChildren.first?.parentId else {
            return
        }
        
        messagingManager.connect(parentId: parentId, childId: currentUser.id)
    }
    
    private func sendMessage() {
        guard let currentUser = authManager.currentUser,
              let parentId = selectedParentId ?? pairingManager.pairedChildren.first?.parentId,
              !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        messageText = ""
        
        Task {
            await messagingManager.sendChildMessage(message, from: currentUser.id, to: parentId)
        }
        
        // Stop typing indicator
        stopTyping()
    }
    
    private func handleTyping() {
        guard let currentUser = authManager.currentUser,
              let parentId = selectedParentId ?? pairingManager.pairedChildren.first?.parentId else {
            return
        }
        
        // Start typing indicator
        if !isTyping {
            isTyping = true
            Task {
                await messagingManager.setTypingStatus(isTyping: true, userId: currentUser.id, chatId: getChatId(parentId: parentId, childId: currentUser.id))
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
              let parentId = selectedParentId ?? pairingManager.pairedChildren.first?.parentId else {
            return
        }
        
        isTyping = false
        Task {
            await messagingManager.setTypingStatus(isTyping: false, userId: currentUser.id, chatId: getChatId(parentId: parentId, childId: currentUser.id))
        }
    }
    
    private func getChatId(parentId: String, childId: String) -> String {
        let sortedIds = [parentId, childId].sorted()
        return "\(sortedIds[0])_\(sortedIds[1])"
    }
}

// MARK: - Child Message Bubble View
struct ChildMessageBubble: View {
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
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    
                    HStack(spacing: 4) {
                        Text(message.formattedTimestamp)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if message.isRead {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
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
                        .background(Color.blue)
                        .foregroundColor(.white)
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

#Preview {
    ChildMessagesView()
        .environmentObject(AuthenticationManager())
}
