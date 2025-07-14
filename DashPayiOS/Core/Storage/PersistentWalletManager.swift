import Foundation
import Combine
import SwiftData
import SwiftDashCoreSDK
import os.log

@Observable
final class PersistentWalletManager {
    private let client: SPVClient
    private let storage: StorageManager
    private var syncTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.dash.wallet", category: "PersistentWalletManager")
    
    var watchedAddresses: Set<String> = []
    var totalBalance: Balance = Balance(
        confirmed: 0,
        pending: 0,
        instantLocked: 0,
        mempool: 0,
        mempoolInstant: 0,
        total: 0
    )
    
    init(client: SPVClient, storage: StorageManager) {
        self.client = client
        self.storage = storage
        
        Task {
            await loadPersistedData()
        }
    }
    
    deinit {
        syncTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    func watchAddress(_ address: String, label: String? = nil) async throws {
        // Add to SPV client
        try await client.addWatchItem(type: .address, data: address)
        
        // Add to tracked set
        watchedAddresses.insert(address)
        
        // Persist to storage if it's a new address
        if try storage.fetchWatchedAddress(by: address) == nil {
            // Find the account this address belongs to (if any)
            // For now, we'll create a standalone watched address
            let watchedAddress = HDWatchedAddress(
                address: address,
                index: 0,
                isChange: false,
                derivationPath: "",
                label: label ?? "Watched"
            )
            try storage.saveWatchedAddress(watchedAddress)
        }
        
        // Start syncing data for this address
        await syncAddressData(address)
    }
    
    func unwatchAddress(_ address: String) async throws {
        // Remove from SPV client
        try await client.removeWatchItem(type: .address, data: address)
        
        // Remove from tracked set
        watchedAddresses.remove(address)
        
        // Remove from storage
        if let watchedAddress = try storage.fetchWatchedAddress(by: address) {
            try storage.deleteWatchedAddress(watchedAddress)
        }
    }
    
    func getBalance(for address: String) async throws -> SwiftDashCoreSDK.Balance {
        // Try to get from storage first
        if let cachedBalance = try storage.fetchBalance(for: address) {
            // Check if balance is recent (within last minute)
            if Date.now.timeIntervalSince(cachedBalance.lastUpdated) < 60 {
                return SwiftDashCoreSDK.Balance(
                    confirmed: cachedBalance.confirmed,
                    pending: cachedBalance.pending,
                    instantLocked: cachedBalance.instantLocked,
                    mempool: cachedBalance.mempool,
                    mempoolInstant: cachedBalance.mempoolInstant,
                    total: cachedBalance.total,
                    lastUpdated: cachedBalance.lastUpdated
                )
            }
        }
        
        // Fetch fresh balance from SPV client
        let addressBalance = try await client.getAddressBalance(address)
        let balance = SwiftDashCoreSDK.Balance(
            confirmed: addressBalance.confirmed,
            pending: addressBalance.pending,
            instantLocked: addressBalance.instantLocked,
            mempool: 0, // SPV client doesn't provide mempool balance yet
            mempoolInstant: 0,
            total: addressBalance.confirmed + addressBalance.pending
        )
        
        // Save to storage
        let balanceModel = Balance(
            confirmed: balance.confirmed,
            pending: balance.pending,
            instantLocked: balance.instantLocked,
            mempool: balance.mempool,
            mempoolInstant: balance.mempoolInstant ?? 0,
            total: balance.total
        )
        try storage.saveBalance(balanceModel, for: address)
        
        return balance
    }
    
    func getTotalBalance() async throws -> SwiftDashCoreSDK.Balance {
        var totalConfirmed: UInt64 = 0
        var totalPending: UInt64 = 0
        var totalInstantLocked: UInt64 = 0
        var totalMempool: UInt64 = 0
        var totalMempoolInstant: UInt64 = 0
        
        for address in watchedAddresses {
            let balance = try await getBalance(for: address)
            totalConfirmed += balance.confirmed
            totalPending += balance.pending
            totalInstantLocked += balance.instantLocked
            totalMempool += balance.mempool
            totalMempoolInstant += balance.mempoolInstant ?? 0
        }
        
        let total = SwiftDashCoreSDK.Balance(
            confirmed: totalConfirmed,
            pending: totalPending,
            instantLocked: totalInstantLocked,
            mempool: totalMempool,
            mempoolInstant: totalMempoolInstant,
            total: totalConfirmed + totalPending + totalMempool
        )
        
        // Update internal state
        totalBalance = Balance(
            confirmed: total.confirmed,
            pending: total.pending,
            instantLocked: total.instantLocked,
            mempool: total.mempool,
            mempoolInstant: total.mempoolInstant ?? 0,
            total: total.total
        )
        
        return total
    }
    
    func getTransactions(for address: String? = nil, limit: Int = 100) async throws -> [SwiftDashCoreSDK.Transaction] {
        // For now, fetch from storage
        let storedTransactions = try storage.fetchTransactions(for: address, limit: limit)
        
        // Convert to SDK transactions
        return storedTransactions.map { tx in
            SwiftDashCoreSDK.Transaction(
                txid: tx.txid,
                height: tx.height,
                timestamp: tx.timestamp,
                amount: tx.amount,
                fee: tx.fee ?? 0,
                confirmations: tx.confirmations,
                isInstantLocked: tx.isInstantLocked,
                raw: tx.raw ?? Data(),
                size: tx.size ?? 0,
                version: tx.version ?? 1
            )
        }
    }
    
    func getUTXOs(for address: String? = nil) async throws -> [SwiftDashCoreSDK.UTXO] {
        let storedUTXOs = try storage.fetchUTXOs(for: address)
        
        // Convert to SDK UTXOs
        return storedUTXOs.map { utxo in
            SwiftDashCoreSDK.UTXO(
                outpoint: utxo.outpoint,
                txid: utxo.txid,
                vout: utxo.vout,
                address: utxo.address,
                script: utxo.script,
                value: utxo.value,
                height: utxo.height,
                confirmations: utxo.confirmations,
                isInstantLocked: utxo.isInstantLocked
            )
        }
    }
    
    func getSpendableUTXOs() async throws -> [SwiftDashCoreSDK.UTXO] {
        let utxos = try await getUTXOs()
        return utxos.filter { $0.confirmations > 0 }
    }
    
    func createTransaction(
        to address: String,
        amount: UInt64,
        feeRate: UInt64
    ) async throws -> Data {
        // This would need to be implemented with proper transaction building
        // For now, throw not implemented
        throw DashSDKError.notImplemented("Transaction creation not yet implemented")
    }
    
    // MARK: - Persistence Methods
    
    private func loadPersistedData() async {
        do {
            // Load watched addresses
            let addresses = try storage.fetchWatchedAddresses()
            
            watchedAddresses = Set(addresses.map { $0.address })
            
            // Re-watch addresses in SPV client if connected
            if client.isConnected {
                var watchErrors: [Error] = []
                
                for address in addresses {
                    do {
                        try await client.addWatchItem(type: .address, data: address.address)
                        logger.debug("Re-watched address: \(address.address)")
                    } catch {
                        logger.error("Failed to re-watch address \(address.address): \(error)")
                        watchErrors.append(error)
                    }
                }
                
                // If any addresses failed to watch, log but continue
                if !watchErrors.isEmpty {
                    logger.warning("Failed to re-watch \(watchErrors.count) addresses")
                }
            }
            
            // Load total balance
            await updateTotalBalance()
        } catch {
            logger.error("Failed to load persisted data: \(error)")
        }
    }
    
    private func syncAddressData(_ address: String) async {
        do {
            // Sync balance
            _ = try await getBalance(for: address)
            
            // Sync UTXOs (when implemented in SPV client)
            // let utxos = try await client.getUTXOs(for: address)
            // try await storage.saveUTXOs(utxos.map { LocalUTXO(from: $0) })
            
            // Sync transactions (when implemented in SPV client)
            // let transactions = try await client.getTransactions(for: address)
            // try await storage.saveTransactions(transactions.map { Transaction(from: $0) })
            
            // Update activity timestamp
            if let watchedAddress = try storage.fetchWatchedAddress(by: address) {
                watchedAddress.lastActivityTimestamp = Date()
                try storage.saveWatchedAddress(watchedAddress)
            }
        } catch {
            logger.error("Failed to sync address data: \(error)")
        }
    }
    
    private func updateTotalBalance() async {
        do {
            _ = try await getTotalBalance()
        } catch {
            logger.error("Failed to update total balance: \(error)")
        }
    }
    
    // MARK: - Public Persistence Methods
    
    func startPeriodicSync(interval: TimeInterval = 30) {
        syncTask?.cancel()
        
        syncTask = Task {
            while !Task.isCancelled {
                await syncAllData()
                
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }
    
    func stopPeriodicSync() {
        syncTask?.cancel()
        syncTask = nil
    }
    
    func syncAllData() async {
        for address in watchedAddresses {
            await syncAddressData(address)
        }
        
        await updateTotalBalance()
    }
    
    func getStorageStatistics() throws -> StorageStatistics {
        return try storage.getStorageStatistics()
    }
    
    func clearAllData() throws {
        try storage.deleteAllData()
        watchedAddresses.removeAll()
        totalBalance = Balance(
            confirmed: 0,
            pending: 0,
            instantLocked: 0,
            mempool: 0,
            mempoolInstant: 0,
            total: 0
        )
    }
    
    func exportWalletData() throws -> WalletExportData {
        let addresses = try storage.fetchWatchedAddresses()
        let transactions = try storage.fetchTransactions()
        let utxos = try storage.fetchUTXOs()
        
        // Convert to export format
        let exportedAddresses = addresses.map { address in
            WalletExportData.ExportedAddress(
                address: address.address,
                label: address.label,
                createdAt: Date(),
                isActive: !address.transactionIds.isEmpty,
                balance: address.balance.map { balance in
                    WalletExportData.ExportedBalance(
                        confirmed: balance.confirmed,
                        pending: balance.pending,
                        instantLocked: balance.instantLocked,
                        total: balance.total
                    )
                }
            )
        }
        
        let exportedTransactions = transactions.map { tx in
            WalletExportData.ExportedTransaction(
                txid: tx.txid,
                height: tx.height,
                timestamp: tx.timestamp,
                amount: tx.amount,
                fee: tx.fee ?? 0,
                confirmations: tx.confirmations,
                isInstantLocked: tx.isInstantLocked,
                size: tx.size ?? 0,
                version: tx.version ?? 1
            )
        }
        
        let exportedUTXOs = utxos.map { utxo in
            WalletExportData.ExportedUTXO(
                txid: utxo.txid,
                vout: utxo.vout,
                address: utxo.address,
                value: utxo.value,
                height: utxo.height,
                confirmations: utxo.confirmations,
                isInstantLocked: utxo.isInstantLocked
            )
        }
        
        return WalletExportData(
            addresses: exportedAddresses,
            transactions: exportedTransactions,
            utxos: exportedUTXOs,
            exportDate: .now
        )
    }
    
    func importWalletData(_ data: WalletExportData) async throws {
        // Clear existing data
        try clearAllData()
        
        // Import addresses
        for exportedAddress in data.addresses {
            let address = HDWatchedAddress(
                address: exportedAddress.address,
                index: 0,
                isChange: false,
                derivationPath: "",
                label: exportedAddress.label ?? "Imported"
            )
            
            // Create balance if present
            if let exportedBalance = exportedAddress.balance {
                let balance = Balance(
                    confirmed: exportedBalance.confirmed,
                    pending: exportedBalance.pending,
                    instantLocked: exportedBalance.instantLocked,
                    mempool: 0,
                    mempoolInstant: 0,
                    total: exportedBalance.total
                )
                address.balance = balance
            }
            
            try storage.saveWatchedAddress(address)
            watchedAddresses.insert(address.address)
        }
        
        // Import transactions
        let transactions = data.transactions.map { exportedTx in
            Transaction(
                txid: exportedTx.txid,
                height: exportedTx.height,
                timestamp: exportedTx.timestamp,
                amount: exportedTx.amount,
                fee: exportedTx.fee,
                confirmations: exportedTx.confirmations,
                isInstantLocked: exportedTx.isInstantLocked,
                size: exportedTx.size,
                version: exportedTx.version
            )
        }
        try await storage.saveTransactions(transactions)
        
        // Import UTXOs
        let utxos = data.utxos.map { exportedUTXO in
            let outpoint = "\(exportedUTXO.txid):\(exportedUTXO.vout)"
            return LocalUTXO(
                outpoint: outpoint,
                txid: exportedUTXO.txid,
                vout: exportedUTXO.vout,
                address: exportedUTXO.address,
                script: Data(), // Empty script for imported UTXOs
                value: exportedUTXO.value,
                height: exportedUTXO.height ?? 0,
                confirmations: exportedUTXO.confirmations,
                isInstantLocked: exportedUTXO.isInstantLocked,
                isSpent: false
            )
        }
        try await storage.saveUTXOs(utxos)
        
        // Update balances
        await updateTotalBalance()
    }
}

// MARK: - Wallet Export Data

struct WalletExportData: Codable {
    struct ExportedAddress: Codable {
        let address: String
        let label: String?
        let createdAt: Date
        let isActive: Bool
        let balance: ExportedBalance?
    }
    
    struct ExportedBalance: Codable {
        let confirmed: UInt64
        let pending: UInt64
        let instantLocked: UInt64
        let total: UInt64
    }
    
    struct ExportedTransaction: Codable {
        let txid: String
        let height: UInt32?
        let timestamp: Date
        let amount: Int64
        let fee: UInt64
        let confirmations: UInt32
        let isInstantLocked: Bool
        let size: UInt32
        let version: UInt32
    }
    
    struct ExportedUTXO: Codable {
        let txid: String
        let vout: UInt32
        let address: String
        let value: UInt64
        let height: UInt32?
        let confirmations: UInt32
        let isInstantLocked: Bool
    }
    
    let addresses: [ExportedAddress]
    let transactions: [ExportedTransaction]
    let utxos: [ExportedUTXO]
    let exportDate: Date
    
    var formattedSize: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        if let data = try? encoder.encode(self) {
            return ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .binary)
        }
        
        return "Unknown"
    }
}