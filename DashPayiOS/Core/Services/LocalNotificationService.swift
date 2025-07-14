import Foundation
import UserNotifications
import os.log
import SwiftUI
import UIKit
import SwiftDashCoreSDK

/// Service for managing local push notifications for transaction events
class LocalNotificationService: ObservableObject {
    static let shared = LocalNotificationService()
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var isEnabled = false
    
    private let logger = Logger(subsystem: "com.dash.wallet", category: "LocalNotificationService")
    private let notificationQueue = DispatchQueue(label: "com.dash.wallet.notifications", qos: .background)
    private let notificationOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.dash.wallet.notifications.operations"
        queue.qualityOfService = .background
        return queue
    }()
    private var observers: [NSObjectProtocol] = []
    
    private init() {
        setupNotificationObservers()
        Task {
            await checkAuthorizationStatus()
        }
    }
    
    deinit {
        removeObservers()
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            
            await MainActor.run {
                self.authorizationStatus = granted ? .authorized : .denied
                self.isEnabled = granted
            }
            
            if granted {
                logger.info("✅ Notification authorization granted")
            } else {
                logger.warning("❌ Notification authorization denied")
            }
        } catch {
            logger.error("❌ Failed to request notification authorization: \(error)")
            await MainActor.run {
                self.authorizationStatus = .denied
                self.isEnabled = false
            }
        }
    }
    
    private func checkAuthorizationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        await MainActor.run {
            self.authorizationStatus = settings.authorizationStatus
            self.isEnabled = settings.authorizationStatus == .authorized
        }
        
        if settings.authorizationStatus == .notDetermined {
            // Automatically request authorization on first launch
            await requestAuthorization()
        }
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // Listen for funds received notifications
        let fundsReceivedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("FundsReceived"),
            object: nil,
            queue: notificationOperationQueue
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let amount = userInfo["amount"] as? Int64,
                  let txid = userInfo["txid"] as? String,
                  let confirmed = userInfo["confirmed"] as? Bool,
                  let amountText = userInfo["amountText"] as? String,
                  let statusText = userInfo["statusText"] as? String else {
                return
            }
            
            Task {
                await self.showFundsReceivedNotification(
                    amount: amount,
                    amountText: amountText,
                    txid: txid,
                    confirmed: confirmed,
                    statusText: statusText
                )
            }
        }
        observers.append(fundsReceivedObserver)
        
        // Listen for balance updates
        let balanceUpdateObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("BalanceUpdated"),
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let balance = userInfo["balance"] as? Balance else {
                return
            }
            
            Task {
                await self.handleBalanceUpdate(balance)
            }
        }
        observers.append(balanceUpdateObserver)
    }
    
    private func removeObservers() {
        observers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
    
    /// Manually remove all notification observers - useful for testing or explicit cleanup
    func cleanup() {
        removeObservers()
    }
    
    // MARK: - Notification Methods
    
    func showFundsReceivedNotification(
        amount: Int64,
        amountText: String,
        txid: String,
        confirmed: Bool,
        statusText: String
    ) async {
        guard isEnabled else {
            logger.info("📱 Notifications disabled, skipping local notification")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "💰 Funds Received"
        content.body = "\(amountText) (\(statusText))"
        content.sound = .default
        content.badge = 1
        
        // Add transaction details to user info
        content.userInfo = [
            "type": "funds_received",
            "amount": amount,
            "txid": txid,
            "confirmed": confirmed,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Create notification request
        let identifier = "funds_received_\(txid)_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("📱 Local notification sent for funds received: \(amountText)")
        } catch {
            logger.error("❌ Failed to send local notification: \(error)")
        }
    }
    
    func showTransactionConfirmedNotification(txid: String, amount: Int64) async {
        guard isEnabled else { return }
        
        let dashAmount = Double(amount) / 100_000_000
        let amountText = String(format: "%.8g DASH", dashAmount)
        
        let content = UNMutableNotificationContent()
        content.title = "✅ Transaction Confirmed"
        content.body = "\(amountText) transaction has been confirmed"
        content.sound = .default
        
        content.userInfo = [
            "type": "transaction_confirmed",
            "amount": amount,
            "txid": txid,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        let identifier = "tx_confirmed_\(txid)_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("📱 Local notification sent for transaction confirmation: \(txid)")
        } catch {
            logger.error("❌ Failed to send confirmation notification: \(error)")
        }
    }
    
    func showSyncCompletedNotification() async {
        guard isEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "🔄 Sync Completed"
        content.body = "Your wallet is now up to date"
        content.sound = .default
        
        content.userInfo = [
            "type": "sync_completed",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        let identifier = "sync_completed_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("📱 Local notification sent for sync completion")
        } catch {
            logger.error("❌ Failed to send sync completion notification: \(error)")
        }
    }
    
    private func handleBalanceUpdate(_ balance: Balance) async {
        // For now, just log balance updates
        // Could implement notifications for significant balance changes
        logger.info("💰 Balance update received - Total: \(balance.total) satoshis")
    }
    
    // MARK: - Notification Management
    
    func clearAllNotifications() async {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        logger.info("🧹 Cleared all notifications")
    }
    
    func clearNotificationsForTransaction(_ txid: String) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let pending = await center.pendingNotificationRequests()
        
        // Find notifications related to this transaction
        let deliveredToRemove = delivered.filter { notification in
            if let userTxid = notification.request.content.userInfo["txid"] as? String {
                return userTxid == txid
            }
            return false
        }.map { $0.request.identifier }
        
        let pendingToRemove = pending.filter { request in
            if let userTxid = request.content.userInfo["txid"] as? String {
                return userTxid == txid
            }
            return false
        }.map { $0.identifier }
        
        if !deliveredToRemove.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredToRemove)
        }
        
        if !pendingToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingToRemove)
        }
        
        logger.info("🧹 Cleared notifications for transaction: \(txid)")
    }
    
    func setBadgeCount(_ count: Int) async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(count)
            logger.info("📱 Set badge count to: \(count)")
        } catch {
            logger.error("❌ Failed to set badge count: \(error)")
        }
    }
    
    // MARK: - Settings
    
    func openNotificationSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
        
        Task { @MainActor in
            if UIApplication.shared.canOpenURL(settingsUrl) {
                UIApplication.shared.open(settingsUrl)
            }
        }
    }
}

// MARK: - Notification Delegate

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let logger = Logger(subsystem: "com.dash.wallet", category: "NotificationDelegate")
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle notification tap
        if let type = userInfo["type"] as? String {
            switch type {
            case "funds_received":
                // Could navigate to transaction details
                logger.info("📱 User tapped funds received notification")
                
            case "transaction_confirmed":
                // Could navigate to transaction details
                logger.info("📱 User tapped transaction confirmed notification")
                
            case "sync_completed":
                // Could navigate to wallet view
                logger.info("📱 User tapped sync completed notification")
                
            default:
                logger.warning("📱 Unknown notification type: \(type)")
            }
        }
        
        completionHandler()
    }
}

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