//
//  DeviceManagementView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/7/25.
//

import SwiftUI
import FirebaseFirestore

struct DeviceManagementView: View {
    @StateObject private var pairingManager = PairingManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var showingUnlinkAlert = false
    @State private var deviceToUnlink: PairedChildDevice?
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var showingAddDevice = false
    
    var filteredDevices: [PairedChildDevice] {
        if searchText.isEmpty {
            return pairingManager.pairedChildren
        } else {
            return pairingManager.pairedChildren.filter { device in
                device.childName.localizedCaseInsensitiveContains(searchText) ||
                device.deviceName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with stats
                DeviceStatsHeader(pairedDevices: pairingManager.pairedChildren)
                
                // Search bar
                SearchBar(text: $searchText, placeholder: "Search devices...")
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                
                if isLoading {
                    Spacer()
                    ProgressView("Loading devices...")
                        .progressViewStyle(CircularProgressViewStyle())
                    Spacer()
                } else if pairingManager.pairedChildren.isEmpty {
                    EmptyStateView()
                } else {
                    // Device list
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredDevices) { device in
                                DeviceCard(
                                    device: device,
                                    onUnlink: {
                                        deviceToUnlink = device
                                        showingUnlinkAlert = true
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                    .refreshable {
                        await refreshDevices()
                    }
                }
            }
            .navigationTitle("Device Management")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddDevice = true
                    }) {
                        HStack(spacing: 4) {
                            Text("Add Device")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                        .foregroundColor(.blue)
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        Task {
                            await refreshDevices()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                }
            }
            .alert("Unlink Device", isPresented: $showingUnlinkAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Unlink", role: .destructive) {
                    if let device = deviceToUnlink {
                        Task {
                            await unlinkDevice(device)
                        }
                    }
                }
            } message: {
                if let device = deviceToUnlink {
                    Text("Are you sure you want to unlink \(device.childName)'s device? This will remove all monitoring and communication features.")
                }
            }
            .sheet(isPresented: $showingAddDevice) {
                DevicePairingView()
            }
            .onAppear {
                Task {
                    await loadDevices()
                }
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
                Task {
                    await pairingManager.loadPairedChildren()
                }
            }
        }
    }
    
    private func loadDevices() async {
        isLoading = true
        await pairingManager.loadPairedChildren()
        isLoading = false
    }
    
    private func refreshDevices() async {
        await pairingManager.loadPairedChildren()
    }
    
    private func unlinkDevice(_ device: PairedChildDevice) async {
        isLoading = true
        
        let result = await pairingManager.unpairChild(relationshipId: device.id)
        
        await MainActor.run {
            isLoading = false
            
            switch result {
            case .success:
                notificationManager.scheduleLocalNotification(
                    title: "Device Unlinked",
                    body: "\(device.childName)'s device has been successfully unlinked.",
                    timeInterval: 1
                )
                
            case .failure(let error):
                notificationManager.scheduleLocalNotification(
                    title: "Unlink Failed",
                    body: "Failed to unlink \(device.childName)'s device: \(error.localizedDescription)",
                    timeInterval: 1
                )
            }
        }
    }
}

// MARK: - Supporting Views

struct DeviceStatsHeader: View {
    let pairedDevices: [PairedChildDevice]
    
    private var onlineCount: Int {
        pairedDevices.filter { $0.isOnline }.count
    }
    
    private var offlineCount: Int {
        pairedDevices.filter { !$0.isOnline }.count
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(pairedDevices.count)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                    
                    Text(pairedDevices.count == 1 ? "Connected Device" : "Connected Devices")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
            }
            
