//
//  MessagesView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//

import SwiftUI
import FirebaseFirestore
import Foundation
import FirebaseFirestore

struct MessagesView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var messagingManager = MessagingManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    
    @State private var customMessage = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isLoading = false
    @State private var selectedMessageType: MessageType = .reminder
    @State private var pairedDevices: [ChildDevice] = []
    @State private var selectedDevice: ChildDevice?
    @State private var messageHistory: [MessageData] = []
    @State private var messageListener: ListenerRegistration?
    
    private let db = Firestore.firestore()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Device Selection (if multiple devices)
                    if pairedDevices.count > 1 {
                        deviceSelectionSection
                    }
                    
                    // Message History
                    if !messageHistory.isEmpty {
                        messageHistorySection
                    }
                    
                    // Preset Messages
                    presetMessagesSection
                    
                    // Custom Message
                    customMessageSection
                    
                    Spacer(minLength: 50)
                }
                .padding(.vertical)
            }
            .navigationBarHidden(true)
            .refreshable {
                await loadPairedDevices()
                await loadMessageHistory()
            }
        }
        .task {
            await setupMessaging()
        }
        .onAppear {
            setupNotificationObservers()
        }
        .onDisappear {
            messageListener?.remove()
            removeNotificationObservers()
        }
        .alert("Message Status", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - View Components
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Send a Quick Message")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Connection status indicator
                connectionStatusIndicator
            }
            
            Text("Send gentle reminders or encouragement to your child's device")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
    
    private var connectionStatusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(pairedDevices.isEmpty ? Color.red : Color.green)
                .frame(width: 8, height: 8)
            
            Text(pairedDevices.isEmpty ? "Not Connected" : "Connected")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var deviceSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Send to Device")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(pairedDevices) { device in
                        DeviceSelectionCard(
                            device: device,
                            isSelected: selectedDevice?.id == device.id,
                            onSelect: { selectedDevice = device }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var messageHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Messages")
                    .font(.headline)
                Spacer()
                Button("Clear All") {
                    clearMessageHistory()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .padding(.horizontal)
            
            LazyVStack(spacing: 8) {
                ForEach(messageHistory.prefix(5)) { message in
                    MessageHistoryCard(message: message)
                }
            }
        }
    }
    
    private var presetMessagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Messages")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            
            // Message Type Selector
            Picker("Message Type", selection: $selectedMessageType) {
                ForEach(MessageType.allCases.filter { $0 != .response }, id: \.self) { type in
                    Text(type.rawValue.capitalized)
                        .tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            LazyVStack(spacing: 8) {
                ForEach(getPresetMessages(for: selectedMessageType)) { message in
                    MessageCard(
                        message: message,
                        isLoading: isLoading,
                        onSend: { sendMessage(message.text, type: selectedMessageType) }
                    )
                }
            }
        }
    }
    
    private var customMessageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Custom Message")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            
            VStack(spacing: 12) {
                TextField("Type your message...", text: $customMessage, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                
                Button(action: { sendMessage(customMessage, type: .custom) }) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("Send Message")
                        }
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(customMessage.isEmpty || isLoading ? Color.gray : Color.blue)
                .cornerRadius(12)
                .disabled(customMessage.isEmpty || isLoading || selectedDevice == nil)
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Functions
    private func setupMessaging() async {
        await loadPairedDevices()
        
        if let userId = authManager.currentUser?.id {
            do {
                try await messagingManager.retrieveFCMToken(for: userId, deviceType: .parent)
                await loadMessageHistory()
                setupMessageListener()
            } catch {
                print("❌ Error setting up messaging: \(error)")
                await MainActor.run {
                    alertMessage = "Failed to setup messaging: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func loadPairedDevices() async {
        guard let parentId = authManager.currentUser?.id else { return }
        
        do {
            let snapshot = try await db.collection("childDevices")
                .whereField("parentId", isEqualTo: parentId)
                .whereField("isActive", isEqualTo: true)
                .getDocuments()
            
            let devices = try snapshot.documents.compactMap { document -> ChildDevice? in
                try document.data(as: ChildDevice.self)
            }
            
            await MainActor.run {
                self.pairedDevices = devices
                if self.selectedDevice == nil && !devices.isEmpty {
                    self.selectedDevice = devices.first
                }
            }
            
        } catch {
            print("❌ Error loading paired devices: \(error)")
            await MainActor.run {
                alertMessage = "Failed to load paired devices"
                showAlert = true
            }
        }
    }
    
    private func loadMessageHistory() async {
        guard let device = selectedDevice,
              let userId = authManager.currentUser?.id else { return }
        
        do {
            let messages = try await messagingManager.getMessageHistory(for: userId, deviceId: device.id ?? "")
            await MainActor.run {
                self.messageHistory = messages
            }
        } catch {
            print("❌ Error loading message history: \(error)")
        }
    }
    
    private func setupMessageListener() {
        guard let device = selectedDevice else { return }
        
        messageListener?.remove()
        messageListener = messagingManager.listenForMessages(childDeviceId: device.id ?? "") { messages in
            self.messageHistory = messages
        }
    }
    
    private func sendMessage(_ messageText: String, type: MessageType) {
        guard let parentId = authManager.currentUser?.id,
              let device = selectedDevice else {
            alertMessage = "Please select a device to send message to"
            showAlert = true
            return
        }
        
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Please enter a message"
            showAlert = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                try await messagingManager.sendMessageToChild(
                    parentId: parentId,
                    childDeviceId: device.id ?? "",
                    message: messageText,
                    messageType: type
                )
                
                await MainActor.run {
                    isLoading = false
                    alertMessage = "Message sent successfully!"
                    showAlert = true
                    if type == .custom {
                        customMessage = ""
                    }
                }
                
                // Refresh message history
                await loadMessageHistory()
                
            } catch {
                await MainActor.run {
                    isLoading = false
                    alertMessage = "Failed to send message: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func clearMessageHistory() {
        messageHistory.removeAll()
        notificationManager.clearBadge()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .notificationReplyTapped,
            object: nil,
            queue: .main
        ) { notification in
            if let messageId = notification.userInfo?["messageId"] as? String {
                // Handle reply action - could navigate to specific message or show reply interface
                print("Reply tapped for message: \(messageId)")
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .messageReceived,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await loadMessageHistory()
            }
        }
    }
    
    private func removeNotificationObservers() {
        NotificationCenter.default.removeObserver(self, name: .notificationReplyTapped, object: nil)
        NotificationCenter.default.removeObserver(self, name: .messageReceived, object: nil)
    }
    
    private func getPresetMessages(for type: MessageType) -> [QuickMessage] {
        switch type {
        case .reminder:
            return QuickMessage.reminderMessages
        case .encouragement:
            return QuickMessage.encouragementMessages
        case .warning:
            return QuickMessage.warningMessages
        default:
            return QuickMessage.presetMessages
        }
    }
}

// MARK: - Supporting Views
struct DeviceSelectionCard: View {
    let device: ChildDevice
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone")
                .font(.title2)
                .foregroundColor(isSelected ? .white : .blue)
            
            Text(device.deviceName ?? "Unknown Device")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .lineLimit(1)
        }
        .frame(width: 80, height: 60)
        .background(isSelected ? Color.blue : Color(.systemGray6))
        .cornerRadius(12)
        .onTapGesture {
            onSelect()
        }
    }
}

struct MessageHistoryCard: View {
    let message: MessageData
    
    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Circle()
                    .fill(message.isDelivered ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message.message)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                HStack {
                    Text(message.messageType.rawValue.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    Text(message.timestamp.dateValue(), style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack {
                Image(systemName: message.isRead ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(message.isRead ? .green : .gray)
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct MessageCard: View {
    let message: QuickMessage
    let isLoading: Bool
    let onSend: () -> Void
    
    var body: some View {
        HStack {
            Text(message.emoji)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            Button(action: onSend) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                }
            }
            .disabled(isLoading)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Extended QuickMessage
extension QuickMessage {
    static let reminderMessages = [
        QuickMessage(text: "I see you've been on TikTok for a while, take a break?", emoji: "⏰"),
        QuickMessage(text: "Remember our screen time agreement - time for a break!", emoji: "📱"),
        QuickMessage(text: "Morning! Let's start the day screen-free for 30 minutes.", emoji: "🌅"),
        QuickMessage(text: "It's getting late - time to put the phone away for bed.", emoji: "🌙")
    ]
    
    static let encouragementMessages = [
        QuickMessage(text: "Doing great today! Screen time is looking healthy 👏", emoji: "🎉"),
        QuickMessage(text: "I'm proud of how you're managing your screen time!", emoji: "⭐"),
        QuickMessage(text: "You've been so good with breaks today - keep it up!", emoji: "💪"),
        QuickMessage(text: "Love seeing you balance screen time and other activities!", emoji: "🌟")
    ]
    
    static let warningMessages = [
        QuickMessage(text: "You've reached your daily limit for this app.", emoji: "⚠️"),
        QuickMessage(text: "Time to take a longer break from screens.", emoji: "🚫"),
        QuickMessage(text: "We agreed on limits - please respect our agreement.", emoji: "⏱️"),
        QuickMessage(text: "Let's talk about your screen time when you're free.", emoji: "💭")
    ]
}


#Preview {
    MessagesView()
        .environmentObject(AuthenticationManager())
}
