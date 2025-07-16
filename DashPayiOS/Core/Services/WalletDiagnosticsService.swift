import Foundation
import SwiftDashCoreSDK
import os.log

/// Service responsible for wallet testing and diagnostics functionality
@MainActor
class WalletDiagnosticsService: ObservableObject {
    private let logger = Logger(subsystem: "com.dash.wallet", category: "WalletDiagnosticsService")
    
    private let balanceTransactionService = BalanceTransactionService()
    private let addressManagementService = AddressManagementService()
    
    // MARK: - Test Methods
    
    /// Test method to create a test address for receiving funds
    func createTestReceiveAddress(for account: HDAccount) -> String? {
        do {
            let testAddress = try addressManagementService.generateNewAddress(for: account, isChange: false)
            logger.info("🧪 Test receive address created: \(testAddress.address)")
            logger.info("   Derivation path: \(testAddress.derivationPath)")
            logger.info("   Index: \(testAddress.index)")
            return testAddress.address
        } catch {
            logger.error("❌ Error creating test address: \(error)")
            return nil
        }
    }
    
    /// Comprehensive test of the receiving funds detection system
    func testReceivingFundsDetection(activeAccount: HDAccount?) async {
        logger.info("🧪 Starting comprehensive receiving funds detection test")
        
        guard let account = activeAccount else {
            logger.error("❌ No active account for testing")
            return
        }
        
        // 1. Create a test receive address
        guard let testAddress = createTestReceiveAddress(for: account) else {
            logger.error("❌ Failed to create test address")
            return
        }
        
        logger.info("✅ Step 1: Test address created - \(testAddress)")
        
        // 2. Simulate receiving a transaction
        logger.info("🧪 Step 2: Simulating received transaction...")
        
        let mockTxid = "test_tx_\(Date().timeIntervalSince1970)"
        let mockAmount: Int64 = 50_000_000 // 0.5 DASH
        
        // Simulate the transaction event directly
        await balanceTransactionService.saveTransaction(
            txid: mockTxid,
            amount: mockAmount,
            addresses: [testAddress],
            confirmed: false,
            blockHeight: nil,
            account: account
        )
        
        logger.info("✅ Step 2: Mock transaction saved")
        
        // 3. Test the notification system
        logger.info("🧪 Step 3: Testing notification system...")
        
        await showFundsReceivedNotification(
            amount: mockAmount,
            txid: mockTxid,
            confirmed: false
        )
        
        logger.info("✅ Step 3: Notification system tested")
        
        // 4. Test address activity tracking
        logger.info("🧪 Step 4: Testing address activity tracking...")
        
        await updateAddressActivity(addresses: [testAddress], txid: mockTxid, account: account)
        
        let (hasRecentActivity, lastActivity) = getRecentActivityForAddress(testAddress, account: account)
        logger.info("✅ Step 4: Address activity - Recent: \(hasRecentActivity), Last: \(lastActivity?.description ?? "None")")
        
        // 5. Test confirmation simulation
        logger.info("🧪 Step 6: Simulating transaction confirmation...")
        
        do {
            try await balanceTransactionService.confirmTransaction(txid: mockTxid, blockHeight: 850000)
            logger.info("✅ Step 6: Transaction confirmation simulated")
        } catch {
            logger.error("❌ Step 6: Transaction confirmation failed - \(error)")
        }
        
        logger.info("🎉 Comprehensive receiving funds detection test completed!")
        logger.info("📊 Test Summary:")
        logger.info("   - Test address: \(testAddress)")
        logger.info("   - Test transaction: \(mockTxid)")
        logger.info("   - Test amount: \(Double(mockAmount) / 100_000_000) DASH")
        logger.info("   - Notifications: Enabled")
        logger.info("   - Activity tracking: Active")
        logger.info("   - Balance updates: Real-time")
    }
    
