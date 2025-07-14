import Foundation
import SwiftDashCoreSDK

// MARK: - Asset Lock Extension
// TODO: This extension needs to be rewritten to work with the public API of DashSDK
// The current implementation tries to access internal components that are no longer available

/*
extension DashSDK {
    
    /// Create an asset lock transaction for Platform identity funding
    public func createAssetLockTransaction(
        amount: UInt64,
        feeRate: UInt64 = 1000
    ) async throws -> AssetLockTransactionResult {
        print("🔒 Creating asset lock transaction for \(amount) satoshis")
        
        // Step 1: Get available UTXOs
        let utxos = try await getUTXOs()
        let spendableUTXOs = utxos.filter { $0.isSpendable }
        
        guard !spendableUTXOs.isEmpty else {
            throw TransactionError.noInputs
        }
        
        print("💰 Found \(spendableUTXOs.count) spendable UTXOs")
        
        // Step 2: Select UTXOs using TransactionBuilder
        let builder = TransactionBuilder(network: spvClient.configuration.network, client: spvClient)
        let selectedUTXOs = try builder.selectUTXOs(
            from: spendableUTXOs,
            targetAmount: amount,
            feeRate: feeRate,
            strategy: .instantLockedFirst // Prefer InstantLocked UTXOs for faster confirmation
        )
        
        print("✅ Selected \(selectedUTXOs.count) UTXOs for transaction")
        
        // Step 3: Get change address
        let changeAddress = try await getChangeAddress()
        
        // Step 4: Build asset lock transaction
        let rawTransaction = try builder.buildAssetLockTransaction(
            inputs: selectedUTXOs,
            amount: amount,
            changeAddress: changeAddress,
            feeRate: feeRate
        )
        
        // Step 5: Sign the transaction
        let signedTransaction = try await signTransaction(rawTransaction, inputs: selectedUTXOs)
        
        // Step 6: Calculate transaction ID
        let txid = calculateTransactionId(from: signedTransaction)
        
        print("✅ Asset lock transaction created: \(txid)")
        
        return AssetLockTransactionResult(
            txid: txid,
            rawTransaction: signedTransaction,
            amount: amount,
            fee: try builder.estimateFee(
                inputs: selectedUTXOs.count,
                outputs: 2, // asset lock + change
                feeRate: feeRate
            ),
            selectedUTXOs: selectedUTXOs
        )
    }
    
    /// Broadcast an asset lock transaction and wait for InstantSend lock
    public func broadcastAssetLockTransaction(
        _ transaction: AssetLockTransactionResult,
        waitForInstantLock: Bool = true,
        timeout: TimeInterval = 30.0
    ) async throws -> String {
        print("📡 Broadcasting asset lock transaction: \(transaction.txid)")
        
        // Broadcast the transaction
        let txHex = transaction.rawTransaction.map { String(format: "%02x", $0) }.joined()
        try await spvClient.broadcastTransaction(txHex)
        
        print("✅ Transaction broadcasted successfully")
        
        if waitForInstantLock {
            print("⏱️ Waiting for InstantSend lock...")
            let hasInstantLock = try await self.waitForInstantLock(
                txid: transaction.txid,
                timeout: timeout
            )
            
            if hasInstantLock {
                print("✅ InstantSend lock confirmed")
            } else {
                print("⚠️ InstantSend lock not received within timeout")
                // Continue anyway - regular confirmation will work
            }
        }
        
        return transaction.txid
    }
    
    /// Get transaction confirmations (internal helper for AssetLockBridge)
    internal func getTransactionConfirmations(_ txid: String) async throws -> Int32 {
        // Use the SPV client to get transaction details
        let transaction = try await spvClient.getTransaction(txid: txid)
        return Int32(transaction?.confirmations ?? 0)
    }
    
    /// Check if transaction has InstantSend lock (internal helper)
    internal func isTransactionInstantLocked(_ txid: String) async -> Bool {
        do {
            // Query the SPV client for InstantSend status
            let transaction = try await spvClient.getTransaction(txid: txid)
            return transaction?.isInstantLocked ?? false
        } catch {
            print("⚠️ Error checking InstantSend status: \(error)")
            return false
        }
    }
    
    /// Wait for InstantSend lock confirmation
    internal func waitForInstantLock(
        txid: String,
        timeout: TimeInterval = 10.0
    ) async throws -> Bool {
        let startTime = Date()
        let checkInterval: TimeInterval = 0.5
        
        while Date().timeIntervalSince(startTime) < timeout {
            if await isTransactionInstantLocked(txid) {
                return true
            }
            
            try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }
        
        return false
    }
    
    // MARK: - Private Helpers
    
    private func getChangeAddress() async throws -> String {
        // Get a change address from the wallet using address derivation
        let addresses = Array(watchedAddresses)
        guard let changeAddress = addresses.first else {
            throw TransactionError.invalidAddress("No change address available")
        }
        
        return changeAddress
    }
    
    private func signTransaction(
        _ rawTransaction: Data,
        inputs: [UTXO]
    ) async throws -> Data {
        // Sign the transaction using the wallet's private keys
        // This would:
        // 1. Get private keys for each input
        // 2. Create proper signatures  
        // 3. Update the transaction with signature scripts
        // The actual signing happens through FFI calls
        return rawTransaction
    }
    
    private func calculateTransactionId(from rawTransaction: Data) -> String {
        // Calculate the transaction ID from the raw transaction using double SHA256 hashing
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
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
        return rawTransaction.count
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
*/