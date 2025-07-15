import Foundation
import SwiftDashCoreSDK
import Combine
import os.log

/// Service responsible for handling SDK events and notifications
@MainActor
class WalletEventService: ObservableObject {
    private let logger = Logger(subsystem: "com.dash.wallet", category: "WalletEventService")
    
    private var cancellables = Set<AnyCancellable>()
    
    // Service dependencies
    private let connectionService: WalletConnectionService
    private let transactionService: WalletTransactionService
    private let syncService: WalletSyncService
    private let networkConfigurationService = NetworkConfigurationService()
    
    // Callback to get active account (will be injected)
    var getActiveAccount: (() -> HDAccount?)?
    
    init(connectionService: WalletConnectionService, transactionService: WalletTransactionService, syncService: WalletSyncService) {
        self.connectionService = connectionService
        self.transactionService = transactionService
        self.syncService = syncService
    }
    
    func setupEventHandling(sdk: DashSDK) {
        logger.info("🔌 Setting up SPV event handling...")
        
        sdk.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleSDKEvent(event)
            }
            .store(in: &cancellables)
            
        logger.info("✅ SPV event handling setup complete")
    }
    
    private func handleSDKEvent(_ event: SPVEvent) {
        logger.info("🎯 Received SPV event")
        switch event {
        case .connectionStatusChanged(let connected):
            handleConnectionStatusChanged(connected)
            
        case .balanceUpdated(let balance):
            // Convert Balance to LocalBalance
            let localBalance = LocalBalance(
                confirmed: balance.confirmed,
                pending: balance.pending,
                instantLocked: balance.instantLocked,
                mempool: balance.mempool,
                mempoolInstant: balance.mempoolInstant ?? 0,
                total: balance.total
            )
            handleBalanceUpdated(localBalance)
            
        case .transactionReceived(let txid, let confirmed, let amount, let addresses, let blockHeight):
            handleTransactionReceived(txid: txid, confirmed: confirmed, amount: amount, addresses: addresses, blockHeight: blockHeight)
            
        case .mempoolTransactionAdded(let txid, let amount, let addresses):
            handleMempoolTransactionAdded(txid: txid, amount: amount, addresses: addresses)
            
        case .mempoolTransactionConfirmed(let txid, let blockHeight, let confirmations):
            handleMempoolTransactionConfirmed(txid: txid, blockHeight: blockHeight, confirmations: confirmations)
            
        case .mempoolTransactionRemoved(let txid, let reason):
            handleMempoolTransactionRemoved(txid: txid, reason: String(describing: reason))
            
        case .syncProgressUpdated(let progress):
            handleSyncProgressUpdated(progress)
            
        default:
            break
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleConnectionStatusChanged(_ connected: Bool) {
        if connected {
            logger.info("✅ Connected to network")
            logger.info("   Is syncing: \(self.syncService.isSyncing)")
            logger.info("   Is connected: \(self.connectionService.isConnected)")
        } else {
            logger.warning("❌ Disconnected from network")
            Task {
                await handlePeerConnectivityIssue()
            }
        }
    }
    
    private func handleBalanceUpdated(_ balance: LocalBalance) {
        Task {
            logger.info("💰 Balance updated - Confirmed: \(balance.confirmed), Pending: \(balance.pending), InstantLocked: \(balance.instantLocked), Total: \(balance.total)")
            
            // Trigger a notification to other parts of the app
            await transactionService.notifyBalanceUpdate(balance)
        }
    }
    
    private func handleTransactionReceived(txid: String, confirmed: Bool, amount: Int64, addresses: [String], blockHeight: UInt32?) {
        Task {
            await transactionService.handleTransactionReceived(
                txid: txid, 
                confirmed: confirmed, 
                amount: amount, 
                addresses: addresses, 
                blockHeight: blockHeight, 
                account: getActiveAccountInternal()
            )
        }
    }
    
    private func handleMempoolTransactionAdded(txid: String, amount: Int64, addresses: [String]) {
        Task {
            await transactionService.handleMempoolTransactionAdded(
                txid: txid, 
                amount: amount, 
                addresses: addresses, 
                account: getActiveAccountInternal()
            )
        }
    }
    
    private func handleMempoolTransactionConfirmed(txid: String, blockHeight: UInt32, confirmations: UInt32) {
        Task {
            await transactionService.handleMempoolTransactionConfirmed(
                txid: txid, 
                blockHeight: blockHeight, 
                confirmations: confirmations, 
                account: getActiveAccountInternal()
            )
        }
    }
    
    private func handleMempoolTransactionRemoved(txid: String, reason: String) {
        Task {
            await transactionService.handleMempoolTransactionRemoved(
                txid: txid, 
                reason: reason, 
                account: getActiveAccountInternal()
            )
        }
    }
    
    private func handleSyncProgressUpdated(_ progress: SyncProgress) {
        logger.info("📊 Sync progress: \(progress.percentageComplete)% - \(progress.status.description)")
    }
    
    // MARK: - Helper Methods
    
    private func handlePeerConnectivityIssue() async {
        await networkConfigurationService.handlePeerConnectivityIssue()
    }
    
    private func getActiveAccountInternal() -> HDAccount? {
        return getActiveAccount?()
    }
    
    func cleanup() {
        cancellables.removeAll()
    }
}