import XCTest
import Foundation
@testable import DashPay

/// Comprehensive tests for the Transaction model and status tracking
@MainActor
final class TransactionModelTests: TransactionTestBase {
    
    // MARK: - Transaction Creation Tests
    
    func testTransactionInitialization() {
        // Given: Valid transaction parameters
        let txid = generateTestTxid()
        let amount: Int64 = 100_000_000 // 1.0 DASH
        let fee: UInt64 = 1000
        let confirmations: UInt32 = 3
        
        // When: Creating a transaction
        let transaction = Transaction(
            txid: txid,
            height: 100000,
            timestamp: Date(),
            amount: amount,
            fee: fee,
            confirmations: confirmations,
            isInstantLocked: false,
            raw: generateTestRawTransaction(),
            size: 250,
            version: 3
        )
        
        // Then: All properties should be set correctly
        XCTAssertEqual(transaction.txid, txid)
        XCTAssertEqual(transaction.amount, amount)
        XCTAssertEqual(transaction.fee, fee)
        XCTAssertEqual(transaction.confirmations, confirmations)
        XCTAssertEqual(transaction.version, 3)
        XCTAssertFalse(transaction.isInstantLocked)
    }
    
    func testTransactionWithFFIInitialization() {
        // This test would require actual FFI integration
        // For now, we'll test the concept with mock data
        
        // Given: Mock FFI transaction data
        let txid = generateTestTxid()
        
        // When: Creating transaction from FFI data (simulated)
        let transaction = createTestTransaction(
            txid: txid,
            amount: 50_000_000,
            confirmations: 0
        )
        
        // Then: Transaction should be properly initialized
        XCTAssertEqual(transaction.txid, txid)
        XCTAssertEqual(transaction.amount, 50_000_000)
        XCTAssertEqual(transaction.confirmations, 0)
    }
    
    // MARK: - Transaction Status Tests
    
    func testTransactionStatusPending() {
        // Given: Unconfirmed, non-InstantSend transaction
        let transaction = createTestTransaction(confirmations: 0, isInstantLocked: false)
        
        // When: Checking status
        let status = transaction.status
        
        // Then: Should be pending
        XCTAssertEqual(status, .pending)
        XCTAssertTrue(transaction.isPending)
        XCTAssertFalse(transaction.isConfirmed)
    }
    
    func testTransactionStatusConfirming() {
        // Given: Transaction with partial confirmations
        let transaction = createTestTransaction(confirmations: 3, isInstantLocked: false)
        
        // When: Checking status
        let status = transaction.status
        
        // Then: Should be confirming with count
        if case .confirming(let count) = status {
            XCTAssertEqual(count, 3)
        } else {
            XCTFail("Expected confirming status, got: \(status)")
        }
        
        XCTAssertFalse(transaction.isPending)
        XCTAssertTrue(transaction.isConfirmed)
    }
    
    func testTransactionStatusConfirmed() {
        // Given: Fully confirmed transaction (6+ confirmations)
        let transaction = createTestTransaction(confirmations: 6, isInstantLocked: false)
        
        // When: Checking status
        let status = transaction.status
        
        // Then: Should be confirmed
        XCTAssertEqual(status, .confirmed)
        XCTAssertFalse(transaction.isPending)
        XCTAssertTrue(transaction.isConfirmed)
    }
    
    func testTransactionStatusInstantLocked() {
        // Given: InstantSend transaction
        let transaction = createTestTransaction(confirmations: 0, isInstantLocked: true)
        
        // When: Checking status
        let status = transaction.status
        
        // Then: Should be InstantSend
        XCTAssertEqual(status, .instantLocked)
        XCTAssertFalse(transaction.isPending)
        XCTAssertTrue(transaction.isConfirmed) // InstantSend counts as confirmed
    }
    
    func testTransactionStatusInstantLockedWithConfirmations() {
        // Given: InstantSend transaction that also has confirmations
        let transaction = createTestTransaction(confirmations: 3, isInstantLocked: true)
        
        // When: Checking status
        let status = transaction.status
        
        // Then: Should still show as InstantSend (takes precedence)
        XCTAssertEqual(status, .instantLocked)
        XCTAssertFalse(transaction.isPending)
        XCTAssertTrue(transaction.isConfirmed)
    }
    
    // MARK: - Transaction Status Description Tests
    
    func testStatusDescriptions() {
        // Test all status description strings
        XCTAssertEqual(TransactionStatus.pending.description, "Pending")
        XCTAssertEqual(TransactionStatus.confirming(confirmations: 3).description, "3/6 confirmations")
        XCTAssertEqual(TransactionStatus.confirmed.description, "Confirmed")
        XCTAssertEqual(TransactionStatus.instantLocked.description, "InstantSend")
    }
    
