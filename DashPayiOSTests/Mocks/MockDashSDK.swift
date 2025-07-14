import Foundation
@testable import DashPay
import SwiftDashCoreSDK
import Combine

// Mock implementation of DashSDKProtocol for testing
class MockDashSDK: DashSDKProtocol {
    var isConnected = false
    var balance: SwiftDashCoreSDK.Balance = SwiftDashCoreSDK.Balance(confirmed: 0, pending: 0, instantLocked: 0, mempool: 0, mempoolInstant: 0, total: 0)
    var syncProgress: SyncProgress?
    var eventPublisher = PassthroughSubject<SPVEvent, Never>()
    
    func connect() async throws {
        isConnected = true
    }
    
    func disconnect() async throws {
        isConnected = false
    }
    
    func sync() async throws {
        // Mock sync
    }
    
    func stopSync() {
        // Mock stop
    }
    
    func getBalance(for address: String) async throws -> SwiftDashCoreSDK.Balance {
        return balance
    }
    
    func getNewAddress() async throws -> String {
        return "yMockAddress123"
    }
    
    func sendTransaction(to address: String, amount: UInt64, fee: UInt64) async throws -> String {
        return "mockTxId123"
    }
    
    // DashSDKProtocol methods
    func createTransaction(to: String, amount: UInt64, isAssetLock: Bool) async throws -> SwiftDashCoreSDK.Transaction {
        return SwiftDashCoreSDK.Transaction(
            txid: "mockTx123",
            height: nil,
            timestamp: Date(),
            amount: Int64(amount),
            fee: 1000,
            confirmations: 0,
            isInstantLocked: false,
            raw: Data(),
            size: 250,
            version: 2
        )
    }
    
    func createAssetLockTransaction(amount: UInt64) async throws -> SwiftDashCoreSDK.Transaction {
        return SwiftDashCoreSDK.Transaction(
            txid: "mockAssetLockTx",
            height: nil,
            timestamp: Date(),
            amount: Int64(amount),
            fee: 1000,
            confirmations: 0,
            isInstantLocked: false,
            raw: Data(),
            size: 250,
            version: 2
        )
    }
    
    func watchAddress(_ address: String, label: String?) async throws {
        // Mock watch
    }
    
    func unwatchAddress(_ address: String) async throws {
        // Mock unwatch
    }
    
    func getTransactions(for address: String) async throws -> [SwiftDashCoreSDK.Transaction] {
        return []
    }
    
    func generateMnemonic() -> String {
        return "mock mnemonic phrase for testing purposes only not real seed words"
    }
    
    func validateMnemonic(_ mnemonic: String) -> Bool {
        return !mnemonic.isEmpty
    }
    
    func syncProgressStream() -> AsyncStream<DetailedSyncProgress> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    
    func broadcastTransaction(_ tx: SwiftDashCoreSDK.Transaction) async throws -> String {
        return tx.txid
    }
    
    func getInstantLock(for txid: String) async throws -> InstantLock? {
        return InstantLock(txid: txid, height: 1000, signature: Data())
    }
    
    func waitForInstantLockResult(txid: String, timeout: TimeInterval) async throws -> InstantLock {
        return InstantLock(txid: txid, height: 1000, signature: Data())
    }
}