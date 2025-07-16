import Foundation
import SwiftDashCoreSDK
import SwiftData
import os.log

/// Service responsible for transaction handling and management
@MainActor
class WalletTransactionService: ObservableObject {
    private let logger = Logger(subsystem: "com.dash.wallet", category: "WalletTransactionService")
    
    private let balanceTransactionService = BalanceTransactionService()
    private var modelContext: ModelContext?
    
    var mempoolTransactionCount: Int { balanceTransactionService.mempoolTransactionCount }
    
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        balanceTransactionService.configure(modelContext: modelContext)
    }
    
    // MARK: - Balance Management
    
    /// Helper method to perform heavy I/O operations for balance updates
    nonisolated private func performBalanceUpdate(
        sdk: DashSDK, 
        addresses: [HDWatchedAddress]
    ) async throws -> (addressBalances: [(HDWatchedAddress, SwiftDashCoreSDK.Balance)], accountBalance: SwiftDashCoreSDK.Balance) {
        var confirmedTotal: UInt64 = 0
        var pendingTotal: UInt64 = 0
        var instantLockedTotal: UInt64 = 0
        var mempoolTotal: UInt64 = 0
        var addressBalances: [(HDWatchedAddress, SwiftDashCoreSDK.Balance)] = []
        
        // Perform heavy I/O operations in background
        for address in addresses {
            let balance = try await sdk.getBalance(for: address.address)
            confirmedTotal += balance.confirmed
            pendingTotal += balance.pending
            instantLockedTotal += balance.instantLocked
            mempoolTotal += balance.mempool
            
            addressBalances.append((address, balance))
        }
        
        // Create SDK Balance for account update
        let accountBalance = SwiftDashCoreSDK.Balance(
            confirmed: confirmedTotal,
            pending: pendingTotal,
            instantLocked: instantLockedTotal,
            mempool: mempoolTotal,
            mempoolInstant: 0, // Will be calculated from individual addresses if needed
            total: confirmedTotal + pendingTotal + mempoolTotal
        )
        
        return (addressBalances: addressBalances, accountBalance: accountBalance)
    }
    
    func updateAccountBalance(_ account: HDAccount, sdk: DashSDK) async throws {
        try await balanceTransactionService.updateAccountBalance(account, sdk: sdk)
    }
    
    func updateTransactions(for account: HDAccount, sdk: DashSDK) async throws {
        try await balanceTransactionService.updateTransactions(for: account, sdk: sdk)
    }
    
    /// Fetch transactions for a given account from SwiftData
    func fetchTransactionsForAccount(_ account: HDAccount) async -> [SwiftDashCoreSDK.Transaction] {
        return await balanceTransactionService.fetchTransactionsForAccount(account)
    }
    
    /// Manually check for new transactions for all watched addresses
    func checkForNewTransactions(for account: HDAccount, sdk: DashSDK) async {
        await balanceTransactionService.checkForNewTransactions(for: account, sdk: sdk)
    }
    
    // MARK: - Transaction Event Handling
    
    func handleTransactionReceived(txid: String, confirmed: Bool, amount: Int64, addresses: [String], blockHeight: UInt32?, account: HDAccount?) async {
        logger.info("🚨 SPVEvent.transactionReceived triggered!")
        
        guard let account = account else { return }
        
        logger.info("📱 Transaction received: \(txid)")
        logger.info("   Amount: \(amount) satoshis (\(Double(amount) / 100_000_000) DASH)")
        logger.info("   Addresses: \(addresses.joined(separator: ", "))")
        logger.info("   Confirmed: \(confirmed)")
        if let height = blockHeight {
            logger.info("   Block Height: \(height)")
        }
        
        // Check if this transaction involves our addresses
        let isOurTransaction = addresses.contains { address in
            account.addresses.contains { watchedAddress in
                watchedAddress.address == address
            }
        }
        
        if isOurTransaction {
            // Determine transaction direction
            let direction = amount > 0 ? "received" : "sent"
            logger.info("   Direction: \(direction == "received" ? "Received" : "Sent")")
            
            // Show notification for received funds
            if direction == "received" {
                await showFundsReceivedNotification(
                    amount: amount,
                    txid: txid,
                    confirmed: confirmed
                )
            }
            
            // Create and save the transaction
            await balanceTransactionService.saveTransaction(
                txid: txid,
                amount: amount,
                addresses: addresses,
                confirmed: confirmed,
                blockHeight: blockHeight,
                account: account
            )
            
            // Update activity indicators
            await updateAddressActivity(addresses: addresses, txid: txid, account: account)
        } else {
            logger.info("   Transaction does not involve our addresses")
        }
    }
    
    func handleMempoolTransactionAdded(txid: String, amount: Int64, addresses: [String], account: HDAccount?) async {
        guard let account = account else { return }
        
        print("🔄 Mempool transaction added: \(txid)")
        print("   Amount: \(amount) satoshis")
        print("   Addresses: \(addresses)")
        
        // Save as unconfirmed transaction
        await balanceTransactionService.saveTransaction(
            txid: txid,
            amount: amount,
            addresses: addresses,
            confirmed: false,
            blockHeight: nil,
            account: account
        )
        
        // Update mempool count
        await balanceTransactionService.updateMempoolTransactionCount(for: account)
    }
    
    func handleMempoolTransactionConfirmed(txid: String, blockHeight: UInt32, confirmations: UInt32, account: HDAccount?) async {
        guard account != nil else { return }
        
        print("✅ Mempool transaction confirmed: \(txid) at height \(blockHeight) with \(confirmations) confirmations")
        
        // Update transaction confirmation status
        do {
            try await balanceTransactionService.confirmTransaction(txid: txid, blockHeight: blockHeight)
        } catch {
            logger.error("❌ Failed to confirm transaction \(txid): \(error)")
            // Continue processing but log the error - mempool tracking will handle eventual consistency
        }
        
        // Update mempool count
        if let account = account {
            await balanceTransactionService.updateMempoolTransactionCount(for: account)
        }
    }
    
    func handleMempoolTransactionRemoved(txid: String, reason: String, account: HDAccount?) async {
        guard account != nil else { return }
        
        print("❌ Mempool transaction removed: \(txid), reason: \(reason)")
        
        // Remove or mark transaction as dropped
        do {
            if let account = account {
                try await balanceTransactionService.removeTransaction(txid: txid, account: account)
            }
        } catch {
            logger.error("❌ Failed to remove transaction \(txid): \(error)")
            // Continue processing but log the error - mempool tracking will handle eventual consistency
        }
        
        // Update mempool count
        if let account = account {
            await balanceTransactionService.updateMempoolTransactionCount(for: account)
        }
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
        
        // Save the context
        do {
            try modelContext?.save()
        } catch {
            logger.error("❌ Error saving address activity: \(error)")
        }
    }
    
    /// Notify other parts of the app about balance updates
    func notifyBalanceUpdate(_ balance: LocalBalance) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("BalanceUpdated"),
                object: nil,
                userInfo: ["balance": balance]
            )
        }
    }
    
    /// Get recent transaction activity for an address
    func getRecentActivityForAddress(_ address: String, account: HDAccount?) -> (hasRecentActivity: Bool, lastActivityTime: Date?) {
        guard let account = account,
              let watchedAddress = account.addresses.first(where: { $0.address == address }) else {
            return (false, nil)
        }
        
        let lastActivity = watchedAddress.lastActivityTimestamp
        let isRecent = lastActivity?.timeIntervalSinceNow ?? -Double.greatestFiniteMagnitude > -300 // 5 minutes
        
        return (isRecent, lastActivity)
    }
    
    /// Enhanced transaction logging for debugging
    private func logTransactionDetails(_ transaction: Transaction) {
        logger.info("📝 Transaction Details:")
        logger.info("   TXID: \(transaction.txid)")
        logger.info("   Amount: \(transaction.amount) satoshis")
        logger.info("   Height: \(transaction.height ?? 0)")
        logger.info("   Confirmations: \(transaction.confirmations)")
        logger.info("   InstantLocked: \(transaction.isInstantLocked)")
    }
}