            HStack(spacing: 20) {
                StatusIndicator(
                    title: "Online",
                    count: onlineCount,
                    color: .green,
                    icon: "wifi"
                )
                
                StatusIndicator(
                    title: "Offline",
                    count: offlineCount,
                    color: .gray,
                    icon: "wifi.slash"
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .padding(.horizontal)
    }
}

struct StatusIndicator: View {
    let title: String
    let count: Int
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 14, weight: .medium))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct DeviceCard: View {
    let device: PairedChildDevice
    let onUnlink: () -> Void
    
    @State private var showingDeviceDetails = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(device.isOnline ? Color.green : Color.gray)
                        .frame(width: 12, height: 12)
                    
                    Image(systemName: "iphone")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.childName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(device.deviceName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                                            HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(device.isOnline ? Color.green : Color.gray)
                                    .frame(width: 6, height: 6)
                                
                                Text(device.connectionStatus)
                                    .font(.caption)
                                    .foregroundColor(device.isOnline ? .green : .gray)
                            }
                            
                            if device.missedHeartbeats > 0 {
                                Text("\(device.missedHeartbeats) missed")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: {
                        showingDeviceDetails = true
                    }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.system(size: 18))
                    }
                    
                    Button(action: onUnlink) {
                        HStack(spacing: 4) {
                            Image(systemName: "link.badge.minus")
                                .foregroundColor(.white)
                                .font(.system(size: 14, weight: .medium))
                            Text("Unlink")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .cornerRadius(6)
                    }
                }
            }
            .padding()
            
            Divider()
                .padding(.horizontal)
            
            HStack(spacing: 20) {
                QuickActionButton(
                    title: "Message",
                    icon: "message",
                    color: .blue
                ) {
                    // Navigate to messages
                }
                
                QuickActionButton(
                    title: "Activity",
                    icon: "chart.bar",
                    color: .green
                ) {
                    // Navigate to activity
                }
                
                QuickActionButton(
                    title: "Settings",
                    icon: "gearshape",
                    color: .orange
                ) {
                    // Navigate to device settings
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .sheet(isPresented: $showingDeviceDetails) {
            DeviceDetailsView(device: device)
        }
    }
    
    private func formatLastSyncTime(_ timestamp: Timestamp) -> String {
        let date = timestamp.dateValue()
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "Just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m ago"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days)d ago"
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("No Devices Connected")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Add a child's device to start monitoring their screen time and communicating with them.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button(action: {
                // This will be handled by the parent view
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Device")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(8)
            }
        }
        .padding()
    }
}

struct DeviceDetailsView: View {
    let device: PairedChildDevice
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "iphone")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        VStack(spacing: 4) {
                            Text(device.childName)
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text(device.deviceName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    
                    DeviceStatusSection(device: device)
                    ConnectionInfoSection(device: device)
                    QuickActionsSection()
                }
                .padding()
            }
            .navigationTitle("Device Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DeviceStatusSection: View {
    let device: PairedChildDevice
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device Status")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 8) {
                StatusRow(
                    title: "Connection Status",
                    value: device.isOnline ? "Online" : "Offline",
                    color: device.isOnline ? .green : .red
                )
                
                StatusRow(
                    title: "Paired Since",
                    value: formatDate(device.pairedAt),
                    color: .blue
                )
                
                StatusRow(
                    title: "Last Sync",
                    value: formatDate(device.lastSyncAt),
                    color: .orange
                )
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private func formatDate(_ timestamp: Timestamp) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp.dateValue())
    }
}

struct StatusRow: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .foregroundColor(color)
                .fontWeight(.medium)
        }
    }
}

struct ConnectionInfoSection: View {
    let device: PairedChildDevice
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection Information")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 8) {
                InfoRow(title: "Pairing Code", value: device.pairCode)
                InfoRow(title: "Relationship ID", value: device.id)
                InfoRow(title: "Child User ID", value: device.childUserId)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}

struct QuickActionsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .padding(.horizontal)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ActionCard(
                    title: "Send Message",
                    subtitle: "Communicate with child",
                    icon: "message",
                    color: .blue
                )
                
                ActionCard(
                    title: "View Activity",
                    subtitle: "Screen time & usage",
                    icon: "chart.bar",
                    color: .green
                )
                
                ActionCard(
                    title: "Device Settings",
                    subtitle: "Configure limits",
                    icon: "gearshape",
                    color: .orange
                )
                
                ActionCard(
                    title: "Unlink Device",
                    subtitle: "Remove connection",
                    icon: "link.badge.minus",
                    color: .red
                )
            }
        }
    }
}

struct ActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    DeviceManagementView()
} 