import Foundation
import SwiftDashCoreSDK

// MARK: - Local Asset Lock Error Types
enum DashSDKAssetLockError: LocalizedError {
    case invalidAmount(String)
    case insufficientBalance
    case instantLockTimeout
    case transactionNotFound
    case assetLockGenerationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidAmount(let reason):
            return "Invalid amount: \(reason)"
        case .insufficientBalance:
            return "Insufficient balance for asset lock transaction"
        case .instantLockTimeout:
            return "Timeout waiting for InstantSend lock"
        case .transactionNotFound:
            return "Transaction not found"
        case .assetLockGenerationFailed:
            return "Failed to generate asset lock"
        }
    }
}

// MARK: - Type Aliases for Consistency
// Use the same types as AssetLockBridge to avoid conflicts

// MARK: - Asset Lock Extension
// Asset lock implementation using DashSDK public API only

extension DashSDK {
    
    /// Create an asset lock transaction using public API only
    public func createAssetLockTransactionWithValidation(amount: UInt64) async throws -> SwiftDashCoreSDK.Transaction {
        print("🔒 Creating asset lock transaction for \(amount) satoshis using public API")
        
        // Validate minimum amount for asset lock (10,000 duffs)
        guard amount >= 10_000 else {
            throw DashSDKAssetLockError.invalidAmount("Asset lock amount must be at least 10,000 duffs")
        }
        
        // Check available balance using public API
        let balance = try await getBalance()
        let estimatedFee = try await estimateFee(to: "yP8A3q8vhQNZNrxJQgJ7VjSkZ5EjyzMEvH", amount: amount, feeRate: 2000)
        let totalRequired = amount + estimatedFee
        
        guard balance.confirmed >= totalRequired else {
            throw DashSDKAssetLockError.insufficientBalance
        }
        
        print("✅ Balance validated: \(balance.confirmed) >= \(totalRequired)")
        
        // Generate asset lock address using public API
        let assetLockAddress = try await generateAssetLockAddressFromWatchedAddresses()
        print("🏠 Generated asset lock address: \(assetLockAddress)")
        
        // Create the asset lock transaction using sendTransaction (public API)
        let txid = try await sendTransaction(
            to: assetLockAddress,
            amount: amount,
            feeRate: 2000
        )
        
        print("✅ Asset lock transaction created: \(txid)")
        
        // Create and return SwiftDashCoreSDK.Transaction using public API data
        // Note: Raw transaction data is not available from the sendTransaction public API
        // The size is estimated based on typical asset lock transaction characteristics
        let estimatedTransactionSize: UInt32 = 250 // Typical asset lock transaction size
        let transaction = SwiftDashCoreSDK.Transaction(
            txid: txid,
            height: nil,
            timestamp: Date(),
            amount: Int64(amount),
            fee: estimatedFee,
            confirmations: 0,
            isInstantLocked: false,
            raw: Data(), // Empty: raw data not available from public API
            size: estimatedTransactionSize,
            version: 3 // Asset lock transactions use version 3
        )
        
        return transaction
    }
    
    /// Create an asset lock transaction result using public API only
    public func createAssetLockTransactionResult(
        amount: UInt64,
        feeRate: UInt64 = 2000
    ) async throws -> AssetLockTransactionResult {
        let transaction = try await createAssetLockTransactionWithValidation(amount: amount)
        
        // Create result with transaction data
        // Note: rawTransaction is empty because the public API doesn't provide raw transaction bytes
        let result = AssetLockTransactionResult(
            txid: transaction.txid,
            rawTransaction: transaction.raw, // Empty: not available from public API
            amount: amount,
            fee: transaction.fee,
            selectedUTXOs: [] // UTXO selection handled internally by public API
        )
        
        return result
    }
    
    /// Broadcast an asset lock transaction result with InstantSend waiting
    public func broadcastAssetLockTransactionWithInstantSend(
        _ transaction: AssetLockTransactionResult,
        waitForInstantLock: Bool = true,
        timeout: TimeInterval = 30.0
    ) async throws -> String {
        print("📡 Asset lock transaction already broadcasted: \(transaction.txid)")
        
        if waitForInstantLock {
            print("⏱️ Waiting for InstantSend lock using public API...")
            let hasInstantLock = try await waitForInstantLockWithTimeout(
                txid: transaction.txid,
                timeout: timeout
            )
            
            if hasInstantLock {
                print("✅ InstantSend lock confirmed")
            } else {
                print("⚠️ InstantSend lock not received within timeout")
                throw DashSDKAssetLockError.instantLockTimeout
            }
        }
        
        return transaction.txid
    }
    
