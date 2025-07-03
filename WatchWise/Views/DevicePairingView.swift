//
//  DevicePairingView.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/7/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AVFoundation

struct DevicePairingView: View {
    @StateObject private var pairingManager = PairingManager.shared
    @State private var pairingCode = ""
    @State private var isScanning = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showQRScanner = false
    @State private var showManualEntry = false
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Pair with Child Device")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Connect to your child's device to start monitoring")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Pairing Options
                VStack(spacing: 20) {
                    // QR Code Scanner Button
                    Button(action: {
                        showQRScanner = true
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
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    
                    // Manual Code Entry Button
                    Button(action: {
                        showManualEntry = true
                    }) {
                        HStack {
                            Image(systemName: "keyboard")
                                .font(.title2)
                            Text("Enter Code Manually")
                                .font(.headline)
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 32)
                
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to pair:")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Ask your child to open the WatchWise app on their device")
                        Text("2. Have them generate a pairing code")
                        Text("3. Scan the QR code or enter the 6-digit code")
                        Text("4. The devices will be connected automatically")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Sign Out Button
                Button(action: signOut) {
                    Text("Sign Out")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
                .padding(.bottom, 20)
            }
            .padding(.top, 50)
            .navigationBarHidden(true)
            .alert("Pairing Result", isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showQRScanner) {
                QRCodeScannerView { code in
                    handlePairingCode(code)
                    showQRScanner = false
                }
            }
            .sheet(isPresented: $showManualEntry) {
                ManualCodeEntryView { code in
                    handlePairingCode(code)
                    showManualEntry = false
                }
            }
        }
    }
    
    private func handlePairingCode(_ code: String) {
        guard let currentUser = Auth.auth().currentUser else {
            alertMessage = "You must be logged in to pair devices"
            showAlert = true
            return
        }
        
        Task {
            let result = await pairingManager.pairWithChild(code: code, parentUserId: currentUser.uid)
            
            await MainActor.run {
                switch result {
                case .success(let pairingSuccess):
                    alertMessage = "Successfully paired with \(pairingSuccess.childName)'s device!"
                    showAlert = true
                    
                    // Update local authentication state to reflect pairing
                    authManager.updateDevicePairingStatus(isPaired: true)
                    
                    // Navigate to dashboard after successful pairing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        NotificationCenter.default.post(name: .navigateToDashboard, object: nil)
                    }
                    
                case .failure(let error):
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
    
    private func signOut() {
        authManager.signOut()
    }
}

// QR Code Scanner View
struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let scanner = QRScannerViewController()
        scanner.onCodeScanned = onCodeScanned
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var onCodeScanned: ((String) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        // Add a background color
        view.backgroundColor = .black
        
        // Check if we're in simulator
        #if targetEnvironment(simulator)
        setupSimulatorUI()
        #else
        setupCamera()
        #endif
    }
    
    private func setupSimulatorUI() {
        // For simulator, show photo library option
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
        
        let titleLabel = UILabel()
        titleLabel.text = "QR Code Scanner"
        titleLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = "In simulator, you can select a QR code image from your photo library"
        subtitleLabel.font = UIFont.systemFont(ofSize: 16)
        subtitleLabel.textColor = .lightGray
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        
        let photoButton = UIButton(type: .system)
        photoButton.setTitle("Select from Photo Library", for: .normal)
        photoButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        photoButton.backgroundColor = .systemBlue
        photoButton.setTitleColor(.white, for: .normal)
        photoButton.layer.cornerRadius = 12
        photoButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        photoButton.addTarget(self, action: #selector(selectFromPhotoLibrary), for: .touchUpInside)
        
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        cancelButton.setTitleColor(.lightGray, for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelScanning), for: .touchUpInside)
        
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(photoButton)
        stackView.addArrangedSubview(cancelButton)
    }
    
    @objc private func selectFromPhotoLibrary() {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        imagePicker.allowsEditing = false
        present(imagePicker, animated: true)
    }
    
    @objc private func cancelScanning() {
        dismiss(animated: true)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true) {
            if let image = info[.originalImage] as? UIImage {
                self.processQRCodeFromImage(image)
            }
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    
    private func processQRCodeFromImage(_ image: UIImage) {
        guard let ciImage = CIImage(image: image) else {
            showAlert(message: "Could not process the selected image")
            return
        }
        
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: ciImage) ?? []
        
        if let qrFeature = features.first as? CIQRCodeFeature,
           let stringValue = qrFeature.messageString {
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onCodeScanned?(stringValue)
        } else {
            showAlert(message: "No QR code found in the selected image")
        }
    }
    
    private func showAlert(message: String) {
        let alert = UIAlertController(title: "QR Code Scanner", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { 
            showAlert(message: "Camera not available")
            return 
        }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            showAlert(message: "Could not access camera")
            return
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            showAlert(message: "Could not add camera input")
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            showAlert(message: "Could not add metadata output")
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        // Add cancel button for camera view
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        cancelButton.layer.cornerRadius = 8
        cancelButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelScanning), for: .touchUpInside)
        view.addSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        
        captureSession.startRunning()
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onCodeScanned?(stringValue)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if (captureSession?.isRunning == false) {
            captureSession?.startRunning()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if (captureSession?.isRunning == true) {
            captureSession?.stopRunning()
        }
    }
}

// Manual Code Entry View
struct ManualCodeEntryView: View {
    @State private var code = ""
    @Environment(\.presentationMode) var presentationMode
    let onCodeEntered: (String) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Enter Pairing Code")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Enter the 6-digit code from your child's device")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                TextField("000000", text: $code)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 50)
                
                Button("Pair Device") {
                    if code.count == 6 {
                        onCodeEntered(code)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .disabled(code.count != 6)
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

#Preview {
    DevicePairingView()
        .environmentObject(AuthenticationManager())
} 