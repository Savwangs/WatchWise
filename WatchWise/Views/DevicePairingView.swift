//
//  DevicePairingView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//

//When you're ready to remove the demo mode (before production), just delete the "Development Mode Section" and the skipPairingWithDemoData() function.

import SwiftUI
import FirebaseFirestore
import Foundation
import FirebaseAuth
import AVFoundation
import AudioToolbox

struct DevicePairingView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var pairingManager = PairingManager()
    @State private var pairCode = ""
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isSuccess = false
    @State private var showQRScanner = false
    @State private var showCameraPermissionAlert = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Top Navigation Bar
                HStack {
                    Spacer()
                    
                    Button("Sign Out") {
                        authManager.signOut()
                    }
                    .foregroundColor(.red)
                    .padding(.trailing)
                }
                .padding(.top, 10)
                
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("Connect to Your Child's Device")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                // Instructions
                VStack(alignment: .leading, spacing: 16) {
                    InstructionRow(
                        number: "1",
                        text: "Install the WatchWise Kids app on your child's iPhone"
                    )
                    
                    InstructionRow(
                        number: "2",
                        text: "Open that app and tap 'Generate Code'"
                    )
                    
                    InstructionRow(
                        number: "3",
                        text: "Scan the QR code or enter the 6-digit code below:"
                    )
                }
                .padding(.horizontal, 32)
                
                // QR Code Scanner Button
                VStack(spacing: 16) {
                    Button(action: {
                        checkCameraPermissionAndShowScanner()
                    }) {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                            Text("Scan QR Code")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                    }
                    
                    // Divider
                    HStack {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.gray.opacity(0.3))
                        
                        Text("OR")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                        
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.gray.opacity(0.3))
                    }
                }
                .padding(.horizontal, 32)
                
                // Code Input
                VStack(spacing: 16) {
                    TextField("Enter 6-digit code", text: $pairCode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .onChange(of: pairCode) { newValue in
                            // Limit to 6 digits and only numbers
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered.count > 6 {
                                pairCode = String(filtered.prefix(6))
                            } else {
                                pairCode = filtered
                            }
                        }
                    
                    Button(action: pairDevice) {
                        if pairingManager.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Pair Devices")
                                .font(.headline)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(pairCode.count == 6 && !pairingManager.isLoading ? Color.blue : Color.gray)
                    .cornerRadius(12)
                    .disabled(pairCode.count != 6 || pairingManager.isLoading)
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Privacy Note
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                    
                    Text("Your child's privacy is protected. We only collect screen time data that you can already see in iOS Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .navigationBarHidden(true)
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {
                if isSuccess {
                    // The ContentView will automatically navigate based on isDevicePaired
                }
            }
        } message: {
            Text(alertMessage)
        }
        .alert("Camera Permission Required", isPresented: $showCameraPermissionAlert) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel") { }
        } message: {
            Text("Camera access is required to scan QR codes. Please enable it in Settings.")
        }
        .sheet(isPresented: $showQRScanner) {
            QRCodeScannerView { scannedCode in
                pairCode = scannedCode
                showQRScanner = false
            }
        }
        .onChange(of: pairingManager.errorMessage) { errorMessage in
            if let error = errorMessage {
                alertTitle = "Pairing Failed"
                alertMessage = error
                isSuccess = false
                showAlert = true
            }
        }
        .onChange(of: pairingManager.successMessage) { successMessage in
            if let success = successMessage {
                alertTitle = "Success!"
                alertMessage = success
                isSuccess = true
                showAlert = true
            }
        }
    }
    
    private func checkCameraPermissionAndShowScanner() {
        print("🔍 Checking camera permission...")
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("✅ Camera authorized, showing scanner")
            showQRScanner = true
        case .notDetermined:
            print("⏳ Camera permission not determined, requesting...")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        print("✅ Camera permission granted, showing scanner")
                        self.showQRScanner = true
                    } else {
                        print("❌ Camera permission denied")
                        self.showCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            print("❌ Camera permission denied/restricted")
            showCameraPermissionAlert = true
        @unknown default:
            print("❌ Unknown camera permission status")
            showCameraPermissionAlert = true
        }
    }
    
    private func pairDevice() {
        guard let parentId = authManager.currentUser?.id else {
            alertTitle = "Authentication Error"
            alertMessage = "Please sign in again."
            isSuccess = false
            showAlert = true
            return
        }
        
        Task {
            let result = await pairingManager.pairWithChild(
                code: pairCode,
                parentUserId: parentId
            )
            
            await MainActor.run {
                switch result {
                case .success(let pairingSuccess):
                    // Update the parent's device pairing status
                    authManager.updateDevicePairingStatus(isPaired: true)
                    
                    // DEMO DATA - START (Store demo data for parent dashboard)
                    UserDefaults.standard.set(pairingSuccess.childName, forKey: "demoChildName")
                    UserDefaults.standard.set(pairingSuccess.deviceName, forKey: "demoDeviceName")
                    UserDefaults.standard.set(true, forKey: "demoParentDevicePaired")
                    
                    // Set the pairing completion flag for the child device to detect
                    print("🔗 Setting pairing completion flag for child device with code: \(pairCode)")
                    print("🔗 Pairing success - childName: \(pairingSuccess.childName), deviceName: \(pairingSuccess.deviceName)")
                    UserDefaults.standard.set(true, forKey: "demoChildPaired_\(pairCode)")
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "demoPairingTimestamp_\(pairCode)")
                    
                    // Verify the flag was set
                    let flagSet = UserDefaults.standard.bool(forKey: "demoChildPaired_\(pairCode)")
                    print("🔗 Verification - pairing flag set for \(pairCode): \(flagSet)")
                    
                    // Debug the pairing status
                    authManager.debugPairingStatus()
                    // DEMO DATA - END
                    
                    alertTitle = "Pairing Successful!"
                    alertMessage = "Successfully connected to \(pairingSuccess.childName)'s device. You can now monitor their screen time."
                    isSuccess = true
                    showAlert = true
                    
                case .failure:
                    // Error is handled by the onChange modifier above
                    break
                }
            }
        }
    }
}