    /// Get transaction confirmations using public API
    internal func getTransactionConfirmations(_ txid: String) async throws -> Int32 {
        // Use the public API to get transaction information
        // Since getTransactions() is available internally, we can use it
        let transactions = try await getTransactions(limit: 1000)
        
        // Find the transaction with matching txid
        if let transaction = transactions.first(where: { $0.txid == txid }) {
            return transaction.confirmations
        }
        
        // If not found, return 0 confirmations
        return 0
    }
    
    /// Check if transaction has InstantSend lock using public API
    internal func isTransactionInstantLocked(_ txid: String) async -> Bool {
        // Use the public API to get transaction information
        do {
            let transactions = try await getTransactions(limit: 1000)
            
            // Find the transaction with matching txid
            if let transaction = transactions.first(where: { $0.txid == txid }) {
                return transaction.isInstantLocked
            }
        } catch {
            print("⚠️ Error checking InstantLock status: \(error)")
        }
        
        // If not found or error, return false
        return false
    }
    
    /// Wait for InstantSend lock confirmation using public API
    internal func waitForInstantLockWithTimeout(
        txid: String,
        timeout: TimeInterval = 30.0
    ) async throws -> Bool {
        let startTime = Date()
        let checkInterval: TimeInterval = 1.0
        
        while Date().timeIntervalSince(startTime) < timeout {
            let isInstantLocked = await isTransactionInstantLocked(txid)
            
            if isInstantLocked {
                return true
            }
            
            try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }
        
        return false
    }
    
    // MARK: - Private Helpers
    
    private func generateAssetLockAddressFromWatchedAddresses() async throws -> String {
        // Generate a proper P2SH asset lock address using the AssetLockHelper
        let networkInfo = getNetworkInfo()
        let assetLockAddress = AssetLockHelper.generateAssetLockAddress(for: networkInfo.network)
        
        print("🔒 Generated asset lock address for network \(networkInfo.network.name): \(assetLockAddress)")
        return assetLockAddress
    }
}

// MARK: - Asset Lock Transaction Result

public struct AssetLockTransactionResult {
    public let txid: String
    public let rawTransaction: Data
    public let amount: UInt64
    public let fee: UInt64
    public let selectedUTXOs: [UTXO]
    
    public var size: Int {
        // Return actual size if raw transaction data is available, otherwise use estimated size
        return rawTransaction.count > 0 ? rawTransaction.count : 250 // Estimated size for asset lock transactions
    }
    
    public var feeRate: UInt64 {
        guard size > 0 else { return 0 }
        return (fee * 1000) / UInt64(size)
    }
    
    public init(
        txid: String,
        rawTransaction: Data,
        amount: UInt64,
        fee: UInt64,
        selectedUTXOs: [UTXO]
    ) {
        self.txid = txid
        self.rawTransaction = rawTransaction
        self.amount = amount
        self.fee = fee
        self.selectedUTXOs = selectedUTXOs
    }
}

// InstantLock is defined in AssetLockBridge.swift

// MARK: - Transaction Errors

enum TransactionError: LocalizedError {
    case insufficientFunds
    case noInputs
    case noOutputs
    case invalidAddress(String)
    case feeTooHigh
    case dustOutput
    case broadcastFailed
    case signingFailed
    
    var errorDescription: String? {
        switch self {
        case .insufficientFunds:
            return "Insufficient funds for transaction"
        case .noInputs:
            return "No inputs available for transaction"
        case .noOutputs:
            return "No outputs specified for transaction"
        case .invalidAddress(let reason):
            return "Invalid address: \(reason)"
        case .feeTooHigh:
            return "Transaction fee is too high"
        case .dustOutput:
            return "Output amount is too small (dust)"
        case .broadcastFailed:
            return "Failed to broadcast transaction"
        case .signingFailed:
            return "Failed to sign transaction"
        }
    }
}

// MARK: - Data Extensions
// Data extension is already defined in PersistentWalletManager.swift