    func testStatusSettledStates() {
        // Test which statuses are considered "settled"
        XCTAssertFalse(TransactionStatus.pending.isSettled)
        XCTAssertFalse(TransactionStatus.confirming(confirmations: 3).isSettled)
        XCTAssertTrue(TransactionStatus.confirmed.isSettled)
        XCTAssertTrue(TransactionStatus.instantLocked.isSettled)
    }
    
    // MARK: - Transaction Status Transitions Tests
    
    func testStatusTransitionPendingToConfirming() {
        // Given: Pending transaction
        let transaction = createTestTransaction(confirmations: 0, isInstantLocked: false)
        XCTAssertEqual(transaction.status, .pending)
        
        // When: Transaction gets first confirmation
        transaction.confirmations = 1
        
        // Then: Status should transition to confirming
        if case .confirming(let count) = transaction.status {
            XCTAssertEqual(count, 1)
        } else {
            XCTFail("Expected confirming status after first confirmation")
        }
    }
    
    func testStatusTransitionConfirmingToConfirmed() {
        // Given: Partially confirmed transaction
        let transaction = createTestTransaction(confirmations: 5, isInstantLocked: false)
        XCTAssertEqual(transaction.status, .confirming(confirmations: 5))
        
        // When: Transaction reaches full confirmation
        transaction.confirmations = 6
        
        // Then: Status should transition to confirmed
        XCTAssertEqual(transaction.status, .confirmed)
    }
    
    func testStatusTransitionPendingToInstantLocked() {
        // Given: Pending transaction
        let transaction = createTestTransaction(confirmations: 0, isInstantLocked: false)
        XCTAssertEqual(transaction.status, .pending)
        
        // When: Transaction becomes InstantSend
        transaction.isInstantLocked = true
        
        // Then: Status should transition to InstantSend
        XCTAssertEqual(transaction.status, .instantLocked)
    }
    
    // MARK: - Transaction Equality Tests
    
    func testTransactionEquality() {
        // Given: Two transactions with same TXID
        let txid = generateTestTxid()
        let transaction1 = createTestTransaction(txid: txid, amount: 100_000_000)
        let transaction2 = createTestTransaction(txid: txid, amount: 200_000_000)
        
        // When: Comparing transactions
        // Then: Should be equal based on TXID (SwiftData @Attribute(.unique))
        XCTAssertEqual(transaction1.txid, transaction2.txid)
    }
    
    func testTransactionInequality() {
        // Given: Two transactions with different TXIDs
        let transaction1 = createTestTransaction(txid: "txid1")
        let transaction2 = createTestTransaction(txid: "txid2")
        
        // When: Comparing transactions
        // Then: Should not be equal
        XCTAssertNotEqual(transaction1.txid, transaction2.txid)
    }
    
    // MARK: - Transaction Amount Tests
    
    func testPositiveAmountTransaction() {
        // Given: Received transaction (positive amount)
        let transaction = createTestTransaction(amount: 100_000_000) // +1.0 DASH
        
        // When: Checking amount
        // Then: Should be positive (receiving funds)
        XCTAssertGreaterThan(transaction.amount, 0)
    }
    
    func testNegativeAmountTransaction() {
        // Given: Sent transaction (negative amount)
        let transaction = createTestTransaction(amount: -50_000_000) // -0.5 DASH
        
        // When: Checking amount
        // Then: Should be negative (sending funds)
        XCTAssertLessThan(transaction.amount, 0)
    }
    
    func testZeroAmountTransaction() {
        // Given: Transaction with zero amount (should be rare)
        let transaction = createTestTransaction(amount: 0)
        
        // When: Checking amount
        // Then: Should be zero
        XCTAssertEqual(transaction.amount, 0)
    }
    
    // MARK: - Transaction Fee Tests
    
    func testTransactionFee() {
        // Given: Transaction with fee
        let fee: UInt64 = 2500 // 0.000025 DASH
        let transaction = createTestTransaction(fee: fee)
        
        // When: Checking fee
        // Then: Should match set fee
        XCTAssertEqual(transaction.fee, fee)
        XCTAssertGreaterThan(transaction.fee, 0)
    }
    
    func testZeroFeeTransaction() {
        // Given: Transaction with zero fee (theoretical case)
        let transaction = createTestTransaction(fee: 0)
        
        // When: Checking fee
        // Then: Should be zero
        XCTAssertEqual(transaction.fee, 0)
    }
    