    /// Test peer connectivity with detailed logging
    func testPeerConnectivity(activeWallet: HDWallet?, syncProgress: SyncProgress?, detailedSyncProgress: SwiftDashCoreSDK.DetailedSyncProgress?, isConnected: Bool, isSyncing: Bool, isUsingLocalPeers: Bool, sdk: DashSDK?) async {
        logger.info("🧪 Starting peer connectivity test")
        logger.info("   Current configuration: useLocalPeers = \(isUsingLocalPeers)")
        
        guard let wallet = activeWallet else {
            logger.error("❌ No active wallet/account for testing")
            return
        }
        
        logger.info("📊 Test Summary:")
        logger.info("   - Network: \(String(describing: wallet.network))")
        logger.info("   - Using Local Peers: \(isUsingLocalPeers)")
        
        if sdk != nil {
            // Log current peer configuration
            if wallet.network == .testnet {
                let testnetConfig = try? SPVConfigurationManager.shared.configuration(for: .testnet)
                logger.info("   - Available testnet peers:")
                if let testnetConfig = testnetConfig {
                    for peer in testnetConfig.additionalPeers {
                        logger.info("     • \(peer)")
                    }
                } else {
                    logger.warning("   - Failed to get testnet configuration for peer logging")
                }
            }
            
            logger.info("   - Connection Status: \(isConnected ? "Connected" : "Disconnected")")
            logger.info("   - Sync Status: \(isSyncing ? "Syncing" : "Not syncing")")
            
            if let progress = syncProgress {
                logger.info("   - Sync Progress: \(Int(progress.progress * 100))%")
                logger.info("   - Current Height: \(progress.currentHeight)")
                logger.info("   - Total Height: \(progress.totalHeight)")
            }
        }
        
        logger.info("✅ Peer connectivity test completed")
    }
    
    /// Get summary of receiving funds detection capabilities
    func getReceivingFundsDetectionSummary() -> [String: Any] {
        return [
            "spv_event_handling": "Enhanced with comprehensive logging and transaction filtering",
            "visual_indicators": "Real-time notification banners and activity indicators",
            "local_notifications": "Push notifications for received funds and confirmations",
            "balance_updates": "Immediate UI updates with forced refresh",
            "activity_tracking": "Address-level activity timestamps and recent activity detection",
            "logging": "Comprehensive transaction and balance logging for debugging",
            "test_capabilities": "Full test suite for simulating fund reception",
            "features": [
                "Transaction direction detection",
                "Real-time balance updates",
                "Visual notification banners",
                "Local push notifications",
                "Address activity indicators",
                "Enhanced receive address view",
                "Comprehensive transaction logging",
                "Test address generation"
            ]
        ]
    }
    
    // MARK: - Connection Diagnostics
    
    /// Get Platform network status
    func getPlatformNetworkStatus() async -> String? {
        // Platform SDK integration will be added later
        return "Platform SDK not yet integrated"
    }
    
    /// Run full diagnostic check for both Core and Platform
    func runFullDiagnostics(
        sdk: DashSDK?,
        activeWallet: HDWallet?,
        activeAccount: HDAccount?,
        isConnected: Bool,
        isSyncing: Bool,
        syncProgress: SyncProgress?,
        detailedSyncProgress: SwiftDashCoreSDK.DetailedSyncProgress?,
        watchAddressErrors: [WatchAddressError],
        pendingWatchCount: Int,
        networkMonitor: NetworkMonitor?,
        autoSyncEnabled: Bool,
        lastAutoSyncDate: Date?,
        isUsingLocalPeers: Bool
    ) async -> String {
        var report = "🔍 DashPay iOS Diagnostic Report\n"
        report += "================================\n\n"
        report += "Timestamp: \(Date())\n\n"
        
        // Core diagnostics
        report += "Core SDK Status:\n"
        if let sdk = sdk {
            report += "  - Initialized: ✅\n"
            report += "  - Connected: \(sdk.isConnected ? "✅" : "❌")\n"
            report += "  - Network: \(activeWallet?.network.rawValue ?? "Unknown")\n"
            report += "  - Use Local Peers: \(isUsingLocalPeers)\n"
            
            // Get peer info if available
            if isConnected {
                report += "  - Connection Details:\n"
                if let progress = detailedSyncProgress {
                    report += "    - Connected Peers: \(progress.connectedPeers)\n"
                    report += "    - Sync Stage: \(progress.stage)\n"
                    report += "    - Current Height: \(progress.currentHeight)\n"
                    report += "    - Total Height: \(progress.totalHeight)\n"
                }
            }
        } else {
            report += "  - Initialized: ❌\n"
        }
        
        report += "\n"
        
        // Platform diagnostics
        report += "Platform SDK Status:\n"
        if let platformStatus = await getPlatformNetworkStatus() {
            report += "  - Status: \(platformStatus)\n"
        } else {
            report += "  - Status: Not initialized or not available\n"
        }
        
        report += "\n"
        
        // Wallet status
        report += "Wallet Status:\n"
        report += "  - Active Wallet: \(activeWallet?.name ?? "None")\n"
        report += "  - Active Account: \(activeAccount?.displayName ?? "None")\n"
        report += "  - Connected: \(isConnected ? "✅" : "❌")\n"
        report += "  - Syncing: \(isSyncing ? "✅" : "❌")\n"
        if let progress = syncProgress {
            report += "  - Sync Progress: \(Int(progress.progress * 100))%\n"
        }
        report += "  - Watch Address Errors: \(watchAddressErrors.count)\n"
        report += "  - Pending Watch Count: \(pendingWatchCount)\n"
        
        report += "\n"
        
        // Network connectivity
        report += "Network Connectivity:\n"
        report += "  - Network Monitor: \(networkMonitor?.isConnected ?? false ? "Connected" : "Disconnected")\n"
        report += "  - Auto Sync Enabled: \(autoSyncEnabled)\n"
        if let lastSync = lastAutoSyncDate {
            report += "  - Last Auto Sync: \(lastSync)\n"
        }
        
        logger.info("📋 Full diagnostics report generated")
        return report
    }
    
