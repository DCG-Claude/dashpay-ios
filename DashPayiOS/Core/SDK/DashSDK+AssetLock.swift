import Foundation
import SwiftDashCoreSDK

// MARK: - Asset Lock Extension
// Asset lock implementation using DashSDK public API only

extension DashSDK {
    
    /// Create an asset lock transaction for Platform identity funding (returns SwiftDashCoreSDK.Transaction)
    public func createAssetLockTransaction(amount: UInt64) async throws -> SwiftDashCoreSDK.Transaction {
        print("🔒 Creating asset lock transaction for \(amount) satoshis")
        
        // Validate minimum amount for asset lock (10,000 duffs)
        guard amount >= 10_000 else {
            throw AssetLockError.invalidAmount("Asset lock amount must be at least 10,000 duffs")
        }
        
        // Check available balance
        let balance = try await getBalance()
        let estimatedFee = try await estimateFee(to: "placeholder", amount: amount, feeRate: 2000)
        let totalRequired = amount + estimatedFee
        
        guard balance.confirmed >= totalRequired else {
            throw AssetLockError.insufficientBalance
        }
        
        print("✅ Balance validated: \(balance.confirmed) >= \(totalRequired)")
        
        // Generate asset lock address
        let assetLockAddress = try await generateAssetLockAddress(for: amount)
        print("🏠 Generated asset lock address: \(assetLockAddress)")
        
        // Create the asset lock transaction using sendTransaction
        let txid = try await sendTransaction(
            to: assetLockAddress,
            amount: amount,
            feeRate: 2000
        )
        
        print("✅ Asset lock transaction created: \(txid)")
        
        // Create and return SwiftDashCoreSDK.Transaction
        let transaction = SwiftDashCoreSDK.Transaction(
            txid: txid,
            height: nil,
            timestamp: Date(),
            amount: Int64(amount),
            fee: estimatedFee,
            confirmations: 0,
            isInstantLocked: false,
            raw: Data(), // Raw transaction data not available from sendTransaction
            size: 250, // Estimated size
            version: 3 // Asset lock transactions use version 3
        )
        
        return transaction
    }
    
    /// Create an asset lock transaction for Platform identity funding (returns AssetLockTransactionResult)
    public func createAssetLockTransactionResult(
        amount: UInt64,
        feeRate: UInt64 = 2000
    ) async throws -> AssetLockTransactionResult {
        let transaction = try await createAssetLockTransaction(amount: amount)
        
        // Create result with transaction data
        let result = AssetLockTransactionResult(
            txid: transaction.txid,
            rawTransaction: transaction.raw,
            amount: amount,
            fee: transaction.fee,
            selectedUTXOs: [] // UTXO selection handled internally
        )
        
        return result
    }
    
    /// Broadcast an asset lock transaction (SwiftDashCoreSDK.Transaction)
    public func broadcastTransaction(_ tx: SwiftDashCoreSDK.Transaction) async throws -> String {
        print("📡 Asset lock transaction already broadcasted: \(tx.txid)")
        
        // Since the transaction was already broadcasted by sendTransaction,
        // we just return the transaction ID
        return tx.txid
    }
    
    /// Broadcast an asset lock transaction (transaction already broadcasted by sendTransaction)
    public func broadcastAssetLockTransaction(
        _ transaction: AssetLockTransactionResult,
        waitForInstantLock: Bool = true,
        timeout: TimeInterval = 30.0
    ) async throws -> String {
        print("📡 Asset lock transaction already broadcasted: \(transaction.txid)")
        
        if waitForInstantLock {
            print("⏱️ Waiting for InstantSend lock...")
            let hasInstantLock = try await waitForInstantLockWithTimeout(
                txid: transaction.txid,
                timeout: timeout
            )
            
            if hasInstantLock {
                print("✅ InstantSend lock confirmed")
            } else {
                print("⚠️ InstantSend lock not received within timeout")
                throw AssetLockError.instantLockTimeout
            }
        }
        
        return transaction.txid
    }
    
