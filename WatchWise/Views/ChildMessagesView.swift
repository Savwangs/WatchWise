//
//  ChildMessagesView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/7/25.
//

import SwiftUI
import FirebaseFirestore

struct ChildMessagesView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var messages: [ChatMessage] = []
    @State private var newMessage = ""
    @State private var isLoading = true
    @State private var parentId: String?
    
    private let db = Firestore.firestore()
    
    var body: some View {
        NavigationStack {
            VStack {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Messages")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    
                    if let parentId = parentId {
                        Text("Chat with your parent")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Connect with your parent to start messaging")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                if isLoading {
                    Spacer()
                    ProgressView("Loading messages...")
                    Spacer()
                } else if parentId == nil {
                    // Not paired state
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "message.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Parent Connected")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Ask your parent to pair with your device to start receiving messages")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                } else {
                    // Messages list
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .onChange(of: messages.count) { _ in
                            // Auto-scroll to bottom when new message arrives
                            if let lastMessage = messages.last {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    // Message input
                    HStack(spacing: 12) {
                        TextField("Type a message...", text: $newMessage, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                        
                        Button(action: sendMessage) {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(newMessage.isEmpty ? Color.gray : Color.blue)
                                .clipShape(Circle())
                        }
                        .disabled(newMessage.isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            loadParentConnection()
        }
    }
    
    private func loadParentConnection() {
        guard let childId = authManager.currentUser?.id else {
            isLoading = false
            return
        }
        
        // Check if we're in demo mode first
        if UserDefaults.standard.bool(forKey: "demoMode") {
            // Demo mode - create fake parent ID and load demo messages
            parentId = "demo_parent_id"
            loadDemoMessages()
            isLoading = false
            return
        }
        
        // Look for child device record to find parent
        db.collection("childDevices")
            .whereField("childId", isEqualTo: childId) // Assuming you store childId in device records
            .whereField("isActive", isEqualTo: true)
            .limit(to: 1)
            .getDocuments { [self] snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Error loading parent connection: \(error)")
                        isLoading = false
                        return
                    }
                    
                    if let document = snapshot?.documents.first {
                        parentId = document.data()["parentId"] as? String
                        if parentId != nil {
                            loadMessages()
                        }
                    }
                    isLoading = false
                }
            }
    }
    
    private func loadMessages() {
        guard let childId = authManager.currentUser?.id,
              let parentId = parentId else { return }
        
        // Create conversation ID (consistent between parent and child)
        let conversationId = [parentId, childId].sorted().joined(separator: "_")
        
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [self] snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Error loading messages: \(error)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else { return }
                    
                    messages = documents.compactMap { doc in
                        try? doc.data(as: ChatMessage.self)
                    }
                }
            }
    }
    
    private func loadDemoMessages() {
        // Demo messages for testing
        messages = [
            ChatMessage(
                id: UUID().uuidString,
                senderId: "demo_parent_id",
                senderType: .parent,
                content: "Hi! How's your day going?",
                timestamp: Timestamp(date: Date().addingTimeInterval(-3600))
            ),
            ChatMessage(
                id: UUID().uuidString,
                senderId: authManager.currentUser?.id ?? "",
                senderType: .child,
                content: "Good! Just finished homework",
                timestamp: Timestamp(date: Date().addingTimeInterval(-1800))
            ),
            ChatMessage(
                id: UUID().uuidString,
                senderId: "demo_parent_id",
                senderType: .parent,
                content: "Great job! Don't forget to take breaks from the screen 😊",
                timestamp: Timestamp(date: Date().addingTimeInterval(-900))
            )
        ]
    }
    
    private func sendMessage() {
        guard !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let childId = authManager.currentUser?.id,
              let parentId = parentId else { return }
        
        let messageContent = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let conversationId = [parentId, childId].sorted().joined(separator: "_")
        
        let message = ChatMessage(
            id: UUID().uuidString,
            senderId: childId,
            senderType: .child,
            content: messageContent,
            timestamp: Timestamp()
        )
        
        // Clear input immediately for better UX
        newMessage = ""
        
        // Save to Firestore
        do {
            try db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document(message.id)
                .setData(from: message)
        } catch {
            print("Error sending message: \(error)")
            // Show error to user if needed
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var isFromChild: Bool {
        message.senderType == .child
    }
    
    var body: some View {
        HStack {
            if isFromChild {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: isFromChild ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(isFromChild ? Color.blue : Color(.systemGray5))
                    .foregroundColor(isFromChild ? .white : .primary)
                    .cornerRadius(18)
                
                Text(formatTime(message.timestamp.dateValue()))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            
            if !isFromChild {
                Spacer(minLength: 50)
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.timeStyle = .short
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }
}

#Preview {
    ChildMessagesView()
        .environmentObject(AuthenticationManager())
}
