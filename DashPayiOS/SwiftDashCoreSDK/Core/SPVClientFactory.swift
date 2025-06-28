import Foundation
import Combine

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
            return SPVClient(configuration: configuration)
            
        case .mock:
            #if DEBUG
            return MockSPVClient(configuration: configuration)
            #else
            // In production builds, always use real SPVClient even if mock was requested
            print("⚠️ SPVClientFactory: Mock client requested in production build, using real client instead")
            return SPVClient(configuration: configuration)
            #endif
            
        case .auto:
            // Always use real SPVClient for production builds
            print("🚀 SPVClientFactory: Creating real SPVClient for production use")
            
            // Ensure FFI is initialized
            if !FFIInitializer.initialized {
                print("🔧 SPVClientFactory: FFI not yet initialized, initializing now...")
                let ffiInitialized = FFIInitializer.tryInitialize(logLevel: configuration.logLevel)
                
                if ffiInitialized {
                    print("✅ SPVClientFactory: FFI initialized successfully")
                } else {
                    print("⚠️ SPVClientFactory: FFI initialization failed - continuing anyway")
                    print("⚠️ The SPVClient will handle initialization internally")
                }
            } else {
                print("✅ SPVClientFactory: FFI already initialized")
            }
            
            // Always return real SPVClient
            return SPVClient(configuration: configuration)
        }
    }
    
    /// Create a client with default configuration
    public static func createDefaultClient(type: ClientType = .auto) -> SPVClientProtocol {
        let config = SPVClientConfiguration.testnet()
        return createClient(configuration: config, type: type)
    }
}

/// Protocol to abstract SPV client functionality
public protocol SPVClientProtocol: AnyObject {
    // Connection
    var isConnected: Bool { get }
    var isSyncing: Bool { get }
    var currentHeight: UInt32 { get }
    var peers: Int { get }
    var syncProgress: SyncProgress? { get }
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
    func broadcastTransaction(_ txData: Data) async throws -> String
    func broadcastTransaction(_ txHex: String) async throws -> String
    
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

// Make SPVClient conform to the protocol
extension SPVClient: SPVClientProtocol {}

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