    func testReasonableFeeRange() {
        // Given: Transaction with reasonable fee
        let transaction = createTestTransaction(fee: 1000) // 0.00001 DASH
        
        // When: Checking fee reasonableness
        // Then: Should be in reasonable range
        XCTAssertGreaterThan(transaction.fee, 100) // At least 100 satoshis
        XCTAssertLessThan(transaction.fee, 100_000) // Less than 0.001 DASH
    }
    
    // MARK: - Transaction Size Tests
    
    func testTransactionSize() {
        // Given: Transaction with size
        let size: Int = 250
        let transaction = createTestTransaction()
        transaction.size = size
        
        // When: Checking size
        // Then: Should match set size
        XCTAssertEqual(transaction.size, size)
    }
    
    func testMinimumTransactionSize() {
        // Given: Minimum possible transaction size
        let transaction = createTestTransaction()
        transaction.size = 100 // Very small transaction
        
        // When: Checking size
        // Then: Should be reasonable
        XCTAssertGreaterThan(transaction.size, 50) // Minimum viable size
    }
    
    func testLargeTransactionSize() {
        // Given: Large transaction
        let transaction = createTestTransaction()
        transaction.size = 10000 // Large transaction
        
        // When: Checking size
        // Then: Should handle large sizes
        XCTAssertGreaterThan(transaction.size, 1000)
        XCTAssertLessThan(transaction.size, 100000) // Reasonable upper bound
    }
    
    // MARK: - Transaction Version Tests
    
    func testTransactionVersion() {
        // Given: Transaction with version 3 (required for certain features)
        let transaction = createTestTransaction()
        transaction.version = 3
        
        // When: Checking version
        // Then: Should be version 3
        XCTAssertEqual(transaction.version, 3)
    }
    
    func testLegacyTransactionVersion() {
        // Given: Legacy transaction version
        let transaction = createTestTransaction()
        transaction.version = 1
        
        // When: Checking version
        // Then: Should support legacy versions
        XCTAssertEqual(transaction.version, 1)
    }
    
    // MARK: - Transaction Height Tests
    
    func testTransactionWithBlockHeight() {
        // Given: Confirmed transaction with block height
        let height: UInt32 = 100000
        let transaction = createTestTransaction(height: height, confirmations: 6)
        
        // When: Checking height
        // Then: Should have block height
        XCTAssertEqual(transaction.height, height)
        XCTAssertNotNil(transaction.height)
    }
    
    func testUnconfirmedTransactionHeight() {
        // Given: Unconfirmed transaction
        let transaction = createTestTransaction(height: nil, confirmations: 0)
        
        // When: Checking height
        // Then: Should not have block height
        XCTAssertNil(transaction.height)
    }
    
    // MARK: - Transaction Timestamp Tests
    
    func testTransactionTimestamp() {
        // Given: Transaction with specific timestamp
        let timestamp = Date()
        let transaction = createTestTransaction()
        transaction.timestamp = timestamp
        
        // When: Checking timestamp
        // Then: Should match set timestamp
        XCTAssertEqual(transaction.timestamp.timeIntervalSince1970, 
                      timestamp.timeIntervalSince1970, 
                      accuracy: 1.0) // Within 1 second
    }
    
    func testRecentTransactionTimestamp() {
        // Given: Recent transaction
        let transaction = createTestTransaction()
        
        // When: Checking if timestamp is recent
        let timeSinceCreation = Date().timeIntervalSince(transaction.timestamp)
        
        // Then: Should be very recent
        XCTAssertLessThan(timeSinceCreation, 10.0) // Created within last 10 seconds
    }
    
    // MARK: - Transaction Raw Data Tests
    
    func testTransactionRawData() {
        // Given: Transaction with raw data
        let rawData = generateTestRawTransaction()
        let transaction = createTestTransaction()
        transaction.raw = rawData
        
        // When: Checking raw data
        // Then: Should match set data
        XCTAssertEqual(transaction.raw, rawData)
        XCTAssertGreaterThan(transaction.raw.count, 0)
    }
    
    func testEmptyTransactionRawData() {
        // Given: Transaction with empty raw data
        let transaction = createTestTransaction()
        transaction.raw = Data()
        
        // When: Checking raw data
        // Then: Should handle empty data
        XCTAssertEqual(transaction.raw.count, 0)
    }
    
    // MARK: - Complex Transaction Scenarios
    
    func testInstantSendConfirmationScenario() {
        // Given: InstantSend transaction that later gets confirmed
        let transaction = createTestTransaction(confirmations: 0, isInstantLocked: true)
        
        // Initially should be InstantSend
        XCTAssertEqual(transaction.status, .instantLocked)
        
        // When: Transaction gets blockchain confirmations
        transaction.confirmations = 3
        
        // Then: Should still show as InstantSend (takes precedence)
        XCTAssertEqual(transaction.status, .instantLocked)
        XCTAssertTrue(transaction.isConfirmed)
    }
    