struct InstructionRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

#Preview {
    DevicePairingView()
        .environmentObject(AuthenticationManager())
}

// MARK: - QR Code Scanner View

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let scanner = QRScannerViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }
    
    class Coordinator: NSObject, QRScannerViewControllerDelegate {
        let onCodeScanned: (String) -> Void
        
        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }
        
        func didScanCode(_ code: String) {
            onCodeScanned(code)
        }
    }
}

// MARK: - QR Scanner View Controller

protocol QRScannerViewControllerDelegate: AnyObject {
    func didScanCode(_ code: String)
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: QRScannerViewControllerDelegate?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }
    
    private func setupCamera() {
        print("📷 Setting up camera...")
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            print("❌ No video capture device available")
            return
        }
        
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            print("✅ Video input created successfully")
        } catch {
            print("❌ Failed to create video input: \(error)")
            return
        }
        
        captureSession = AVCaptureSession()
        
        if captureSession?.canAddInput(videoInput) == true {
            captureSession?.addInput(videoInput)
            print("✅ Video input added to session")
        } else {
            print("❌ Cannot add video input to session")
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession?.canAddOutput(metadataOutput) == true {
            captureSession?.addOutput(metadataOutput)
            print("✅ Metadata output added to session")
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
            print("✅ QR code detection enabled")
        } else {
            print("❌ Cannot add metadata output to session")
            return
        }
        
        print("✅ Camera setup completed successfully")
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor.black
        
        // Preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer?.frame = view.layer.bounds
        previewLayer?.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer!)
        
        // Close button
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Cancel", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        closeButton.layer.cornerRadius = 8
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 80),
            closeButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // Instructions label
        let instructionsLabel = UILabel()
        instructionsLabel.text = "Position the QR code within the frame"
        instructionsLabel.textColor = .white
        instructionsLabel.textAlignment = .center
        instructionsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        instructionsLabel.layer.cornerRadius = 8
        instructionsLabel.font = UIFont.systemFont(ofSize: 16)
        instructionsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionsLabel)
        
        NSLayoutConstraint.activate([
            instructionsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionsLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            instructionsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            instructionsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }
    
    private func startSession() {
        print("🎬 Starting camera session...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
            print("✅ Camera session started")
        }
    }
    
    private func stopSession() {
        print("⏹️ Stopping camera session...")
        captureSession?.stopRunning()
        print("✅ Camera session stopped")
    }
    
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    // MARK: - AVCaptureMetadataOutputObjectsDelegate
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            
            // Validate that it's a 6-digit code
            if stringValue.count == 6 && stringValue.allSatisfy({ $0.isNumber }) {
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                delegate?.didScanCode(stringValue)
            }
        }
    }
}
