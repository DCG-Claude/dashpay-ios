import Foundation
import SwiftData
import SwiftDashCoreSDK

@Observable
final class StorageManager {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let backgroundContext: ModelContext
    
    @MainActor
    init(modelContainer: ModelContainer) throws {
        self.modelContainer = modelContainer
        self.modelContext = modelContainer.mainContext
        self.backgroundContext = ModelContext(modelContainer)
        
        // Configure contexts
        modelContext.autosaveEnabled = true
        backgroundContext.autosaveEnabled = false
    }
    
    // MARK: - Watched Addresses
    
    func saveWatchedAddress(_ address: HDWatchedAddress) throws {
        modelContext.insert(address)
        try modelContext.save()
    }
    
    func fetchWatchedAddresses() throws -> [HDWatchedAddress] {
        let descriptor = FetchDescriptor<HDWatchedAddress>(
            sortBy: [SortDescriptor(\.index, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func fetchWatchedAddress(by address: String) throws -> HDWatchedAddress? {
        let predicate = #Predicate<HDWatchedAddress> { watchedAddress in
            watchedAddress.address == address
        }
        
        let descriptor = FetchDescriptor<HDWatchedAddress>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }
    
    func deleteWatchedAddress(_ address: HDWatchedAddress) throws {
        modelContext.delete(address)
        try modelContext.save()
    }
    
    // MARK: - Transactions
    
    func saveTransaction(_ transaction: Transaction) throws {
        modelContext.insert(transaction)
        try modelContext.save()
    }
    
    func saveTransactions(_ transactions: [Transaction]) async throws {
        for transaction in transactions {
            backgroundContext.insert(transaction)
        }
        try backgroundContext.save()
    }
    
    func fetchTransactions(
        for address: String? = nil,
        limit: Int = 100,
        offset: Int = 0
    ) throws -> [Transaction] {
        var descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        if let address = address {
            // Filter by address if needed
            // This would require a relationship or additional field to filter by address
        }
        
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        
        return try modelContext.fetch(descriptor)
    }
    
    func fetchTransaction(by txid: String) throws -> Transaction? {
        let predicate = #Predicate<Transaction> { transaction in
            transaction.txid == txid
        }
        
        let descriptor = FetchDescriptor<Transaction>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }
    
    func updateTransaction(_ transaction: Transaction) throws {
        try modelContext.save()
    }
    
    // MARK: - UTXOs
    
    func saveUTXO(_ utxo: LocalUTXO) throws {
        modelContext.insert(utxo)
        try modelContext.save()
    }
    
    func saveUTXOs(_ utxos: [LocalUTXO]) async throws {
        for utxo in utxos {
            backgroundContext.insert(utxo)
        }
        try backgroundContext.save()
    }
    
    func fetchUTXOs(
        for address: String? = nil,
        includeSpent: Bool = false
    ) throws -> [LocalUTXO] {
        var predicate: Predicate<LocalUTXO>?
        
        if let address = address {
            if includeSpent {
                predicate = #Predicate<LocalUTXO> { utxo in
                    utxo.address == address
                }
            } else {
                predicate = #Predicate<LocalUTXO> { utxo in
                    utxo.address == address && !utxo.isSpent
                }
            }
        } else if !includeSpent {
            predicate = #Predicate<LocalUTXO> { utxo in
                !utxo.isSpent
            }
        }
        
        let descriptor = FetchDescriptor<LocalUTXO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.value, order: .reverse)]
        )
        
        return try modelContext.fetch(descriptor)
    }
    
    func markUTXOAsSpent(outpoint: String) throws {
        let predicate = #Predicate<LocalUTXO> { utxo in
            utxo.outpoint == outpoint
        }
        
        let descriptor = FetchDescriptor<LocalUTXO>(predicate: predicate)
        if let utxo = try modelContext.fetch(descriptor).first {
            utxo.isSpent = true
            try modelContext.save()
        }
    }
    
    // MARK: - Balance
    
    func saveBalance(_ balance: LocalBalance, for address: String) throws {
        if let watchedAddress = try fetchWatchedAddress(by: address) {
            watchedAddress.balance = balance
            try modelContext.save()
        }
    }
    
    func fetchBalance(for address: String) throws -> LocalBalance? {
        let watchedAddress = try fetchWatchedAddress(by: address)
        return watchedAddress?.balance
    }
    
    // MARK: - Batch Operations
    
    func performBatchUpdate<T>(
        _ updates: @escaping () throws -> T
    ) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let result = try updates()
                    try self.backgroundContext.save()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Cleanup
    
    func deleteAllData() throws {
        try modelContext.delete(model: HDWatchedAddress.self)
        try modelContext.delete(model: Transaction.self)
        try modelContext.delete(model: LocalUTXO.self)
        try modelContext.delete(model: Balance.self)
        try modelContext.save()
    }
    
    func pruneOldTransactions(olderThan date: Date) throws {
        let predicate = #Predicate<Transaction> { transaction in
            transaction.timestamp < date
        }
        
        try modelContext.delete(model: Transaction.self, where: predicate)
        try modelContext.save()
    }
    
    // MARK: - Statistics
    
    func getStorageStatistics() throws -> StorageStatistics {
        let addressCount = try modelContext.fetchCount(FetchDescriptor<HDWatchedAddress>())
        let transactionCount = try modelContext.fetchCount(FetchDescriptor<Transaction>())
        let utxoCount = try modelContext.fetchCount(FetchDescriptor<LocalUTXO>())
        
        let spentUTXOPredicate = #Predicate<LocalUTXO> { $0.isSpent }
        let spentUTXOCount = try modelContext.fetchCount(
            FetchDescriptor<LocalUTXO>(predicate: spentUTXOPredicate)
        )
        
        return StorageStatistics(
            watchedAddressCount: addressCount,
            transactionCount: transactionCount,
            totalUTXOCount: utxoCount,
            spentUTXOCount: spentUTXOCount,
            unspentUTXOCount: utxoCount - spentUTXOCount
        )
    }
}

// MARK: - Storage Statistics

public struct StorageStatistics {
    let watchedAddressCount: Int
    let transactionCount: Int
    let totalUTXOCount: Int
    let spentUTXOCount: Int
    let unspentUTXOCount: Int
    
    var description: String {
        """
        Storage Statistics:
        - Watched Addresses: \(watchedAddressCount)
        - Transactions: \(transactionCount)
        - Total UTXOs: \(totalUTXOCount)
        - Spent UTXOs: \(spentUTXOCount)
        - Unspent UTXOs: \(unspentUTXOCount)
        """
    }
}