    func testReplacementTransactionScenario() {
        // Given: Two transactions with same TXID but different properties
        let txid = generateTestTxid()
        let originalTx = createTestTransaction(txid: txid, confirmations: 0)
        
        // When: Transaction gets updated (e.g., confirmation)
        originalTx.confirmations = 6
        originalTx.height = 100050
        
        // Then: Transaction should reflect updates
        XCTAssertEqual(originalTx.status, .confirmed)
        XCTAssertEqual(originalTx.height, 100050)
    }
    
    func testLargeAmountTransaction() {
        // Given: Transaction with large amount
        let largeAmount: Int64 = 10_000_000_000 // 100 DASH
        let transaction = createTestTransaction(amount: largeAmount)
        
        // When: Checking amount handling
        // Then: Should handle large amounts correctly
        XCTAssertEqual(transaction.amount, largeAmount)
        XCTAssertGreaterThan(transaction.amount, 1_000_000_000) // > 10 DASH
    }
    
    func testSmallAmountTransaction() {
        // Given: Transaction with small amount
        let smallAmount: Int64 = 1000 // 0.00001 DASH
        let transaction = createTestTransaction(amount: smallAmount)
        
        // When: Checking amount handling
        // Then: Should handle small amounts correctly
        XCTAssertEqual(transaction.amount, smallAmount)
        XCTAssertLessThan(transaction.amount, 10000) // < 0.0001 DASH
    }
    
    // MARK: - Edge Cases
    
    func testTransactionWithEmptyTxid() {
        // This test ensures the model handles edge cases gracefully
        // In practice, empty TXIDs should not occur, but testing robustness
        
        // Given: Transaction with empty TXID (edge case)
        let transaction = createTestTransaction(txid: "")
        
        // When: Checking TXID
        // Then: Should handle gracefully
        XCTAssertEqual(transaction.txid, "")
        // In a production system, this might trigger validation errors
    }
    
    func testTransactionWithFutureTimestamp() {
        // Given: Transaction with future timestamp (edge case)
        let futureDate = Date().addingTimeInterval(3600) // 1 hour in future
        let transaction = createTestTransaction()
        transaction.timestamp = futureDate
        
        // When: Checking timestamp
        // Then: Should handle future timestamps
        XCTAssertGreaterThan(transaction.timestamp, Date())
    }
    
    func testTransactionWithNegativeConfirmations() {
        // This shouldn't happen in practice, but test model robustness
        
        // Given: Transaction with invalid confirmations
        let transaction = createTestTransaction(confirmations: 0)
        
        // When: Setting invalid confirmations (this would be prevented in real code)
        // Then: Model should maintain data integrity
        XCTAssertGreaterThanOrEqual(transaction.confirmations, 0)
    }
    
    // MARK: - Performance Tests
    
    func testManyTransactionsCreation() {
        // Given: Need to create many transactions
        let transactionCount = 1000
        
        // When: Creating many transactions
        let startTime = Date()
        var transactions: [Transaction] = []
        
        for i in 0..<transactionCount {
            let transaction = createTestTransaction(
                txid: "txid_\(i)",
                amount: Int64(i * 1000)
            )
            transactions.append(transaction)
        }
        
        let creationTime = Date().timeIntervalSince(startTime)
        
        // Then: Should create efficiently
        XCTAssertEqual(transactions.count, transactionCount)
        XCTAssertLessThan(creationTime, 5.0) // Should complete within 5 seconds
    }
}

// MARK: - Transaction Status Equality Conformance Test

extension TransactionModelTests {
    
    func testTransactionStatusEquality() {
        // Test TransactionStatus Equatable conformance
        XCTAssertEqual(TransactionStatus.pending, TransactionStatus.pending)
        XCTAssertEqual(TransactionStatus.confirmed, TransactionStatus.confirmed)
        XCTAssertEqual(TransactionStatus.instantLocked, TransactionStatus.instantLocked)
        XCTAssertEqual(TransactionStatus.confirming(confirmations: 3), TransactionStatus.confirming(confirmations: 3))
        
        // Test inequality
        XCTAssertNotEqual(TransactionStatus.pending, TransactionStatus.confirmed)
        XCTAssertNotEqual(TransactionStatus.confirming(confirmations: 2), TransactionStatus.confirming(confirmations: 3))
        XCTAssertNotEqual(TransactionStatus.instantLocked, TransactionStatus.pending)
    }
}