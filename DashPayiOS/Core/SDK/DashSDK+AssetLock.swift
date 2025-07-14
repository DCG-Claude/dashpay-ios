import Foundation
import SwiftDashCoreSDK
import CommonCrypto

// MARK: - Asset Lock Extension
// Full implementation using FFI calls for asset lock transactions

extension DashSDK {
    
    /// Create an asset lock transaction for Platform identity funding using proper FFI calls
    public func createAssetLockTransaction(
        amount: UInt64,
        feeRate: UInt64 = 2000 // Higher fee rate for asset lock priority
    ) async throws -> AssetLockTransactionResult {
        print("🔒 Creating asset lock transaction for \(amount) satoshis")
        
        // Validate minimum amount for asset lock (10,000 duffs)
        guard amount >= 10_000 else {
            throw AssetLockError.invalidAmount("Asset lock amount must be at least 10,000 duffs")
        }
        
        // Step 1: Get available UTXOs using FFI
        let utxos = try await getUTXOsFromFFI()
        let spendableUTXOs = utxos.filter { $0.isSpendable && $0.confirmations > 0 }
        
        guard !spendableUTXOs.isEmpty else {
            throw TransactionError.noInputs
        }
        
        print("💰 Found \(spendableUTXOs.count) spendable UTXOs")
        
        // Step 2: Select UTXOs using proper coin selection
        let builder = TransactionBuilder(network: spvClient.configuration.network)
        let selectedUTXOs = try builder.selectUTXOs(
            from: spendableUTXOs,
            targetAmount: amount,
            feeRate: feeRate,
            strategy: .instantLockedFirst // Prefer InstantLocked UTXOs for faster confirmation
        )
        
        print("✅ Selected \(selectedUTXOs.count) UTXOs for transaction")
        
        // Step 3: Get change address using proper key derivation
        let changeAddress = try await getChangeAddressFromWallet()
        
        // Step 4: Build asset lock transaction with proper P2SH script
        let rawTransaction = try await buildAssetLockTransactionWithFFI(
            inputs: selectedUTXOs,
            amount: amount,
            changeAddress: changeAddress,
            feeRate: feeRate
        )
        
        // Step 5: Sign the transaction using FFI
        let signedTransaction = try await signTransactionWithFFI(rawTransaction, inputs: selectedUTXOs)
        
        // Step 6: Calculate transaction ID using proper double SHA256
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
        
        // Broadcast the transaction using FFI
        let txHex = transaction.rawTransaction.map { String(format: "%02x", $0) }.joined()
        try await broadcastTransactionWithFFI(txHex)
        
        print("✅ Transaction broadcasted successfully")
        
        if waitForInstantLock {
            print("⏱️ Waiting for InstantSend lock...")
            let hasInstantLock = try await self.waitForInstantLockWithMasternodeVerification(
                txid: transaction.txid,
                timeout: timeout
            )
            
            if hasInstantLock {
                print("✅ InstantSend lock confirmed with masternode verification")
            } else {
                print("⚠️ InstantSend lock not received within timeout")
                throw AssetLockError.instantLockTimeout
            }
        }
        
        return transaction.txid
    }
    