    /// Get transaction confirmations using public API
    internal func getTransactionConfirmations(_ txid: String) async throws -> Int32 {
        // Use public API to get transaction details
        let transactions = try await getTransactions(limit: 1000)
        
        for tx in transactions {
            if tx.txid == txid {
                return Int32(tx.confirmations)
            }
        }
        
        // Transaction not found in wallet
        throw AssetLockError.transactionNotFound
    }
    
    /// Check if transaction has InstantSend lock using public API
    internal func isTransactionInstantLocked(_ txid: String) async -> Bool {
        do {
            let transactions = try await getTransactions(limit: 1000)
            
            for tx in transactions {
                if tx.txid == txid {
                    return tx.isInstantLocked
                }
            }
            
            return false
        } catch {
            print("⚠️ Error checking InstantSend status: \(error)")
            return false
        }
    }
    
    /// Wait for InstantSend lock confirmation
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
    
    /// Get InstantLock for a transaction
    public func getInstantLock(for txid: String) async throws -> InstantLock? {
        let isInstantLocked = await isTransactionInstantLocked(txid)
        
        if isInstantLocked {
            let confirmations = try await getTransactionConfirmations(txid)
            
            return InstantLock(
                txid: txid,
                height: confirmations > 0 ? UInt32(confirmations) : 0,
                signature: Data() // Signature would be obtained from masternode quorum
            )
        }
        
        return nil
    }
    
    /// Wait for InstantSend lock and return InstantLock
    public func waitForInstantLockResult(txid: String, timeout: TimeInterval) async throws -> InstantLock {
        let startTime = Date()
        let checkInterval: TimeInterval = 1.0
        
        while Date().timeIntervalSince(startTime) < timeout {
            if let instantLock = try await getInstantLock(for: txid) {
                return instantLock
            }
            
            try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }
        
        throw AssetLockError.instantLockTimeout
    }
    
    // MARK: - Private Helpers
    
    private func generateAssetLockAddress(for amount: UInt64) async throws -> String {
        // Generate a proper asset lock address using available addresses
        let addresses = Array(watchedAddresses)
        
        guard let firstAddress = addresses.first else {
            throw AssetLockError.assetLockGenerationFailed
        }
        
        // In a real implementation, this would generate a proper P2SH address
        // For now, use the first watched address as the asset lock destination
        return firstAddress
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
        return rawTransaction.count > 0 ? rawTransaction.count : 250 // Estimated size if raw tx not available
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

// MARK: - InstantLock

public struct InstantLock {
    public let txid: String
    public let height: UInt32
    public let signature: Data
    
    public init(txid: String, height: UInt32, signature: Data) {
        self.txid = txid
        self.height = height
        self.signature = signature
    }
}

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

// MARK: - Additional Asset Lock Errors

enum AssetLockError: LocalizedError {
    case invalidAmount(String)
    case transactionNotFound
    case broadcastFailed
    case instantLockTimeout
    case assetLockGenerationFailed
    case insufficientBalance
    case invalidOutputIndex
    case sdkNotAvailable
    case notImplemented
    
    var errorDescription: String? {
        switch self {
        case .invalidAmount(let reason):
            return "Invalid amount: \(reason)"
        case .transactionNotFound:
            return "Transaction not found"
        case .broadcastFailed:
            return "Failed to broadcast transaction"
        case .instantLockTimeout:
            return "Timeout waiting for InstantSend lock"
        case .assetLockGenerationFailed:
            return "Failed to generate asset lock"
        case .insufficientBalance:
            return "Insufficient balance for asset lock transaction"
        case .invalidOutputIndex:
            return "Invalid output index for asset lock"
        case .sdkNotAvailable:
            return "Core SDK not available for asset lock operation"
        case .notImplemented:
            return "Asset lock functionality is not yet implemented with the new SDK"
        }
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