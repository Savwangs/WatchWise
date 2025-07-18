//
//  WatchWiseApp.swift
//  WatchWise
//
//  Created by Savir Wangoo on 6/2/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure Firebase
        FirebaseApp.configure()
        
        // Initialize Firebase Manager
        let firebaseManager = FirebaseManager.shared
        firebaseManager.configureFirebase()
        
        // Test Firebase connection
        firebaseManager.testFirebaseConnection { success in
            if success {
                print("✅ Firebase connection test passed")
            } else {
                print("❌ Firebase connection test failed")
            }
        }
        
        // Validate Firebase collections
        firebaseManager.validateCollections { results in
            print("📊 Firebase collections validation:")
            for (collection, isValid) in results {
                print("  \(collection): \(isValid ? "✅" : "❌")")
            }
        }
        
        // Configure Firebase Messaging
        Messaging.messaging().delegate = self
        
        // Configure background tasks
        configureBackgroundTasks()
        
        print("🚀 WatchWise App initialized successfully")
        return true
    }
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        print("📱 Received device token")
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("🔥 Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    private func configureBackgroundTasks() {
        #if targetEnvironment(simulator)
        // Skip background task registration in simulator
        print("⚠️ Skipping background task registration in simulator")
        return
        #else
        // Register heartbeat background task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.watchwise.heartbeat", using: nil) { task in
            print("🔄 Background heartbeat task received in AppDelegate")
            let activityManager = ActivityMonitoringManager.shared
            activityManager.handleBackgroundHeartbeat(task: task as! BGProcessingTask)
        }
        
        // Register monitoring background task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.watchwise.monitoring", using: nil) { task in
            print("🔄 Background monitoring task received in AppDelegate")
            let activityManager = ActivityMonitoringManager.shared
            activityManager.handleBackgroundMonitoring(task: task as! BGProcessingTask)
        }
        
        print("✅ Background tasks configured in AppDelegate")
        #endif
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("📝 FCM registration token: \(fcmToken ?? "nil")")
        
        // Store the token for the current user
        if let token = fcmToken,
           let userId = Auth.auth().currentUser?.uid {
            let userData = ["deviceToken": token]
            FirebaseManager.shared.usersCollection.document(userId).updateData(userData) { error in
                if let error = error {
                    print("🔥 Error updating device token: \(error)")
                } else {
                    print("✅ Device token updated successfully")
                }
            }
        }
    }
}



@main
struct WatchWiseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var databaseManager = DatabaseManager.shared
    @StateObject private var activityMonitoringManager = ActivityMonitoringManager.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(databaseManager)
                .environmentObject(activityMonitoringManager)
                .environmentObject(networkMonitor)
                .onAppear {
                    setupAppearance()
                    setupActivityMonitoring()
                }
        }
    }
    
    private func setupActivityMonitoring() {
        // Start activity monitoring for child devices
        if let currentUser = Auth.auth().currentUser {
            // Check if this is a child device (you can add logic to determine user type)
            // For now, we'll start monitoring for all users
            activityMonitoringManager.startMonitoring()
            
            // Start background processing
            #if !targetEnvironment(simulator)
            BackgroundTaskManager.shared.startBackgroundProcessing()
            #endif
        }
    }
    
    private func setupAppearance() {
        // Configure app-wide appearance
        UINavigationBar.appearance().tintColor = .systemBlue
        UITabBar.appearance().tintColor = .systemBlue
    }
}

extension Notification.Name {
    static let navigateToMessages = Notification.Name("navigateToMessages")
    static let navigateToDashboard = Notification.Name("navigateToDashboard")
}