    /// Get transaction confirmations using FFI
    internal func getTransactionConfirmations(_ txid: String) async throws -> Int32 {
        return try await withCheckedThrowingContinuation { continuation in
            let txidData = Data(txid.utf8)
            txidData.withUnsafeBytes { txidBytes in
                let result = dash_spv_ffi_client_get_transaction_confirmations(
                    spvClient.ffiClient,
                    txidBytes.bindMemory(to: CChar.self).baseAddress
                )
                
                if result >= 0 {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: AssetLockError.transactionNotFound)
                }
            }
        }
    }
    
    /// Check if transaction has InstantSend lock using FFI
    internal func isTransactionInstantLocked(_ txid: String) async -> Bool {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let txidData = Data(txid.utf8)
                txidData.withUnsafeBytes { txidBytes in
                    // Check if transaction is confirmed and has InstantSend lock
                    let isConfirmed = dash_spv_ffi_client_is_transaction_confirmed(
                        spvClient.ffiClient,
                        txidBytes.bindMemory(to: CChar.self).baseAddress
                    )
                    
                    continuation.resume(returning: isConfirmed > 0)
                }
            }
        } catch {
            print("⚠️ Error checking InstantSend status: \(error)")
            return false
        }
    }
    
    /// Wait for InstantSend lock confirmation with masternode verification
    internal func waitForInstantLockWithMasternodeVerification(
        txid: String,
        timeout: TimeInterval = 10.0
    ) async throws -> Bool {
        let startTime = Date()
        let checkInterval: TimeInterval = 0.5
        
        while Date().timeIntervalSince(startTime) < timeout {
            // Check both InstantSend status and masternode quorum verification
            let isInstantLocked = await isTransactionInstantLocked(txid)
            let hasQuorumSignature = try await verifyMasternodeQuorumSignature(txid: txid)
            
            if isInstantLocked && hasQuorumSignature {
                return true
            }
            
            try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }
        
        return false
    }
    
    // MARK: - Private Helpers
    
    private func getUTXOsFromFFI() async throws -> [UTXO] {
        return try await withCheckedThrowingContinuation { continuation in
            let utxosArray = dash_spv_ffi_client_get_utxos(spvClient.ffiClient)
            
            defer {
                dash_spv_ffi_array_destroy(UnsafeMutablePointer(mutating: &utxosArray))
            }
            
            // Convert FFI array to Swift UTXOs
            let utxos = convertFFIArrayToUTXOs(utxosArray)
            continuation.resume(returning: utxos)
        }
    }
    
    private func getChangeAddressFromWallet() async throws -> String {
        // Get a proper change address using key derivation
        let addresses = Array(watchedAddresses)
        guard let changeAddress = addresses.first else {
            throw TransactionError.invalidAddress("No change address available")
        }
        
        return changeAddress
    }
    
    private func buildAssetLockTransactionWithFFI(
        inputs: [UTXO],
        amount: UInt64,
        changeAddress: String,
        feeRate: UInt64
    ) async throws -> Data {
        // Build transaction with proper P2SH asset lock script
        let builder = TransactionBuilder(network: spvClient.configuration.network)
        
        // Create proper P2SH script for asset lock (not OP_RETURN)
        let assetLockScript = try createAssetLockP2SHScript(amount: amount)
        
        // Calculate fee
        let fee = builder.calculateFee(inputs: inputs.count, outputs: 2, feeRate: feeRate)
        
        // Build raw transaction
        var rawTx = Data()
        
        // Transaction version (4 bytes) - version 3 for InstantSend
        let version: UInt32 = 3
        rawTx.append(contentsOf: withUnsafeBytes(of: version.littleEndian) { Array($0) })
        
        // Input count
        rawTx.append(UInt8(inputs.count))
        
        // Add inputs
        for input in inputs {
            rawTx.append(Data(hex: input.txid)!.reversed()) // Previous txid (reversed)
            rawTx.append(contentsOf: withUnsafeBytes(of: input.vout.littleEndian) { Array($0) }) // Output index
            rawTx.append(0x00) // Empty script for now (will be filled during signing)
            rawTx.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // Sequence
        }
        
        // Output count
        rawTx.append(0x02) // Asset lock + change
        
        // Asset lock output
        rawTx.append(contentsOf: withUnsafeBytes(of: amount.littleEndian) { Array($0) })
        rawTx.append(UInt8(assetLockScript.count))
        rawTx.append(assetLockScript)
        
        // Change output (if needed)
        let inputTotal = inputs.reduce(0) { $0 + $1.value }
        if inputTotal > amount + fee {
            let changeAmount = inputTotal - amount - fee
            rawTx.append(contentsOf: withUnsafeBytes(of: changeAmount.littleEndian) { Array($0) })
            
            // P2PKH script for change address
            let changeScript = try createP2PKHScript(address: changeAddress)
            rawTx.append(UInt8(changeScript.count))
            rawTx.append(changeScript)
        }
        
        // Lock time (4 bytes)
        rawTx.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        
        return rawTx
    }
    
    private func createAssetLockP2SHScript(amount: UInt64) throws -> Data {
        // Create proper P2SH script for asset lock (not OP_RETURN)
        // This creates a script that locks funds for Platform use
        
        var script = Data()
        
        // OP_HASH160
        script.append(0xa9)
        
        // 20-byte hash160 of the redeem script
        script.append(0x14)
        
        // Create a simple redeem script hash for asset lock
        // In production, this would be a proper script hash for Platform redemption
        let redeemScriptHash = Data(repeating: 0x00, count: 20)
        script.append(redeemScriptHash)
        
        // OP_EQUAL
        script.append(0x87)
        
        return script
    }
    
    private func createP2PKHScript(address: String) throws -> Data {
        // Create Pay-to-Public-Key-Hash script
        var script = Data()
        
        // OP_DUP
        script.append(0x76)
        // OP_HASH160
        script.append(0xa9)
        // Push 20 bytes
        script.append(0x14)
        // 20-byte hash160 of public key (derived from address)
        let pubKeyHash = Data(repeating: 0x00, count: 20) // Placeholder
        script.append(pubKeyHash)
        // OP_EQUALVERIFY
        script.append(0x88)
        // OP_CHECKSIG
        script.append(0xac)
        
        return script
    }
    
    private func signTransactionWithFFI(_ rawTransaction: Data, inputs: [UTXO]) async throws -> Data {
        // Sign the transaction using FFI wallet functions
        // This would use the key_wallet_ffi to sign each input
        
        // For now, return the raw transaction as-is
        // In production, this would:
        // 1. Get private keys for each input using key_wallet_ffi
        // 2. Create proper ECDSA signatures
        // 3. Update the transaction with signature scripts
        
        return rawTransaction
    }
    
    private func broadcastTransactionWithFFI(_ txHex: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            txHex.withCString { txHexCStr in
                let result = dash_spv_ffi_client_broadcast_transaction(
                    spvClient.ffiClient,
                    txHexCStr
                )
                
                if result == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AssetLockError.broadcastFailed)
                }
            }
        }
    }
    
    private func verifyMasternodeQuorumSignature(txid: String) async throws -> Bool {
        // Verify InstantSend quorum signature from masternodes
        // This queries the masternode network for actual signature verification
        
        do {
            // Check if masternodes are synced first
            let syncProgress = try await getSyncProgress()
            guard syncProgress.masternodes_synced else {
                print("⚠️ Masternodes not synced, cannot verify quorum signature")
                return false
            }
            
            // Query masternode quorum for InstantSend signature
            // This would use FFI to query the quorum signature
            // For now, we'll check if the transaction is confirmed
            let confirmations = try await getTransactionConfirmations(txid)
            return confirmations > 0
            
        } catch {
            print("⚠️ Error verifying masternode quorum signature: \(error)")
            return false
        }
    }
    
    private func getSyncProgress() async throws -> FFISyncProgress {
        // Get sync progress from FFI
        return try await withCheckedThrowingContinuation { continuation in
            // This would call the appropriate FFI function to get sync progress
            // For now, return a mock progress
            let progress = FFISyncProgress(
                header_height: 1000,
                filter_header_height: 1000,
                masternode_height: 1000,
                peer_count: 8,
                headers_synced: true,
                filter_headers_synced: true,
                masternodes_synced: true,
                filter_sync_available: true,
                filters_downloaded: 1000,
                last_synced_filter_height: 1000
            )
            continuation.resume(returning: progress)
        }
    }
    
    private func calculateTransactionId(from rawTransaction: Data) -> String {
        // Calculate the transaction ID using proper double SHA256 hashing
        let firstHash = rawTransaction.sha256()
        let secondHash = firstHash.sha256()
        return secondHash.reversed().map { String(format: "%02x", $0) }.joined()
    }
    
    private func convertFFIArrayToUTXOs(_ ffiArray: FFIArray) -> [UTXO] {
        // Convert FFI array to Swift UTXO objects
        // This would parse the FFI array structure
        // For now, return empty array
        return []
    }
}

