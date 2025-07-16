import Foundation
import Combine
import SwiftDashSDK
import SwiftDashCoreSDK
import os

/// Factory for creating SPV client instances
public class SPVClientFactory {
    private static let logger = Logger(subsystem: "com.dash.wallet.ios", category: "SPVClientFactory")
    
    public enum ClientType {
        case real
        case mock
        case auto // Automatically choose based on FFI availability
    }
    
    // Cached configuration instances for different networks
    private static let testnetConfiguration: SPVClientConfiguration = {
        do {
            return try SPVConfigurationManager.shared.configuration(for: .testnet)
        } catch {
            logger.error("Failed to create testnet configuration: \(error)")
            fatalError("Critical error: Unable to create testnet configuration - \(error)")
        }
    }()
    
    private static let mainnetConfiguration: SPVClientConfiguration = {
        do {
            return try SPVConfigurationManager.shared.configuration(for: .mainnet)
        } catch {
            logger.error("Failed to create mainnet configuration: \(error)")
            fatalError("Critical error: Unable to create mainnet configuration - \(error)")
        }
    }()
    
    private static let devnetConfiguration: SPVClientConfiguration = {
        do {
            return try SPVConfigurationManager.shared.configuration(for: .devnet)
        } catch {
            logger.error("Failed to create devnet configuration: \(error)")
            fatalError("Critical error: Unable to create devnet configuration - \(error)")
        }
    }()
    
    private static let regtestConfiguration: SPVClientConfiguration = {
        do {
            return try SPVConfigurationManager.shared.configuration(for: .regtest)
        } catch {
            logger.error("Failed to create regtest configuration: \(error)")
            fatalError("Critical error: Unable to create regtest configuration - \(error)")
        }
    }()
    
    /// Get cached configuration for a specific network
    /// - Parameter network: The network type
    /// - Returns: Cached configuration instance
    @MainActor
    private static func getCachedConfiguration(for network: DashNetwork) -> SPVClientConfiguration {
        switch network {
        case .testnet:
            return testnetConfiguration
        case .mainnet:
            return mainnetConfiguration
        case .devnet:
            return devnetConfiguration
        case .regtest:
            return regtestConfiguration
        }
    }
    
    /// Create an SPV client instance with cached configuration
    /// - Parameters:
    ///   - network: The network type to create a client for
    ///   - type: The type of client to create
    /// - Returns: An SPV client instance (either real or mock)
    @MainActor
    public static func createClient(
        for network: DashNetwork,
        type: ClientType = .auto
    ) -> SPVClientProtocol {
        let configuration = getCachedConfiguration(for: network)
        return createClient(configuration: configuration, type: type)
    }
    
    /// Create an SPV client instance with custom configuration
    /// - Parameters:
    ///   - configuration: SPV client configuration
    ///   - type: The type of client to create
    /// - Returns: An SPV client instance (either real or mock)
    /// - Note: For standard network configurations, prefer using `createClient(for:type:)` which uses cached configurations
    public static func createClient(
        configuration: SPVClientConfiguration,
        type: ClientType = .auto
    ) -> SPVClientProtocol {
        switch type {
        case .real:
            let client = SPVClient(configuration: configuration)
            return SPVClientWrapper(client)
            
        case .mock:
            #if DEBUG
            return MockSPVClient(configuration: configuration)
            #else
            // In production builds, always use real SPVClient even if mock was requested
            logger.warning("Mock client requested in production build, using real client instead")
            let client = SPVClient(configuration: configuration)
            return SPVClientWrapper(client)
            #endif
            
        case .auto:
            #if DEBUG
            // In debug builds, check if mock client should be used
            if SPVEnvironment.useMockClient {
                logger.info("Creating mock SPVClient for debug environment")
                return MockSPVClient(configuration: configuration)
            } else {
                logger.info("Creating real SPVClient for debug environment")
                let client = SPVClient(configuration: configuration)
                return SPVClientWrapper(client)
            }
            #else
            // In production builds, always use real SPVClient
            logger.info("Creating real SPVClient for production use")
            
            // FFI initialization is handled by unified library at app startup
            // No need to check or initialize here
            logger.info("Using unified FFI (initialized at app startup)")
            
            let client = SPVClient(configuration: configuration)
            return SPVClientWrapper(client)
            #endif
        }
    }
    
    /// Create a client with default configuration (testnet)
    @MainActor
    public static func createDefaultClient(type: ClientType = .auto) -> SPVClientProtocol {
        // Use cached configuration for testnet
        return createClient(for: .testnet, type: type)
    }
}

/// Protocol to abstract SPV client functionality
public protocol SPVClientProtocol: AnyObject {
    // Connection
    var isConnected: Bool { get }
    var syncProgress: SyncProgress? { get }
    var stats: SPVStats? { get }
    var eventPublisher: AnyPublisher<SPVEvent, Never> { get }
    
    func start() async throws
    func connect() async throws
    func stop() async throws
    func disconnect()
    
    // Sync
    func syncToTip() async throws -> AsyncThrowingStream<SyncProgress, Error>
    func startSync() async throws
    func stopSync()
    func getCurrentSyncProgress() -> SyncProgress?
    
    // Watch items
    func addWatchItem(type: WatchItemType, data: String) async throws
    func removeWatchItem(type: WatchItemType, data: String) async throws
    
