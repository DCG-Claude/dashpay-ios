import Foundation
import Combine
import SwiftData
import SwiftDashCoreSDK

@Observable
public final class DashSDK {
    private let client: SwiftDashCoreSDK.SPVClient
    private let wallet: PersistentWalletManager
    // Storage is not needed in this wrapper - wallet manager has its own storage
    private let configuration: SwiftDashCoreSDK.SPVClientConfiguration
    
    public var isConnected: Bool {
        client.isConnected
    }
    
    public var syncProgress: SwiftDashCoreSDK.SyncProgress? {
        client.syncProgress
    }
    
    public var stats: SwiftDashCoreSDK.SPVStats? {
        client.stats
    }
    
    public var watchedAddresses: Set<String> {
        wallet.watchedAddresses
    }
    
    public var totalBalance: SwiftDashCoreSDK.Balance {
        wallet.totalBalance
    }
    
    public var eventPublisher: AnyPublisher<SwiftDashCoreSDK.SPVEvent, Never> {
        client.eventPublisher
    }
    
    // Platform integration property
    public var spvClient: SwiftDashCoreSDK.SPVClient {
        client
    }
    
    @MainActor
    public init(configuration: SwiftDashCoreSDK.SPVClientConfiguration = .default) throws {
        print("🔵 DashSDK.init() starting...")
        print("🔵 Configuration: \(configuration)")
        print("🔵 Network: \(configuration.network.name)")
        
        self.configuration = configuration
        
        // Validate configuration first
        do {
            try configuration.validate()
            print("✅ Configuration validated")
        } catch {
            print("🔴 Configuration validation failed: \(error)")
            throw DashSDKError.invalidConfiguration("Configuration validation failed: \(error.localizedDescription)")
        }
        
        // Storage is handled internally by PersistentWalletManager
        // No need to create a separate StorageManager here
        
        print("🔵 Creating SPVClient with network: \(configuration.network.name)...")
        self.client = SwiftDashCoreSDK.SPVClient(configuration: configuration)
        print("✅ SPVClient created (using unified FFI)")
        
        print("🔵 Creating PersistentWalletManager...")
        // PersistentWalletManager requires StorageManager
        // For now, create a minimal storage manager inline
        print("🔵 Creating minimal StorageManager for PersistentWalletManager...")
        do {
            // Create a minimal model container for wallet persistence
            let schema = Schema([LocalBalance.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            let storage = try StorageManager(modelContainer: modelContainer)
            self.wallet = PersistentWalletManager(client: client, storage: storage)
            print("✅ PersistentWalletManager created with in-memory storage")
        } catch {
            print("🔴 Failed to create wallet manager: \(error)")
            throw DashSDKError.storageError("Failed to create wallet manager: \(error.localizedDescription)")
        }
        print("✅ PersistentWalletManager created")
        
        print("✅ DashSDK.init() completed successfully")
    }
    
    // MARK: - Connection Management
    
    public func connect() async throws {
        try await client.start()
        
        // Re-sync persisted addresses with SPV client
        await syncPersistedAddresses()
        
        wallet.startPeriodicSync()
    }
    
    public func disconnect() async throws {
        wallet.stopPeriodicSync()
        try await client.stop()
    }
    
    // MARK: - Synchronization
    
    public func syncToTip() async throws -> AsyncThrowingStream<SyncProgress, Error> {
        return try await client.syncToTip()
    }
    
    public func rescanBlockchain(from height: UInt32 = 0) async throws {
        try await client.rescanBlockchain(from: height)
    }
    
    // MARK: - Enhanced Sync Operations
    
    public func syncToTipWithProgress(
        progressCallback: (@Sendable (DetailedSyncProgress) -> Void)? = nil,
        completionCallback: (@Sendable (Bool, String?) -> Void)? = nil
    ) async throws {
        try await client.syncToTipWithProgress(
            progressCallback: progressCallback,
            completionCallback: completionCallback
        )
    }
    
    public func syncProgressStream() -> SyncProgressStream {
        return client.syncProgressStream()
    }
    
    // MARK: - Wallet Operations
    
    public func watchAddress(_ address: String, label: String? = nil) async throws {
        try await wallet.watchAddress(address, label: label)
    }
    
    public func watchAddresses(_ addresses: [String]) async throws {
        for address in addresses {
            try await wallet.watchAddress(address)
        }
    }
    
    public func unwatchAddress(_ address: String) async throws {
        try await wallet.unwatchAddress(address)
    }
    
    public func addWatchItem(type: WatchItemType, data: String) async throws {
        try await client.addWatchItem(type: type, data: data)
    }
    
    public func removeWatchItem(type: WatchItemType, data: String) async throws {
        try await client.removeWatchItem(type: type, data: data)
    }
    
    public func getBalance() async throws -> Balance {
        return try await wallet.getTotalBalance()
    }
    
    public func getBalance(for address: String) async throws -> Balance {
        return try await wallet.getBalance(for: address)
    }
    
    public func getBalanceWithMempool() async throws -> Balance {
        return try await client.getBalanceWithMempool()
    }
    
    public func getBalanceWithMempool(for address: String) async throws -> Balance {
        // Get confirmed balance from wallet
        let confirmedBalance = try await wallet.getBalance(for: address)
        
        // Get mempool balance from SPV client
        let mempoolBalance = try await client.getMempoolBalance(for: address)
        
        // Combine confirmed and mempool balances
        return Balance(
            confirmed: confirmedBalance.confirmed,
            pending: confirmedBalance.pending + mempoolBalance.pending,
            instantLocked: confirmedBalance.instantLocked + mempoolBalance.pendingInstant,
            total: confirmedBalance.confirmed + confirmedBalance.pending + mempoolBalance.pending
        )
    }
    
    // Transaction type is internal, cannot be exposed in public API
    // This would need to return SDK's Transaction type or a public wrapper
    internal func getTransactions(limit: Int = 100) async throws -> [SwiftDashCoreSDK.Transaction] {
        return try await wallet.getTransactions(limit: limit)
    }
    
    // Transaction type is internal, cannot be exposed in public API
    internal func getTransactions(for address: String, limit: Int = 100) async throws -> [SwiftDashCoreSDK.Transaction] {
        return try await wallet.getTransactions(for: address, limit: limit)
    }
    
    public func getUTXOs() async throws -> [UTXO] {
        return try await wallet.getUTXOs()
    }
    
    // MARK: - Mempool Operations
    
    public func enableMempoolTracking(strategy: MempoolStrategy) async throws {
        try await client.enableMempoolTracking(strategy: strategy)
    }
    
    public func getMempoolBalance(for address: String) async throws -> MempoolBalance {
        return try await client.getMempoolBalance(for: address)
    }
    
    public func getMempoolTransactionCount() async throws -> Int {
        return try await client.getMempoolTransactionCount()
    }
    
    // MARK: - Transaction Management
    
    public func sendTransaction(
        to address: String,
        amount: UInt64,
        feeRate: UInt64 = 1000
    ) async throws -> String {
        // Create transaction
        let txData = try await wallet.createTransaction(
            to: address,
            amount: amount,
            feeRate: feeRate
        )
        
        // Broadcast transaction
        let txHex = txData.map { String(format: "%02x", $0) }.joined()
        try await client.broadcastTransaction(txHex)
        
        // For now, return a placeholder - the actual txid should come from parsing the transaction
        return "transaction_sent"
    }
    
    public func estimateFee(
        to address: String,
        amount: UInt64,
        feeRate: UInt64 = 1000
    ) async throws -> UInt64 {
        let utxos = try await wallet.getSpendableUTXOs()
        // For now, estimate fee manually without TransactionBuilder
        // This is a simplified estimation
        
        // Estimate inputs needed
        var inputCount = 0
        var totalInput: UInt64 = 0
        
        for utxo in utxos.sorted(by: { $0.value > $1.value }) {
            inputCount += 1
            totalInput += utxo.value
            
            if totalInput >= amount {
                break
            }
        }
        
        // 1 output for recipient, 1 for change
        let outputCount = 2
        
        // Estimate transaction size:
        // ~148 bytes per input + ~34 bytes per output + ~10 bytes overhead
        let estimatedSize = (inputCount * 148) + (outputCount * 34) + 10
        
        // Calculate fee
        let fee = UInt64(estimatedSize) * feeRate / 1000
        
        return fee
    }
    
    // MARK: - Data Management
    
    public func refreshData() async {
        await wallet.syncAllData()
    }
    
    // Storage statistics not available without StorageManager
    // public func getStorageStatistics() throws -> StorageStatistics {
    //     return try wallet.getStorageStatistics()
    // }
    
    public func clearAllData() throws {
        try wallet.clearAllData()
    }
    
    // WalletExportData is internal, cannot be exposed in public API
    internal func exportWalletData() throws -> WalletExportData {
        return try wallet.exportWalletData()
    }
    
    // WalletExportData is internal, cannot be exposed in public API
    internal func importWalletData(_ data: WalletExportData) async throws {
        try await wallet.importWalletData(data)
    }
    
    // MARK: - Network Information
    
    public func isFilterSyncAvailable() async -> Bool {
        return await client.isFilterSyncAvailable()
    }
    
    public func validateAddress(_ address: String) -> Bool {
        // Basic validation - would call FFI function
        return address.starts(with: "X") || address.starts(with: "y")
    }
    
    public func getNetworkInfo() -> NetworkInfo {
        return NetworkInfo(
            network: client.configuration.network,
            isConnected: client.isConnected,
            connectedPeers: client.stats?.connectedPeers ?? 0,
            blockHeight: client.stats?.headerHeight ?? 0
        )
    }
    
    // MARK: - Private Helpers
    
    private func syncPersistedAddresses() async {
        // This triggers the PersistentWalletManager to reload addresses
        // and re-watch them in the SPV client
        await wallet.syncAllData()
    }
}

// MARK: - Network Info

public struct NetworkInfo {
    public let network: DashNetwork
    public let isConnected: Bool
    public let connectedPeers: UInt32
    public let blockHeight: UInt32
    
    public var description: String {
        """
        Network: \(network.name)
        Connected: \(isConnected)
        Peers: \(connectedPeers)
        Block Height: \(blockHeight)
        """
    }
}

// MARK: - Convenience Extensions

extension DashSDK {
    @MainActor
    public static func mainnet() throws -> DashSDK {
        return try DashSDK(configuration: .mainnet())
    }
    
    @MainActor
    public static func testnet() throws -> DashSDK {
        return try DashSDK(configuration: .testnet())
    }
    
    @MainActor
    public static func regtest() throws -> DashSDK {
        return try DashSDK(configuration: .regtest())
    }
    
    @MainActor
    public static func devnet() throws -> DashSDK {
        return try DashSDK(configuration: .devnet())
    }
}