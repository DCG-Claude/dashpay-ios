import Foundation
import SwiftData
import SwiftDashCoreSDK
import Combine
import os.log

/// Service responsible for balance and transaction management
@MainActor
class BalanceTransactionService: ObservableObject {
    @Published var mempoolTransactionCount: Int = 0
    
    private let logger = Logger(subsystem: "com.dash.wallet", category: "BalanceTransactionService")
    private weak var modelContext: ModelContext?
    
    /// Configure the service with model context
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        logger.info("🔧 BalanceTransactionService configured with modelContext")
    }
    
    /// Update account balance
    func updateAccountBalance(_ account: HDAccount, sdk: DashSDK) async throws {
        logger.info("💰 Updating account balance for: \(account.displayName)")
        
        // Store previous balance for comparison
        let previousBalance = account.balance?.total ?? 0
        
        // Move heavy I/O operations to background
        let balanceData = try await performBalanceUpdate(sdk: sdk, addresses: account.addresses)
        
        // Update individual address balances on main thread
        guard let context = modelContext else {
            logger.error("ModelContext is nil, cannot update address balances")
            throw WalletError.noContext
        }
        
        var updateErrors: [Error] = []
        
        for (address, balance) in balanceData.addressBalances {
            do {
                try address.updateBalanceSafely(from: balance, in: context)
            } catch {
                logger.error("Failed to update address balance for \(address.address): \(error)")
                updateErrors.append(error)
            }
        }
        
        // Update account balance safely
        do {
            try account.updateBalanceSafely(from: balanceData.accountBalance, in: context)
        } catch {
            logger.error("Failed to update account balance: \(error)")
            updateErrors.append(error)
        }
        
        // Save to persistence
        do {
            try context.save()
        } catch {
            logger.error("Failed to save context: \(error)")
            updateErrors.append(error)
        }
        
        // If any errors were collected, throw an aggregate error
        if !updateErrors.isEmpty {
            throw WalletError.aggregateError(updateErrors)
        }
        
        // Log balance change using the updated account balance
        let currentTotal = account.balance?.total ?? 0
        let balanceChange = Int64(currentTotal) - Int64(previousBalance)
        if balanceChange != 0 {
            logger.info("💰 Balance changed by \(balanceChange) satoshis")
            logger.info("   Previous: \(previousBalance) satoshis")
            logger.info("   Current: \(currentTotal) satoshis")
            logger.info("   Confirmed: \(account.balance?.confirmed ?? 0)")
            logger.info("   Pending: \(account.balance?.pending ?? 0)")
            logger.info("   InstantLocked: \(account.balance?.instantLocked ?? 0)")
        }
        
        logger.info("✅ Account balance updated successfully")
    }
    
    /// Update transactions for an account
    func updateTransactions(for account: HDAccount, sdk: DashSDK) async throws {
        guard let context = modelContext else {
            throw WalletError.notConnected
        }
        
        logger.info("📋 Updating transactions for account: \(account.displayName)")
        
        for address in account.addresses {
            let sdkTransactions = try await sdk.getTransactions(for: address.address)
            
            for sdkTx in sdkTransactions {
                // Check if transaction already exists with retry logic
                let txidToCheck = sdkTx.txid
                let descriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate { transaction in
                        transaction.txid == txidToCheck
                    }
                )
                
                let existingTransactions: [Transaction]
                do {
                    existingTransactions = try await fetchWithRetry(
                        descriptor: descriptor,
                        context: context,
                        txid: txidToCheck,
                        maxRetries: 3
                    )
                } catch {
                    logger.error("❌ Failed to fetch existing transaction \(txidToCheck) after retries: \(error)")
                    // Fail fast - stop processing this address to prevent data inconsistency
                    throw WalletError.transactionFetchFailed(txid: txidToCheck, underlyingError: error)
                }
                
                if !existingTransactions.isEmpty {
                    // Transaction already exists, skip
                    continue
                } else {
                    // Create a new transaction instance for this context
                    let newTransaction = Transaction(
                        txid: sdkTx.txid,
                        height: sdkTx.height,
                        timestamp: sdkTx.timestamp,
                        amount: sdkTx.amount,
                        fee: sdkTx.fee,
                        confirmations: sdkTx.confirmations,
                        isInstantLocked: sdkTx.isInstantLocked,
                        raw: sdkTx.raw,
                        size: sdkTx.size,
                        version: sdkTx.version
                    )
                    context.insert(newTransaction)
                    
                    // Add transaction ID to account and address
                    if !account.transactionIds.contains(sdkTx.txid) {
                        account.transactionIds.append(sdkTx.txid)
                    }
                    if !address.transactionIds.contains(sdkTx.txid) {
                        address.transactionIds.append(sdkTx.txid)
                    }
                }
            }
        }
        
        try context.save()
        logger.info("✅ Transactions updated successfully")
    }
    
    /// Save a new transaction
    func saveTransaction(
        txid: String,
        amount: Int64,
        addresses: [String],
        confirmed: Bool,
        blockHeight: UInt32?,
        account: HDAccount
    ) async {
        guard let context = modelContext else { return }
        
        logger.info("💾 Saving transaction: \(txid)")
        
        // Check if transaction already exists
        let descriptor = FetchDescriptor<Transaction>()
        
        let existingTransactions = try? context.fetch(descriptor)
        if let existingTx = existingTransactions?.first(where: { $0.txid == txid }) {
            // Update existing transaction
            existingTx.confirmations = confirmed ? max(1, existingTx.confirmations) : 0
            existingTx.height = blockHeight ?? existingTx.height
            logger.info("📝 Updated existing transaction: \(txid)")
        } else {
            // Create new transaction
            let transaction = Transaction(
                txid: txid,
                height: blockHeight,
                timestamp: Date(),
                amount: amount,
                confirmations: confirmed ? 1 : 0,
                isInstantLocked: false
            )
            
            // Associate transaction ID with account
            if !account.transactionIds.contains(txid) {
                account.transactionIds.append(txid)
            }
            
            // Associate transaction ID with addresses
            for addressString in addresses {
                if let watchedAddress = account.addresses.first(where: { $0.address == addressString }) {
                    if !watchedAddress.transactionIds.contains(txid) {
                        watchedAddress.transactionIds.append(txid)
                    }
                    logger.info("🔗 Linked transaction to address: \(addressString)")
                }
            }
            
            context.insert(transaction)
            logger.info("💾 Saved new transaction: \(txid) with amount: \(amount) satoshis")
        }
        
        // Save context
        do {
            try context.save()
            logger.info("✅ Transaction saved to database")
        } catch {
            logger.error("❌ Error saving transaction: \(error)")
        }
    }
    
    /// Confirm a transaction
    func confirmTransaction(txid: String, blockHeight: UInt32) async throws {
        guard let context = modelContext else { return }
        
        logger.info("✅ Confirming transaction: \(txid)")
        
        let descriptor = FetchDescriptor<Transaction>()
        let existingTransactions = try? context.fetch(descriptor)
        
        if let transaction = existingTransactions?.first(where: { $0.txid == txid }) {
            transaction.confirmations = 1
            transaction.height = blockHeight
            logger.info("✅ Updated transaction \(txid) as confirmed at height \(blockHeight)")
            
            do {
                try context.save()
            } catch {
                logger.error("❌ Error updating confirmed transaction: \(error)")
                throw error
            }
        }
    }
    
    /// Remove a transaction
    func removeTransaction(txid: String, account: HDAccount) async throws {
        guard let context = modelContext else { return }
        
        logger.info("🗑️ Removing transaction: \(txid)")
        
        let descriptor = FetchDescriptor<Transaction>()
        let existingTransactions = try? context.fetch(descriptor)
        
        if let transaction = existingTransactions?.first(where: { $0.txid == txid }) {
            // Remove transaction from account and address references
            account.transactionIds.removeAll { $0 == txid }
            
            for address in account.addresses {
                address.transactionIds.removeAll { $0 == txid }
            }
            
            // Delete the transaction
            context.delete(transaction)
            logger.info("🗑️ Removed transaction \(txid) from database")
            
            do {
                try context.save()
            } catch {
                logger.error("❌ Error removing transaction: \(error)")
                throw error
            }
        }
    }
    
    /// Update mempool transaction count
    func updateMempoolTransactionCount(for account: HDAccount) async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<Transaction>()
        let allTransactions = try? context.fetch(descriptor)
        
        // Count unconfirmed transactions (confirmations == 0)
        let accountTxIds = Set(account.transactionIds)
        let mempoolCount = allTransactions?.filter { transaction in
            accountTxIds.contains(transaction.txid) && transaction.confirmations == 0
        }.count ?? 0
        
        mempoolTransactionCount = mempoolCount
        logger.info("📊 Updated mempool transaction count: \(mempoolCount)")
    }
    
    /// Fetch transactions for a given account from SwiftData
    func fetchTransactionsForAccount(_ account: HDAccount) async -> [SwiftDashCoreSDK.Transaction] {
        guard let modelContext = modelContext else { return [] }
        
        // Get all transaction IDs from the account
        let txids = account.transactionIds
        guard !txids.isEmpty else { return [] }
        
        var sdkTransactions: [SwiftDashCoreSDK.Transaction] = []
        
        // Fetch each transaction from SwiftData
        for txid in txids {
            do {
                let predicate = #Predicate<Transaction> { transaction in
                    transaction.txid == txid
                }
                let descriptor = FetchDescriptor<Transaction>(predicate: predicate)
                
                if let storedTransaction = try modelContext.fetch(descriptor).first {
                    // Convert SwiftData Transaction to SDK Transaction
                    let sdkTransaction = SwiftDashCoreSDK.Transaction(
                        txid: storedTransaction.txid,
                        height: storedTransaction.height,
                        timestamp: storedTransaction.timestamp,
                        amount: storedTransaction.amount,
                        fee: storedTransaction.fee ?? 0,
                        confirmations: storedTransaction.confirmations,
                        isInstantLocked: storedTransaction.isInstantLocked,
                        raw: storedTransaction.raw ?? Data(),
                        size: storedTransaction.size ?? 0,
                        version: storedTransaction.version ?? 1
                    )
                    sdkTransactions.append(sdkTransaction)
                }
            } catch {
                logger.error("❌ Error fetching transaction \(txid): \(error)")
            }
        }
        
        // Sort by timestamp, newest first
        return sdkTransactions.sorted { $0.timestamp > $1.timestamp }
    }
    
    /// Check for new transactions manually
    func checkForNewTransactions(for account: HDAccount, sdk: DashSDK) async {
        logger.info("🔍 Manually checking for new transactions...")
        logger.info("   Active account: \(account.label)")
        logger.info("   Number of addresses: \(account.addresses.count)")
        
        for address in account.addresses {
            do {
                logger.info("   Checking address: \(address.address)")
                let transactions = try await sdk.getTransactions(for: address.address)
                logger.info("📊 Found \(transactions.count) transactions for address \(address.address)")
                
                for transaction in transactions {
                    // Check if we already have this transaction
                    if !account.transactionIds.contains(transaction.txid) {
                        logger.info("🆕 Found new transaction: \(transaction.txid)")
                        
                        // Determine the addresses involved
                        let addresses = [address.address] // We know at least this address is involved
                        
                        // Save the transaction
                        await saveTransaction(
                            txid: transaction.txid,
                            amount: transaction.amount,
                            addresses: addresses,
                            confirmed: transaction.confirmations > 0,
                            blockHeight: transaction.height,
                            account: account
                        )
                    }
                }
            } catch {
                logger.error("❌ Error checking transactions for address \(address.address): \(error)")
            }
        }
        
        logger.info("✅ Transaction check complete")
    }
    
    // MARK: - Private Helper Methods
    
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
    
    /// Helper method to fetch transactions with retry logic for transient failures
    private func fetchWithRetry(
        descriptor: FetchDescriptor<Transaction>,
        context: ModelContext,
        txid: String,
        maxRetries: Int = 3
    ) async throws -> [Transaction] {
        var lastError: Error?
        var retryDelay: TimeInterval = 0.1 // Start with 100ms
        
        for attempt in 0..<maxRetries {
            do {
                let result = try context.fetch(descriptor)
                if attempt > 0 {
                    logger.info("✅ Successfully fetched transaction \(txid) on attempt \(attempt + 1)")
                }
                return result
            } catch {
                lastError = error
                logger.warning("⚠️ Fetch attempt \(attempt + 1)/\(maxRetries) failed for transaction \(txid): \(error)")
                
                // Don't delay on the last attempt
                if attempt < maxRetries - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                    retryDelay *= 2 // Exponential backoff
                }
            }
        }
        
        // All retries failed, throw the last error
        throw lastError ?? WalletError.unknownError
    }
}