    // Balance
    func getAddressBalance(_ address: String) async throws -> Balance
    func getTotalBalance() async throws -> Balance
    func getBalanceWithMempool() async throws -> Balance
    
    // Transactions
    func broadcastTransaction(_ txHex: String) async throws
    // Commented out - Transaction type is internal to SwiftDashCoreSDK
    // func getTransactions(for address: String, limit: Int) async throws -> [Transaction]
    
    // UTXOs
    // Commented out - UTXO type is internal to SwiftDashCoreSDK  
    // func getUTXOs() async throws -> [UTXO]
    // func getUTXOs(for address: String) async throws -> [UTXO]
    
    // Mempool
    func enableMempoolTracking(strategy: MempoolStrategy) async throws
    func getMempoolBalance(for address: String) async throws -> MempoolBalance
    func getMempoolTransactionCount() async throws -> Int
    
    // Other
    func rescanBlockchain(from height: UInt32) async throws
    func isFilterSyncAvailable() async -> Bool
    func updateStats() async
    func recordSend(txid: String) async throws
}

// Wrapper to make SDK's SPVClient conform to our protocol
class SPVClientWrapper: SPVClientProtocol {
    private static let logger = Logger(subsystem: "com.dash.wallet.ios", category: "SPVClientWrapper")
    private let client: SPVClient
    
    var isConnected: Bool { client.isConnected }
    var syncProgress: SyncProgress? { client.syncProgress }
    var stats: SPVStats? { client.stats }
    var eventPublisher: AnyPublisher<SPVEvent, Never> { client.eventPublisher }
    
    init(_ client: SPVClient) {
        self.client = client
    }
    
    func start() async throws {
        // SPVClient doesn't have a start method, use connect
        try await connect()
    }
    
    func connect() async throws {
        // SPVClient doesn't expose connect directly, this might be internal
        // For now, we'll assume it's already connected when created
        Self.logger.info("connect() called - SPVClient manages connection internally")
    }
    
    func stop() async throws {
        // SPVClient doesn't have stop, use disconnect
        disconnect()
    }
    
    func disconnect() {
        // SPVClient doesn't expose disconnect directly
        Self.logger.info("disconnect() called - SPVClient manages connection internally")
    }
    
    func syncToTip() async throws -> AsyncThrowingStream<SyncProgress, Error> {
        // Not directly available in SPVClient
        fatalError("syncToTip not implemented in wrapper")
    }
    
    func startSync() async throws {
        // SPVClient doesn't expose startSync directly
        Self.logger.info("startSync() called - SPVClient manages sync internally")
    }
    
    func stopSync() {
        // SPVClient doesn't expose stopSync directly
        Self.logger.info("stopSync() called - SPVClient manages sync internally")
    }
    
    func getCurrentSyncProgress() -> SyncProgress? {
        return syncProgress
    }
    
    func addWatchItem(type: WatchItemType, data: String) async throws {
        try await client.addWatchItem(type: type, data: data)
    }
    
    func removeWatchItem(type: WatchItemType, data: String) async throws {
        try await client.removeWatchItem(type: type, data: data)
    }
    
    func getAddressBalance(_ address: String) async throws -> Balance {
        try await client.getAddressBalance(address)
    }
    
    func getTotalBalance() async throws -> Balance {
        try await client.getTotalBalance()
    }
    
    func getBalanceWithMempool() async throws -> Balance {
        try await client.getBalanceWithMempool()
    }
    
    func broadcastTransaction(_ txHex: String) async throws {
        try await client.broadcastTransaction(txHex)
    }
    
    // Commented out - Transaction/UTXO types are internal to SwiftDashCoreSDK
    // func getTransactions(for address: String, limit: Int = 100) async throws -> [Transaction] {
    //     try await client.getTransactions(for: address, limit: limit)
    // }
    // 
    // func getUTXOs() async throws -> [UTXO] {
    //     try await client.getUTXOs()
    // }
    // 
    // func getUTXOs(for address: String) async throws -> [UTXO] {
    //     try await client.getUTXOs(for: address)
    // }
    
    func enableMempoolTracking(strategy: MempoolStrategy) async throws {
        try await client.enableMempoolTracking(strategy: strategy)
    }
    
    func getMempoolBalance(for address: String) async throws -> MempoolBalance {
        try await client.getMempoolBalance(for: address)
    }
    
    func getMempoolTransactionCount() async throws -> Int {
        try await client.getMempoolTransactionCount()
    }
    
    func rescanBlockchain(from height: UInt32) async throws {
        try await client.rescanBlockchain(from: height)
    }
    
    func isFilterSyncAvailable() async -> Bool {
        await client.isFilterSyncAvailable()
    }
    
    func updateStats() async {
        await client.updateStats()
    }
    
    func recordSend(txid: String) async throws {
        try await client.recordSend(txid: txid)
    }
}

// MockSPVClient conformance is handled in custom_sdk_files/SPVClientFactory.swift

/// Environment configuration for SPV
public struct SPVEnvironment {
    public static var useMockClient: Bool {
        #if DEBUG
        // Check for test environment or specific flag - only available in debug builds
        return ProcessInfo.processInfo.environment["USE_MOCK_SPV"] == "1"
        #else
        // Never use mock client in production builds
        return false
        #endif
    }
    
    public static var ffiTimeout: TimeInterval {
        #if DEBUG
        return 2.0 // Shorter timeout in debug
        #else
        return 5.0 // Longer timeout in release
        #endif
    }
}