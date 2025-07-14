#if DEBUG
import Foundation
import Combine
import SwiftDashCoreSDK

/// Mock SPV Client for testing without FFI dependencies
@Observable
public class MockSPVClient {
    private let configuration: SPVClientConfiguration
    private var mockSyncProgress: SyncProgress?
    private var mockBalance = Balance(confirmed: 0, pending: 0, instantLocked: 0, total: 0)
    
    public private(set) var isConnected = false
    private var isSyncing = false
    private var currentHeight: UInt32 = 0
    private var peers: Int = 0
    public private(set) var syncProgress: SyncProgress?
    public private(set) var stats: SPVStats?
    
    // Event publisher for reactive updates
    private let eventSubject = PassthroughSubject<SPVEvent, Never>()
    public var eventPublisher: AnyPublisher<SPVEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }
    
    // Sync progress publisher
    private let progressSubject = PassthroughSubject<DetailedSyncProgress, Never>()
    public var progressPublisher: AnyPublisher<DetailedSyncProgress, Never> {
        progressSubject.eraseToAnyPublisher()
    }
    
    public init(configuration: SPVClientConfiguration) {
        print("🎭 MockSPVClient.init() - Running in mock mode")
        self.configuration = configuration
        
        // Simulate some initial state
        self.currentHeight = 1_900_000
        self.peers = 8
    }
    
    // MARK: - Connection Management
    
    public func start() async throws {
        try await connect()
    }
    
    public func connect() async throws {
        guard !isConnected else { return }
        
        print("🎭 MockSPVClient: Simulating connection...")
        
        // Simulate connection delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        isConnected = true
        peers = Int.random(in: 5...12)
        eventSubject.send(.connectionStatusChanged(true))
        
        print("🎭 MockSPVClient: Connected with \(peers) peers")
    }
    
    public func stop() async throws {
        disconnect()
    }
    
    public func disconnect() {
        guard isConnected else { return }
        
        isConnected = false
        isSyncing = false
        peers = 0
        
        eventSubject.send(.connectionStatusChanged(false))
        print("🎭 MockSPVClient: Disconnected")
    }
    
    // MARK: - Synchronization
    
    public func syncToTip() async throws -> AsyncThrowingStream<SyncProgress, Error> {
        guard isConnected else {
            throw SwiftDashCoreSDK.DashSDKError.notConnected
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                // Simulate sync progress
                let targetHeight: UInt32 = 2_000_000
                let startHeight = self.currentHeight
                let blocksToSync = targetHeight - startHeight
                
                for i in 0...10 {
                    let progress = Double(i) / 10.0
                    let currentBlock = startHeight + UInt32(Double(blocksToSync) * progress)
                    
                    let syncProgress = SyncProgress(
                        currentHeight: currentBlock,
                        totalHeight: targetHeight,
                        progress: progress,
                        status: progress < 1.0 ? .downloadingHeaders : .synced,
                        message: "Syncing... \(Int(progress * 100))%"
                    )
                    
                    self.currentHeight = currentBlock
                    self.syncProgress = syncProgress
                    continuation.yield(syncProgress)
                    
                    // Simulate delay between updates
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                }
                
                continuation.finish()
            }
        }
    }
    
    public func startSync() async throws {
        guard isConnected else {
            throw SwiftDashCoreSDK.DashSDKError.notConnected
        }
        
        guard !isSyncing else { return }
        
        isSyncing = true
        // SPVEvent doesn't have syncStarted - send sync progress instead
        let progress = SyncProgress(
            currentHeight: currentHeight,
            totalHeight: 2_000_000,
            progress: 0.0,
            status: .downloadingHeaders,
            message: "Sync started"
        )
        eventSubject.send(.syncProgressUpdated(progress))
        
        do {
            let stream = try await syncToTip()
            for try await progress in stream {
                // Progress updates are handled by the stream
            }
            isSyncing = false
            let completedProgress = SyncProgress(
                currentHeight: currentHeight,
                totalHeight: currentHeight,
                progress: 1.0,
                status: .synced,
                message: "Sync completed"
            )
            eventSubject.send(.syncProgressUpdated(completedProgress))
        } catch {
            isSyncing = false
            // Convert error to DashSDKError if possible, otherwise use generic
            if let sdkError = error as? SwiftDashCoreSDK.DashSDKError {
                eventSubject.send(.error(sdkError))
            } else {
                // Can't send non-SDK errors through event system
                print("🎭 MockSPVClient: Sync failed with error: \(error)")
            }
            throw error
        }
    }
    
    public func stopSync() {
        isSyncing = false
        print("🎭 MockSPVClient: Sync stopped")
    }
    
    public func getCurrentSyncProgress() -> SyncProgress? {
        return syncProgress
    }
    
    // MARK: - Watch Items
    
    public func addWatchItem(type: WatchItemType, data: String) async throws {
        print("🎭 MockSPVClient: Adding watch item - type: \(type), data: \(data)")
        // Simulate success
    }
    
    public func removeWatchItem(type: WatchItemType, data: String) async throws {
        print("🎭 MockSPVClient: Removing watch item - type: \(type), data: \(data)")
        // Simulate success
    }
    
    // MARK: - Balance Queries
    
    public func getAddressBalance(_ address: String) async throws -> Balance {
        print("🎭 MockSPVClient: Getting balance for address: \(address)")
        
        // Return mock balance
        return Balance(
            confirmed: 100_000_000, // 1 DASH
            pending: 0,
            instantLocked: 0,
            total: 100_000_000
        )
    }
    
    public func getTotalBalance() async throws -> Balance {
        return mockBalance
    }
    
    public func getBalanceWithMempool() async throws -> Balance {
        return mockBalance
    }
    
    // MARK: - Transaction Operations
    
    public func broadcastTransaction(_ txData: Data) async throws -> String {
        print("🎭 MockSPVClient: Broadcasting transaction (data: \(txData.count) bytes)")
        
        // Simulate broadcast delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Return mock txid
        let mockTxId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return mockTxId
    }
    
    public func broadcastTransaction(_ txHex: String) async throws {
        print("🎭 MockSPVClient: Broadcasting transaction (hex: \(txHex.prefix(20))...)")
        
        // Simulate broadcast delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Mock success - in real implementation, the txid would be obtained from the response
        print("🎭 MockSPVClient: Transaction broadcast successfully")
    }
    
    // MARK: - Mempool Operations
    
    public func enableMempoolTracking(strategy: MempoolStrategy) async throws {
        print("🎭 MockSPVClient: Enabling mempool tracking with strategy: \(strategy)")
        // Simulate success
    }
    
    public func getMempoolBalance(for address: String) async throws -> MempoolBalance {
        // MempoolBalance doesn't have a public initializer in the SDK
        // For mock purposes, throw a not implemented error
        // Use a generic error since we can't create MempoolBalance in mock
        struct MockError: Error {
            let message: String
        }
        throw MockError(message: "Mock mempool balance not available")
    }
    
    public func getMempoolTransactionCount() async throws -> Int {
        return Int.random(in: 0...50)
    }
    
    // MARK: - Additional Methods
    
    public func rescanBlockchain(from height: UInt32) async throws {
        print("🎭 MockSPVClient: Rescanning blockchain from height: \(height)")
        currentHeight = height
        try await startSync()
    }
    
    public func isFilterSyncAvailable() async -> Bool {
        return true
    }
    
    public func updateStats() async {
        stats = SPVStats(
            connectedPeers: UInt32(peers),
            headerHeight: currentHeight
        )
    }
    
    public func syncToTipWithProgress(
        progressCallback: (@Sendable (DetailedSyncProgress) -> Void)? = nil,
        completionCallback: (@Sendable (Bool, String?) -> Void)? = nil
    ) async throws {
        do {
            try await startSync()
            completionCallback?(true, nil)
        } catch {
            completionCallback?(false, error.localizedDescription)
            throw error
        }
    }
    
    public func syncProgressStream() -> SyncProgressStream {
        return SyncProgressStream(client: self)
    }
    
    public func recordSend(txid: String) async throws {
        print("🎭 MockSPVClient: Recording send: \(txid)")
    }
}

