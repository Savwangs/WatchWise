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
import UserNotifications
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
        
        // Request notification permissions
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermissions()
        
        // Configure background tasks
        configureBackgroundTasks()
        
        print("🚀 WatchWise App initialized successfully")
        return true
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("✅ Notification permissions granted")
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    print("❌ Notification permissions denied: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
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

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification tap
        let userInfo = response.notification.request.content.userInfo
        print("📬 Notification tapped: \(userInfo)")
        
        // Handle deep linking based on notification data
        if let messageType = userInfo["type"] as? String {
            switch messageType {
            case "parent_message":
                // Navigate to messages screen
                NotificationCenter.default.post(name: .navigateToMessages, object: nil)
            case "screen_time_alert":
                // Navigate to dashboard
                NotificationCenter.default.post(name: .navigateToDashboard, object: nil)
            default:
                break
            }
        }
        
        completionHandler()
    }
}

@main
struct WatchWiseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var databaseManager = DatabaseManager.shared
    @StateObject private var activityMonitoringManager = ActivityMonitoringManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(databaseManager)
                .environmentObject(activityMonitoringManager)
                .environmentObject(notificationManager)
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
            notificationManager.connect(userId: currentUser.uid)
            
            // Start background processing
            BackgroundTaskManager.shared.startBackgroundProcessing()
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
