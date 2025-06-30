//
//  PairedDevicesView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/7/25.
//

import SwiftUI
import FirebaseFirestore

struct PairedDevicesView: View {
    @StateObject private var pairingManager = PairingManager()
    @State private var showUnpairAlert = false
    @State private var deviceToUnpair: PairedChildDevice?
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading devices...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if pairingManager.pairedChildren.isEmpty {
                    emptyStateView
                } else {
                    deviceListView
                }
            }
            .navigationTitle("Paired Devices")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadPairedDevices()
            }
            .refreshable {
                await loadPairedDevicesAsync()
            }
            .alert("Unpair Device", isPresented: $showUnpairAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Unpair", role: .destructive) {
                    if let device = deviceToUnpair {
                        unpairDevice(device)
                    }
                }
            } message: {
                if let device = deviceToUnpair {
                    Text("Are you sure you want to unpair \(device.childName)'s device? This will stop screen time monitoring for this device.")
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("No Paired Devices")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("You haven't paired any child devices yet. Pair a device to start monitoring screen time.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            NavigationLink(destination: DevicePairingView()) {
                Text("Pair a Device")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var deviceListView: some View {
        List {
            ForEach(pairingManager.pairedChildren) { device in
                DeviceRowView(device: device) {
                    deviceToUnpair = device
                    showUnpairAlert = true
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
    
    private func loadPairedDevices() {
        Task {
            await loadPairedDevicesAsync()
        }
    }
    
    private func loadPairedDevicesAsync() async {
        await pairingManager.loadPairedChildren()
        await MainActor.run {
            isLoading = false
        }
    }
    
    private func unpairDevice(_ device: PairedChildDevice) {
        Task {
            let result = await pairingManager.unpairChild(relationshipId: device.id)
            await MainActor.run {
                switch result {
                case .success:
                    // Device list will be automatically refreshed
                    print("✅ Successfully unpaired \(device.childName)'s device")
                case .failure(let error):
                    print("🔥 Failed to unpair device: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Device Row View

struct DeviceRowView: View {
    let device: PairedChildDevice
    let onUnpair: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Device Icon
            VStack {
                Image(systemName: "iphone")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                // Online Status Indicator
                Circle()
                    .fill(device.isOnline ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }
            
            // Device Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.childName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    // Online Status Text
                    Text(device.isOnline ? "Online" : "Offline")
                        .font(.caption)
                        .foregroundColor(device.isOnline ? .green : .secondary)
                }
                
                Text(device.deviceName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Paired \(formatDate(device.pairedAt.dateValue()))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Unpair Button
            Button(action: onUnpair) {
                Image(systemName: "link.badge.minus")
                    .foregroundColor(.red)
                    .font(.title3)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview

struct PairedDevicesView_Previews: PreviewProvider {
    static var previews: some View {
        PairedDevicesView()
            .environmentObject(AuthenticationManager())
    }
} 