// MARK: - Mock Extensions

extension MockSPVClient {
    /// Simulate receiving a transaction
    public func simulateTransactionReceived(amount: Int64, confirmed: Bool = false) {
        let txid = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let event = SPVEvent.transactionReceived(
            txid: txid,
            confirmed: confirmed,
            amount: amount,
            addresses: ["yXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"],
            blockHeight: confirmed ? currentHeight : nil
        )
        eventSubject.send(event)
        
        // Update balance
        if confirmed {
            mockBalance = Balance(
                confirmed: mockBalance.confirmed + UInt64(abs(amount)),
                pending: mockBalance.pending,
                instantLocked: mockBalance.instantLocked,
                total: mockBalance.total + UInt64(abs(amount))
            )
            eventSubject.send(.balanceUpdated(mockBalance))
        }
    }
    
    /// Set mock balance
    public func setMockBalance(_ balance: Balance) {
        mockBalance = balance
        eventSubject.send(.balanceUpdated(balance))
    }
}

// MARK: - SyncProgressStream Support

extension MockSPVClient {
    public struct SyncProgressStream: AsyncSequence {
        public typealias Element = DetailedSyncProgress
        
        private let client: MockSPVClient
        
        init(client: MockSPVClient) {
            self.client = client
        }
        
        public func makeAsyncIterator() -> AsyncIterator {
            return AsyncIterator(client: client)
        }
        
        public struct AsyncIterator: AsyncIteratorProtocol {
            private let client: MockSPVClient
            private var isComplete = false
            
            init(client: MockSPVClient) {
                self.client = client
            }
            
            public mutating func next() async -> DetailedSyncProgress? {
                guard !isComplete else { return nil }
                
                // Simulate progress update
                isComplete = true
                
                return DetailedSyncProgress(
                    currentHeight: client.currentHeight,
                    totalHeight: 2_000_000,
                    percentage: 95.0,
                    headersPerSecond: 1000.0,
                    estimatedSecondsRemaining: 30,
                    stage: .downloading,
                    stageMessage: "Mock sync in progress...",
                    connectedPeers: UInt32(client.peers),
                    totalHeadersProcessed: UInt64(client.currentHeight),
                    syncStartTimestamp: Date()
                )
            }
        }
    }
}
#endif