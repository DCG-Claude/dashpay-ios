import Foundation
import Combine
import SwiftData
import SwiftDashCoreSDK
import os.log

/// Protocol for UTXO and transaction synchronization
public protocol UTXOTransactionSyncProtocol: AnyObject {
    func getUTXOs() async throws -> [SwiftDashCoreSDK.UTXO]
    func getTransactions(for address: String) async throws -> [SwiftDashCoreSDK.Transaction]
}

@Observable
final class PersistentWalletManager {
    private let client: SwiftDashCoreSDK.SPVClient
    private let storage: StorageManager
    private weak var syncDelegate: UTXOTransactionSyncProtocol?
    private var syncTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.dash.wallet", category: "PersistentWalletManager")
    
    var watchedAddresses: Set<String> = []
    var totalBalance: SwiftDashCoreSDK.Balance = SwiftDashCoreSDK.Balance(
        confirmed: 0,
        pending: 0,
        instantLocked: 0,
        mempool: 0,
        mempoolInstant: 0,
        total: 0
    )
    
    init(client: SwiftDashCoreSDK.SPVClient, storage: StorageManager, syncDelegate: UTXOTransactionSyncProtocol? = nil) {
        self.client = client
        self.storage = storage
        self.syncDelegate = syncDelegate
        
        Task {
            await loadPersistedData()
        }
    }
    
    deinit {
        syncTask?.cancel()
    }
    
    // MARK: - Configuration Methods
    
