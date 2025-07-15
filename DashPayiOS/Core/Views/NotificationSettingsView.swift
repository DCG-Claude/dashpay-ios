import Foundation
import SwiftUI

// MARK: - Notification Settings View

struct NotificationSettingsView: View {
    @StateObject private var notificationService = LocalNotificationService.shared
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Notification Settings")) {
                    HStack {
                        Text("Push Notifications")
                        Spacer()
                        switch notificationService.authorizationStatus {
                        case .authorized:
                            Text("Enabled")
                                .foregroundColor(.green)
                        case .denied:
                            Text("Disabled")
                                .foregroundColor(.red)
                        case .notDetermined:
                            Text("Not Set")
                                .foregroundColor(.orange)
                        case .provisional:
                            Text("Provisional")
                                .foregroundColor(.orange)
                        case .ephemeral:
                            Text("Ephemeral")
                                .foregroundColor(.orange)
                        @unknown default:
                            Text("Unknown")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    if notificationService.authorizationStatus == .denied {
                        Button("Open Settings") {
                            notificationService.openNotificationSettings()
                        }
                    } else if notificationService.authorizationStatus == .notDetermined {
                        Button("Enable Notifications") {
                            Task {
                                await notificationService.requestAuthorization()
                            }
                        }
                    }
                }
                
                Section(header: Text("Notification Types")) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                        Text("Funds Received")
                        Spacer()
                        Text(notificationService.isEnabled ? "On" : "Off")
                            .foregroundColor(notificationService.isEnabled ? .green : .gray)
                    }
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                        Text("Transaction Confirmed")
                        Spacer()
                        Text(notificationService.isEnabled ? "On" : "Off")
                            .foregroundColor(notificationService.isEnabled ? .green : .gray)
                    }
                    
                    HStack {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundColor(.orange)
                        Text("Sync Completed")
                        Spacer()
                        Text(notificationService.isEnabled ? "On" : "Off")
                            .foregroundColor(notificationService.isEnabled ? .green : .gray)
                    }
                }
                
                Section(header: Text("Actions")) {
                    Button("Clear All Notifications") {
                        Task {
                            await notificationService.clearAllNotifications()
                        }
                    }
                    .foregroundColor(.red)
                    
                    Button("Reset Badge Count") {
                        Task {
                            await notificationService.setBadgeCount(0)
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
        }
    }
}