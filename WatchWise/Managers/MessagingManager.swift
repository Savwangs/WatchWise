//
//  MessagingManager.swift
//  WatchWise
//
//  Created by Savir Wangoo on 7/2/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class MessagingManager: ObservableObject {
    static let shared = MessagingManager()
    
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isConnected = false
    
    private let db = Firestore.firestore()
    private var messageListener: ListenerRegistration?
    private var typingListener: ListenerRegistration?
    private var lastMessageTimestamp: Timestamp?
    
    // Typing indicators
    @Published var isParentTyping = false
    @Published var isChildTyping = false
    
    private init() {}
    
    deinit {
        Task { @MainActor in
            disconnect()
        }
    }
    
    // MARK: - Connection Management
    
    func connect(parentId: String, childId: String) {
        print("🔌 Attempting to connect to messaging for parent: \(parentId), child: \(childId)")
        
        disconnect() // Clean up any existing connections
        
        isLoading = true
        errorMessage = nil
        
        // Set up real-time message listener
        setupMessageListener(parentId: parentId, childId: childId)
        
        // Set up typing indicator listener
        setupTypingListener(parentId: parentId, childId: childId)
        
        isConnected = true
        isLoading = false
        
        print("✅ MessagingManager: Successfully connected to chat for parent \(parentId) and child \(childId)")
    }
    
    func disconnect() {
        messageListener?.remove()
        typingListener?.remove()
        messageListener = nil
        typingListener = nil
        isConnected = false
        messages.removeAll()
        
        print("💬 MessagingManager: Disconnected from chat")
    }
    
    // MARK: - Message Operations
    
    func sendMessage(_ text: String, from parentId: String, to childId: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        do {
            let message = Message(
                id: UUID().uuidString,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                senderId: parentId,
                receiverId: childId,
                timestamp: Date(),
                messageType: .text,
                isRead: false,
                senderType: .parent
            )
            
            // Save to Firebase
            try await saveMessageToFirebase(message)
            
            // Don't add to local messages - let the listener handle it
            // This prevents duplicate messages
            
            // Send notification to child
            await sendMessageNotification(message)
            
            print("💬 Sent message: \(text)")
            
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            print("❌ Error sending message: \(error)")
        }
    }
    
    func sendChildMessage(_ text: String, from childId: String, to parentId: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        do {
            let message = Message(
                id: UUID().uuidString,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                senderId: childId,
                receiverId: parentId,
                timestamp: Date(),
                messageType: .text,
                isRead: false,
                senderType: .child
            )
            
            // Save to Firebase
            try await saveMessageToFirebase(message)
            
            // Don't add to local messages - let the listener handle it
            // This prevents duplicate messages
            
            // Send notification to parent
            await sendMessageNotification(message)
            
            print("💬 Child sent message: \(text)")
            
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            print("❌ Error sending child message: \(error)")
        }
    }
    
    func markMessageAsRead(_ messageId: String) async {
        do {
            try await db.collection("messages")
                .document(messageId)
                .updateData([
                    "isRead": true,
                    "readAt": Timestamp()
                ])
            
            // Update local message
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index].isRead = true
                messages[index].readAt = Date()
            }
            
        } catch {
            print("❌ Error marking message as read: \(error)")
        }
    }
    
    func markAllMessagesAsRead(for userId: String) async {
        do {
            let batch = db.batch()
            
            let unreadMessages = messages.filter { 
                $0.receiverId == userId && !$0.isRead 
            }
            
            for message in unreadMessages {
                let messageRef = db.collection("messages").document(message.id)
                batch.updateData([
                    "isRead": true,
                    "readAt": Timestamp()
                ], forDocument: messageRef)
            }
            
            try await batch.commit()
            
            // Update local messages
            for index in messages.indices {
                if messages[index].receiverId == userId && !messages[index].isRead {
                    messages[index].isRead = true
                    messages[index].readAt = Date()
                }
            }
            
            print("✅ Marked \(unreadMessages.count) messages as read")
            
        } catch {
            print("❌ Error marking messages as read: \(error)")
        }
    }
    
    // MARK: - Typing Indicators
    
    func setTypingStatus(isTyping: Bool, userId: String, chatId: String) async {
        do {
            try await db.collection("typingIndicators")
                .document(chatId)
                .setData([
                    "isTyping": isTyping,
                    "userId": userId,
                    "timestamp": Timestamp()
                ], merge: true)
            
        } catch {
            print("❌ Error setting typing status: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func setupMessageListener(parentId: String, childId: String) {
        let chatId = getChatId(parentId: parentId, childId: childId)
        print("🔍 Setting up message listener for chatId: \(chatId)")
        
        messageListener = db.collection("messages")
            .whereField("chatId", isEqualTo: chatId)
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("❌ Error loading messages: \(error)")
                        
                        // Check if it's an index error
                        if error.localizedDescription.contains("index") {
                            self.errorMessage = "Database index is being created. Please wait a few minutes and try again."
                            print("🔧 Index error detected - user should wait for index to build")
                        } else {
                            self.errorMessage = "Failed to load messages: \(error.localizedDescription)"
                        }
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        print("📝 No messages found for chatId: \(chatId)")
                        self.messages = []
                        return
                    }
                    
                    let newMessages = documents.compactMap { document -> Message? in
                        do {
                            let message = try document.data(as: Message.self)
                            print("📝 Loaded message: \(message.text) from \(message.senderId)")
                            return message
                        } catch {
                            print("❌ Error parsing message document: \(error)")
                            return nil
                        }
                    }
                    
                    // Only update if we have new messages
                    if newMessages.count != self.messages.count {
                        self.messages = newMessages
                        print("📝 Loaded \(newMessages.count) messages for chatId: \(chatId)")
                    }
                }
            }
    }
    
    private func setupTypingListener(parentId: String, childId: String) {
        let chatId = getChatId(parentId: parentId, childId: childId)
        
        typingListener = db.collection("typingIndicators")
            .document(chatId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("❌ Error loading typing indicators: \(error)")
                        return
                    }
                    
                    guard let data = snapshot?.data(),
                          let isTyping = data["isTyping"] as? Bool,
                          let typingUserId = data["userId"] as? String else {
                        self.isParentTyping = false
                        self.isChildTyping = false
                        return
                    }
                    
                    // Check if typing indicator is recent (within last 10 seconds)
                    if let timestamp = data["timestamp"] as? Timestamp {
                        let typingTime = timestamp.dateValue()
                        let isRecent = Date().timeIntervalSince(typingTime) < 10
                        
                        if isRecent && isTyping {
                            if typingUserId == parentId {
                                self.isParentTyping = true
                                self.isChildTyping = false
                            } else if typingUserId == childId {
                                self.isChildTyping = true
                                self.isParentTyping = false
                            }
                        } else {
                            self.isParentTyping = false
                            self.isChildTyping = false
                        }
                    }
                }
            }
    }
    
    private func saveMessageToFirebase(_ message: Message) async throws {
        let chatId = getChatId(parentId: message.senderId, childId: message.receiverId)
        
        let data: [String: Any] = [
            "id": message.id,
            "text": message.text,
            "senderId": message.senderId,
            "receiverId": message.receiverId,
            "chatId": chatId,
            "timestamp": Timestamp(date: message.timestamp),
            "messageType": message.messageType.rawValue,
            "isRead": message.isRead,
            "senderType": message.senderType.rawValue
        ]
        
        print("💾 Saving message to Firebase: \(message.text) with chatId: \(chatId)")
        
        try await db.collection("messages")
            .document(message.id)
            .setData(data)
        
        print("✅ Message saved successfully to Firebase")
    }
    
    private func sendMessageNotification(_ message: Message) async {
        do {
            let notificationData: [String: Any] = [
                "recipientId": message.receiverId,
                "type": "new_message",
                "title": message.senderType == .parent ? "Message from Parent" : "Message from Child",
                "message": message.text,
                "senderId": message.senderId,
                "messageId": message.id,
                "timestamp": Timestamp(),
                "isRead": false
            ]
            
            try await db.collection("notifications").addDocument(data: notificationData)
            
            print("🔔 Sent message notification")
            
        } catch {
            print("❌ Error sending message notification: \(error)")
        }
    }
    
    private func getChatId(parentId: String, childId: String) -> String {
        // Create a consistent chat ID by sorting the IDs
        let sortedIds = [parentId, childId].sorted()
        let chatId = "\(sortedIds[0])_\(sortedIds[1])"
        print("🔗 Generated chatId: \(chatId) from parentId: \(parentId), childId: \(childId)")
        return chatId
    }
    
    // MARK: - Utility Methods
    
    func getUnreadMessageCount(for userId: String) -> Int {
        return messages.filter { $0.receiverId == userId && !$0.isRead }.count
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    func getLastMessage() -> Message? {
        return messages.last
    }
}