    /// Set the sync delegate for UTXO and transaction synchronization
    func setSyncDelegate(_ syncDelegate: UTXOTransactionSyncProtocol) {
        self.syncDelegate = syncDelegate
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
        let balanceModel = LocalBalance(
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
        // Get available UTXOs for transaction building
        let utxos = try await getSpendableUTXOs()
        
        guard !utxos.isEmpty else {
            throw DashSDKError.transactionCreationFailed("No spendable UTXOs available")
        }
        
        // Select UTXOs for the transaction
        let selectedUTXOs = try selectUTXOs(
            from: utxos,
            targetAmount: amount,
            feeRate: feeRate
        )
        
        // Calculate fee
        let fee = calculateTransactionFee(
            inputs: selectedUTXOs.count,
            outputs: 2, // destination + change
            feeRate: feeRate
        )
        
        // Build raw transaction
        let rawTransaction = try buildRawTransaction(
            inputs: selectedUTXOs,
            outputs: [
                TransactionOutput(address: address, amount: amount)
            ],
            fee: fee
        )
        
        logger.info("Created transaction with \(selectedUTXOs.count) inputs, fee: \(fee)")
        
        return rawTransaction
    }
    
    // MARK: - Private Transaction Building Methods
    
    private func selectUTXOs(
        from utxos: [SwiftDashCoreSDK.UTXO],
        targetAmount: UInt64,
        feeRate: UInt64
    ) throws -> [SwiftDashCoreSDK.UTXO] {
        var selected: [SwiftDashCoreSDK.UTXO] = []
        var total: UInt64 = 0
        
        // Estimate fee with 2 inputs and 2 outputs initially
        let estimatedFee = calculateTransactionFee(inputs: 2, outputs: 2, feeRate: feeRate)
        let requiredAmount = targetAmount + estimatedFee
        
        // Sort UTXOs by value (largest first) for efficient selection
        let sortedUTXOs = utxos.sorted { $0.value > $1.value }
        
        for utxo in sortedUTXOs {
            if total >= requiredAmount {
                break
            }
            selected.append(utxo)
            total += utxo.value
        }
        
        if total < requiredAmount {
            throw DashSDKError.transactionCreationFailed("Insufficient funds: need \(requiredAmount), have \(total)")
        }
        
        return selected
    }
    
    private func calculateTransactionFee(
        inputs: Int,
        outputs: Int,
        feeRate: UInt64
    ) -> UInt64 {
        // Calculate transaction size in bytes
        let baseSize = 10 // Version (4) + Input count (1) + Output count (1) + Lock time (4)
        let inputSize = inputs * 148 // Average input size with signature
        let outputSize = outputs * 34 // Average output size (P2PKH)
        
        let totalSize = baseSize + inputSize + outputSize
        return UInt64(totalSize) * feeRate / 1000
    }
    
    private func buildRawTransaction(
        inputs: [SwiftDashCoreSDK.UTXO],
        outputs: [TransactionOutput],
        fee: UInt64
    ) throws -> Data {
        var rawTx = Data()
        
        // Transaction version (4 bytes)
        let version: UInt32 = 1
        rawTx.append(contentsOf: withUnsafeBytes(of: version.littleEndian) { Array($0) })
        
        // Input count (1 byte for now, assuming < 253)
        rawTx.append(UInt8(inputs.count))
        
        // Add inputs
        for input in inputs {
            // Previous transaction hash (32 bytes, reversed)
            if let txidData = Data(hex: input.txid) {
                rawTx.append(txidData.reversed())
            } else {
                throw DashSDKError.transactionCreationFailed("Invalid transaction ID format")
            }
            
            // Output index (4 bytes)
            rawTx.append(contentsOf: withUnsafeBytes(of: input.vout.littleEndian) { Array($0) })
            
            // Script length (1 byte for empty script)
            rawTx.append(0x00)
            
            // Sequence number (4 bytes)
            rawTx.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
        }
        
        // Calculate change amount
        let inputTotal = inputs.reduce(0) { $0 + $1.value }
        let outputTotal = outputs.reduce(0) { $0 + $1.amount }
        let changeAmount = inputTotal - outputTotal - fee
        
        // Determine number of outputs
        let outputCount = changeAmount > 546 ? outputs.count + 1 : outputs.count // 546 is dust threshold
        rawTx.append(UInt8(outputCount))
        
        // Add outputs
        for output in outputs {
            // Amount (8 bytes)
            rawTx.append(contentsOf: withUnsafeBytes(of: output.amount.littleEndian) { Array($0) })
            
            // Script (P2PKH script)
            let script = try createP2PKHScript(for: output.address)
            rawTx.append(UInt8(script.count))
            rawTx.append(script)
        }
        
        // Add change output if needed
        if changeAmount > 546 {
            rawTx.append(contentsOf: withUnsafeBytes(of: changeAmount.littleEndian) { Array($0) })
            
            // Use first watched address as change address
            let changeAddress = watchedAddresses.first ?? "default_change_address"
            let changeScript = try createP2PKHScript(for: changeAddress)
            rawTx.append(UInt8(changeScript.count))
            rawTx.append(changeScript)
        }
        
        // Lock time (4 bytes)
        rawTx.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        
        return rawTx
    }
    
    private func createP2PKHScript(for address: String) throws -> Data {
        // Create Pay-to-Public-Key-Hash script
        // This is a simplified implementation
        var script = Data()
        
        // OP_DUP
        script.append(0x76)
        // OP_HASH160
        script.append(0xa9)
        // Push 20 bytes
        script.append(0x14)
        // 20-byte hash160 of public key (derived from address)
        // For now, use a placeholder hash
        let pubKeyHash = Data(repeating: 0x00, count: 20)
        script.append(pubKeyHash)
        // OP_EQUALVERIFY
        script.append(0x88)
        // OP_CHECKSIG
        script.append(0xac)
        
        return script
    }
    
    private struct TransactionOutput {
        let address: String
        let amount: UInt64
    }
}

// MARK: - Data Extensions

extension Data {
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        for i in 0..<len {
            let j = hex.index(hex.startIndex, offsetBy: i*2)
            let k = hex.index(j, offsetBy: 2)
            let bytes = hex[j..<k]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
        }
        self = data
    }
}

// MARK: - Persistence Methods - Back to PersistentWalletManager

extension PersistentWalletManager {
    
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
            
            // Sync UTXOs and transactions from sync delegate
            if let syncDelegate = self.syncDelegate {
                // Sync UTXOs
                do {
                    let utxos = try await syncDelegate.getUTXOs()
                    // Filter UTXOs for the specific address
                    let addressUTXOs = utxos.filter { $0.address == address }
                    let localUTXOs = addressUTXOs.map { LocalUTXO(from: $0) }
                    try await storage.saveUTXOs(localUTXOs)
                    logger.info("Synced \(localUTXOs.count) UTXOs for address: \(address)")
                } catch {
                    logger.error("Failed to sync UTXOs for address \(address): \(error)")
                }
                
                // Sync transactions
                do {
                    let transactions = try await syncDelegate.getTransactions(for: address)
                    let localTransactions = transactions.map { Transaction(from: $0) }
                    try await storage.saveTransactions(localTransactions)
                    logger.info("Synced \(localTransactions.count) transactions for address: \(address)")
                } catch {
                    logger.error("Failed to sync transactions for address \(address): \(error)")
                }
            } else {
                logger.warning("Sync delegate not available, skipping UTXO and transaction sync for address: \(address)")
            }
            
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
                let balance = LocalBalance(
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