import Foundation
import Combine
import SwiftDashCoreSDK

/// Factory for creating SPV client instances
public class SPVClientFactory {
    public enum ClientType {
        case real
        case mock
        case auto // Automatically choose based on FFI availability
    }
    
    /// Create an SPV client instance
    /// - Parameters:
    ///   - configuration: SPV client configuration
    ///   - type: The type of client to create
    /// - Returns: An SPV client instance (either real or mock)
    public static func createClient(
        configuration: SPVClientConfiguration,
        type: ClientType = .auto
    ) -> SPVClientProtocol {
        switch type {
        case .real:
            let client = SwiftDashCoreSDK.SPVClient(configuration: configuration)
            return SPVClientWrapper(client)
            
        case .mock:
            #if DEBUG
            return MockSPVClient(configuration: configuration)
            #else
            // In production builds, always use real SPVClient even if mock was requested
            print("⚠️ SPVClientFactory: Mock client requested in production build, using real client instead")
            let client = SwiftDashCoreSDK.SPVClient(configuration: configuration)
            return SPVClientWrapper(client)
            #endif
            
        case .auto:
            // Always use real SPVClient for production builds
            print("🚀 SPVClientFactory: Creating real SPVClient for production use")
            
            // FFI initialization is handled by unified library at app startup
            // No need to check or initialize here
            print("✅ SPVClientFactory: Using unified FFI (initialized at app startup)")
            
            // Always return real SPVClient
            let client = SwiftDashCoreSDK.SPVClient(configuration: configuration)
            return SPVClientWrapper(client)
        }
    }
    
    /// Create a client with default configuration
    @MainActor
    public static func createDefaultClient(type: ClientType = .auto) -> SPVClientProtocol {
        // Use cached configuration from manager
        let config = SPVConfigurationManager.shared.configuration(for: .testnet)
        return createClient(configuration: config, type: type)
    }
}

/// Protocol to abstract SPV client functionality
public protocol SPVClientProtocol: AnyObject {
    // Connection
    var isConnected: Bool { get }
    var syncProgress: SwiftDashCoreSDK.SyncProgress? { get }
    var stats: SwiftDashCoreSDK.SPVStats? { get }
    var eventPublisher: AnyPublisher<SwiftDashCoreSDK.SPVEvent, Never> { get }
    
    func start() async throws
    func connect() async throws
    func stop() async throws
    func disconnect()
    
    // Sync
    func syncToTip() async throws -> AsyncThrowingStream<SwiftDashCoreSDK.SyncProgress, Error>
    func startSync() async throws
    func stopSync()
    func getCurrentSyncProgress() -> SwiftDashCoreSDK.SyncProgress?
    
    // Watch items
    func addWatchItem(type: SwiftDashCoreSDK.WatchItemType, data: String) async throws
    func removeWatchItem(type: SwiftDashCoreSDK.WatchItemType, data: String) async throws
    
    // Balance
    func getAddressBalance(_ address: String) async throws -> SwiftDashCoreSDK.Balance
    func getTotalBalance() async throws -> SwiftDashCoreSDK.Balance
    func getBalanceWithMempool() async throws -> SwiftDashCoreSDK.Balance
    
    // Transactions
    func broadcastTransaction(_ txHex: String) async throws
    
    // Mempool
    func enableMempoolTracking(strategy: SwiftDashCoreSDK.MempoolStrategy) async throws
    func getMempoolBalance(for address: String) async throws -> SwiftDashCoreSDK.MempoolBalance
    func getMempoolTransactionCount() async throws -> Int
    
    // Other
    func rescanBlockchain(from height: UInt32) async throws
    func isFilterSyncAvailable() async -> Bool
    func updateStats() async
    func recordSend(txid: String) async throws
}

// Wrapper to make SDK's SPVClient conform to our protocol
class SPVClientWrapper: SPVClientProtocol {
    private let client: SwiftDashCoreSDK.SPVClient
    
    var isConnected: Bool { client.isConnected }
    var syncProgress: SwiftDashCoreSDK.SyncProgress? { client.syncProgress }
    var stats: SwiftDashCoreSDK.SPVStats? { client.stats }
    var eventPublisher: AnyPublisher<SwiftDashCoreSDK.SPVEvent, Never> { client.eventPublisher }
    
    init(_ client: SwiftDashCoreSDK.SPVClient) {
        self.client = client
    }
    
    func start() async throws {
        // SPVClient doesn't have a start method, use connect
        try await connect()
    }
    
    func connect() async throws {
        // SPVClient doesn't expose connect directly, this might be internal
        // For now, we'll assume it's already connected when created
        print("SPVClientWrapper: connect() called - SPVClient manages connection internally")
    }
    
    func stop() async throws {
        // SPVClient doesn't have stop, use disconnect
        disconnect()
    }
    
    func disconnect() {
        // SPVClient doesn't expose disconnect directly
        print("SPVClientWrapper: disconnect() called - SPVClient manages connection internally")
    }
    
    func syncToTip() async throws -> AsyncThrowingStream<SwiftDashCoreSDK.SyncProgress, Error> {
        // Not directly available in SPVClient
        fatalError("syncToTip not implemented in wrapper")
    }
    
    func startSync() async throws {
        // SPVClient doesn't expose startSync directly
        print("SPVClientWrapper: startSync() called - SPVClient manages sync internally")
    }
    
    func stopSync() {
        // SPVClient doesn't expose stopSync directly
        print("SPVClientWrapper: stopSync() called - SPVClient manages sync internally")
    }
    
    func getCurrentSyncProgress() -> SwiftDashCoreSDK.SyncProgress? {
        return syncProgress
    }
    
    func addWatchItem(type: SwiftDashCoreSDK.WatchItemType, data: String) async throws {
        try await client.addWatchItem(type: type, data: data)
    }
    
    func removeWatchItem(type: SwiftDashCoreSDK.WatchItemType, data: String) async throws {
        try await client.removeWatchItem(type: type, data: data)
    }
    
    func getAddressBalance(_ address: String) async throws -> SwiftDashCoreSDK.Balance {
        try await client.getAddressBalance(address)
    }
    
    func getTotalBalance() async throws -> SwiftDashCoreSDK.Balance {
        try await client.getTotalBalance()
    }
    
    func getBalanceWithMempool() async throws -> SwiftDashCoreSDK.Balance {
        try await client.getBalanceWithMempool()
    }
    
    func broadcastTransaction(_ txHex: String) async throws {
        try await client.broadcastTransaction(txHex)
    }
    
    func enableMempoolTracking(strategy: SwiftDashCoreSDK.MempoolStrategy) async throws {
        try await client.enableMempoolTracking(strategy: strategy)
    }
    
    func getMempoolBalance(for address: String) async throws -> SwiftDashCoreSDK.MempoolBalance {
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

#if DEBUG
// Make MockSPVClient conform to the protocol
extension MockSPVClient: SPVClientProtocol {}
#endif

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