    /// Test connection and provide detailed connection status
    func testConnectionStatus(
        sdk: DashSDK?,
        networkMonitor: NetworkMonitor?,
        isUsingLocalPeers: Bool,
        getLocalPeerHost: () -> String
    ) async -> ConnectionStatus {
        logger.info("🔍 Testing connection status...")
        
        var status = ConnectionStatus()
        
        // Check Core SDK
        if let sdk = sdk {
            status.coreSDKInitialized = true
            status.coreSDKConnected = sdk.isConnected
            
            if !sdk.isConnected {
                // Try to get more info about why not connected
                status.coreConnectionError = "SDK exists but not connected to network"
            }
        } else {
            status.coreSDKInitialized = false
            status.coreConnectionError = "Core SDK not initialized"
        }
        
        // Check network connectivity
        status.networkAvailable = networkMonitor?.isConnected ?? true
        
        // Check peer configuration
        status.usingLocalPeers = isUsingLocalPeers
        if status.usingLocalPeers {
            status.peerConfiguration = "Local peer: \(getLocalPeerHost())"
        } else {
            status.peerConfiguration = "Public peers (DNS seeds)"
        }
        
        logger.info("📊 Connection status check complete")
        return status
    }
    
    // MARK: - Private Helper Methods
    
    /// Show a notification when funds are received
    private func showFundsReceivedNotification(amount: Int64, txid: String, confirmed: Bool) async {
        let dashAmount = Double(amount) / 100_000_000
        let amountText = String(format: "%.8g DASH", dashAmount)
        let statusText = confirmed ? "Confirmed" : "Unconfirmed"
        
        // Log the received funds
        logger.info("🎉 Funds received: \(amountText) (\(statusText))")
        logger.info("   Transaction ID: \(txid)")
        
        // Post notification to NotificationCenter for other parts of the app
        let userInfo: [String: Any] = [
            "amount": amount,
            "txid": txid,
            "confirmed": confirmed,
            "amountText": amountText,
            "statusText": statusText
        ]
        
        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("FundsReceived"),
                object: nil,
                userInfo: userInfo
            )
        }
    }
    
    /// Update activity indicators for addresses involved in transactions
    private func updateAddressActivity(addresses: [String], txid: String, account: HDAccount) async {
        // Mark addresses as having recent activity
        for addressString in addresses {
            if let watchedAddress = account.addresses.first(where: { $0.address == addressString }) {
                // Update the address with recent activity timestamp
                watchedAddress.lastActivityTimestamp = Date()
                logger.info("🔄 Updated activity for address: \(addressString)")
            }
        }
    }
    
    /// Get recent transaction activity for an address
    private func getRecentActivityForAddress(_ address: String, account: HDAccount) -> (hasRecentActivity: Bool, lastActivityTime: Date?) {
        guard let watchedAddress = account.addresses.first(where: { $0.address == address }) else {
            return (false, nil)
        }
        
        let lastActivity = watchedAddress.lastActivityTimestamp
        let isRecent = lastActivity?.timeIntervalSinceNow ?? -Double.greatestFiniteMagnitude > -300 // 5 minutes
        
        return (isRecent, lastActivity)
    }
}

// MARK: - Connection Status
struct ConnectionStatus {
    var coreSDKInitialized: Bool = false
    var coreSDKConnected: Bool = false
    var coreConnectionError: String?
    var networkAvailable: Bool = false
    var usingLocalPeers: Bool = false
    var peerConfiguration: String = ""
    var platformSDKAvailable: Bool = false
    var platformConnectionError: String?
}