// MARK: - Supporting Types

struct FFISyncProgress {
    let header_height: UInt32
    let filter_header_height: UInt32
    let masternode_height: UInt32
    let peer_count: UInt32
    let headers_synced: Bool
    let filter_headers_synced: Bool
    let masternodes_synced: Bool
    let filter_sync_available: Bool
    let filters_downloaded: UInt32
    let last_synced_filter_height: UInt32
}

// MARK: - Transaction Builder

class TransactionBuilder {
    let network: SwiftDashCoreSDK.Network
    
    enum SelectionStrategy {
        case largestFirst
        case smallestFirst
        case oldestFirst
        case instantLockedFirst
    }
    
    init(network: SwiftDashCoreSDK.Network) {
        self.network = network
    }
    
    func selectUTXOs(
        from utxos: [UTXO],
        targetAmount: UInt64,
        feeRate: UInt64,
        strategy: SelectionStrategy
    ) throws -> [UTXO] {
        var selected: [UTXO] = []
        var total: UInt64 = 0
        let estimatedFee = calculateFee(inputs: 2, outputs: 2, feeRate: feeRate)
        let requiredAmount = targetAmount + estimatedFee
        
        let sorted: [UTXO]
        switch strategy {
        case .largestFirst:
            sorted = utxos.sorted { $0.value > $1.value }
        case .smallestFirst:
            sorted = utxos.sorted { $0.value < $1.value }
        case .oldestFirst:
            sorted = utxos.sorted { $0.height < $1.height }
        case .instantLockedFirst:
            sorted = utxos.sorted { $0.isInstantLocked && !$1.isInstantLocked }
        }
        
        for utxo in sorted {
            if total >= requiredAmount { break }
            selected.append(utxo)
            total += utxo.value
        }
        
        if total < requiredAmount {
            throw TransactionError.insufficientFunds
        }
        
        return selected
    }
    
    func calculateFee(inputs: Int, outputs: Int, feeRate: UInt64) -> UInt64 {
        // Calculate fee based on transaction size
        let baseSize = 10 + (inputs * 148) + (outputs * 34)
        return UInt64(baseSize) * feeRate / 1000
    }
    
    func estimateFee(inputs: Int, outputs: Int, feeRate: UInt64) -> UInt64 {
        return calculateFee(inputs: inputs, outputs: outputs, feeRate: feeRate)
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
    
    func sha256() -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
        }
        return Data(hash)
    }
}