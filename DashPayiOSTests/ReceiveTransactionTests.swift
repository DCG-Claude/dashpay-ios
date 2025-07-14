import XCTest
import Foundation
@testable import DashPay

/// Comprehensive tests for receive transaction functionality
@MainActor
final class ReceiveTransactionTests: TransactionTestBase {
    
    var receiveTransactionService: ReceiveTransactionService!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        receiveTransactionService = ReceiveTransactionService(walletService: walletService)
    }
    
    override func tearDownWithError() throws {
        receiveTransactionService = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Address Generation Tests
    
    func testGenerateNewReceiveAddress() throws {
        // Given: Account with existing addresses
        let initialAddressCount = testAccount.addresses.count
        
        // When: Generating new receive address
        let newAddress = try receiveTransactionService.generateNewReceiveAddress(for: testAccount)
        
        // Then: Should create new address
        XCTAssertFalse(newAddress.address.isEmpty)
        XCTAssertFalse(newAddress.isChange)
        XCTAssertEqual(newAddress.label, "Receive")
        XCTAssertEqual(testAccount.addresses.count, initialAddressCount + 1)
        
        // Verify address format for testnet
        XCTAssertTrue(validateDashAddress(newAddress.address, network: .testnet))
    }
    
    func testGenerateChangeAddress() throws {
        // Given: Account needing change address
        let initialChangeAddresses = testAccount.addresses.filter { $0.isChange }.count
        
        // When: Generating change address
        let changeAddress = try receiveTransactionService.generateChangeAddress(for: testAccount)
        
        // Then: Should create change address
        XCTAssertFalse(changeAddress.address.isEmpty)
        XCTAssertTrue(changeAddress.isChange)
        XCTAssertEqual(changeAddress.label, "Change")
        
        let newChangeAddresses = testAccount.addresses.filter { $0.isChange }.count
        XCTAssertEqual(newChangeAddresses, initialChangeAddresses + 1)
    }
    
    func testAddressIndexIncrement() throws {
        // Given: Account with specific last used index
        testAccount.lastUsedExternalIndex = 5
        
        // When: Generating new address
        let newAddress = try receiveTransactionService.generateNewReceiveAddress(for: testAccount)
        
        // Then: Should increment index correctly
        XCTAssertEqual(newAddress.index, 6)
        XCTAssertEqual(testAccount.lastUsedExternalIndex, 6)
    }
    
    func testMultipleAddressGeneration() throws {
        // Given: Need for multiple addresses
        let addressCount = 5
        var generatedAddresses: [HDWatchedAddress] = []
        
        // When: Generating multiple addresses
        for _ in 0..<addressCount {
            let address = try receiveTransactionService.generateNewReceiveAddress(for: testAccount)
            generatedAddresses.append(address)
        }
        
        // Then: All addresses should be unique
        let uniqueAddresses = Set(generatedAddresses.map { $0.address })
        XCTAssertEqual(uniqueAddresses.count, addressCount)
        
        // And indices should be sequential
        for (index, address) in generatedAddresses.enumerated() {
            XCTAssertEqual(address.index, UInt32(index + 1)) // Starting from 1 after initial setup
        }
    }
    
    // MARK: - Address Discovery Tests
    
    func testAddressDiscoveryWithGapLimit() async throws {
        // Given: Account with gap limit
        testAccount.gapLimit = 5
        
        // When: Discovering addresses
        let discoveredAddresses = try await receiveTransactionService.discoverAddresses(
            for: testAccount,
            gapLimit: testAccount.gapLimit
        )
        
        // Then: Should discover up to gap limit
        XCTAssertGreaterThanOrEqual(discoveredAddresses.external.count, Int(testAccount.gapLimit))
        XCTAssertGreaterThan(discoveredAddresses.internal.count, 0)
        
        // All addresses should be valid
        for address in discoveredAddresses.external {
            XCTAssertTrue(validateDashAddress(address, network: testAccount.wallet?.network ?? .testnet))
        }
    }
    
    func testAddressDiscoveryWithUsedAddresses() async throws {
        // Given: Account with some used addresses (simulated)
        let usedAddresses = [
            generateTestAddress(index: 0, isChange: false),
            generateTestAddress(index: 1, isChange: false),
            generateTestAddress(index: 2, isChange: false)
        ]
        
        // Mark addresses as used (simulate transactions)
        for address in usedAddresses {
            receiveTransactionService.markAddressAsUsed(address.address)
        }
        
        // When: Discovering addresses
        let discoveredAddresses = try await receiveTransactionService.discoverAddresses(
            for: testAccount,
            gapLimit: 5
        )
        
        // Then: Should discover beyond used addresses
        XCTAssertGreaterThan(discoveredAddresses.external.count, 3)
    }
    
    func testAddressDiscoveryEmptyWallet() async throws {
        // Given: Fresh account with no transaction history
        let freshAccount = createTestAccount(label: "Fresh Account")
        
        // When: Discovering addresses
        let discoveredAddresses = try await receiveTransactionService.discoverAddresses(
            for: freshAccount,
            gapLimit: 5
        )
        
        // Then: Should generate initial set of addresses
        XCTAssertEqual(discoveredAddresses.external.count, 5) // Gap limit
        XCTAssertGreaterThan(discoveredAddresses.internal.count, 0)
    }
    
    // MARK: - Transaction Detection Tests
    
    func testIncomingTransactionDetection() async {
        // Given: Address watching setup
        let testAddress = createTestAddress()
        let expectation = XCTestExpectation(description: "Transaction detected")
        
        // Setup transaction detection
        receiveTransactionService.onTransactionReceived = { txid, amount, addresses in
            if addresses.contains(testAddress.address) {
                expectation.fulfill()
            }
        }
        
        // When: Simulating incoming transaction
        let incomingTx = createTestTransaction(
            amount: 100_000_000, // +1.0 DASH (positive = received)
            confirmations: 0
        )
        
        await receiveTransactionService.handleIncomingTransaction(
            txid: incomingTx.txid,
            amount: incomingTx.amount,
            addresses: [testAddress.address],
            confirmed: false,
            blockHeight: nil
        )
        
        // Then: Should detect transaction
        await fulfillment(of: [expectation], timeout: TestConstants.defaultTimeout)
    }
    
    func testTransactionConfirmationTracking() async {
        // Given: Unconfirmed transaction
        let testAddress = createTestAddress()
        let txid = generateTestTxid()
        let amount: Int64 = 50_000_000 // 0.5 DASH
        
        // Initial unconfirmed transaction
        await receiveTransactionService.handleIncomingTransaction(
            txid: txid,
            amount: amount,
            addresses: [testAddress.address],
            confirmed: false,
            blockHeight: nil
        )
        
        // When: Transaction gets confirmed
        await receiveTransactionService.handleTransactionConfirmation(
            txid: txid,
            blockHeight: 100000,
            confirmations: 1
        )
        
        // Then: Should update transaction status
        let transaction = receiveTransactionService.getTransaction(txid: txid)
        XCTAssertNotNil(transaction)
        XCTAssertEqual(transaction?.confirmations, 1)
        XCTAssertEqual(transaction?.height, 100000)
    }
    
    func testInstantSendDetection() async {
        // Given: InstantSend transaction
        let testAddress = createTestAddress()
        let txid = generateTestTxid()
        let amount: Int64 = 75_000_000 // 0.75 DASH
        
        // When: Receiving InstantSend transaction
        await receiveTransactionService.handleInstantSendTransaction(
            txid: txid,
            amount: amount,
            addresses: [testAddress.address]
        )
        
        // Then: Should be marked as InstantSend
        let transaction = receiveTransactionService.getTransaction(txid: txid)
        XCTAssertNotNil(transaction)
        XCTAssertTrue(transaction?.isInstantLocked ?? false)
        XCTAssertEqual(transaction?.status, .instantLocked)
    }
    
    func testMempoolTransactionHandling() async {
        // Given: Transaction in mempool
        let testAddress = createTestAddress()
        let txid = generateTestTxid()
        let amount: Int64 = 25_000_000 // 0.25 DASH
        
        // When: Receiving mempool transaction
        await receiveTransactionService.handleMempoolTransaction(
            txid: txid,
            amount: amount,
            addresses: [testAddress.address]
        )
        
        // Then: Should track mempool transaction
        let transaction = receiveTransactionService.getTransaction(txid: txid)
        XCTAssertNotNil(transaction)
        XCTAssertEqual(transaction?.confirmations, 0)
        XCTAssertTrue(transaction?.isPending ?? false)
    }
    
    // MARK: - Balance Update Tests
    
    func testBalanceUpdateOnReceive() async {
        // Given: Account with initial balance
        let initialBalance = createMockLocalBalance(confirmed: 100_000_000) // 1.0 DASH
        testAccount.balance = initialBalance
        
        let testAddress = createTestAddress()
        let receiveAmount: Int64 = 50_000_000 // 0.5 DASH
        
        // When: Receiving transaction
        await receiveTransactionService.handleIncomingTransaction(
            txid: generateTestTxid(),
            amount: receiveAmount,
            addresses: [testAddress.address],
            confirmed: true,
            blockHeight: 100000
        )
        
        // Update balance
        await receiveTransactionService.updateAccountLocalBalance(testAccount)
        
        // Then: Balance should increase
        let expectedTotal = initialBalance.total + UInt64(receiveAmount)
        XCTAssertEqual(testAccount.balance?.total, expectedTotal)
    }
    
    func testPendingBalanceTracking() async {
        // Given: Account with confirmed balance
        let confirmedBalance = createMockLocalBalance(confirmed: 100_000_000)
        testAccount.balance = confirmedBalance
        
        let testAddress = createTestAddress()
        let pendingAmount: Int64 = 30_000_000 // 0.3 DASH
        
        // When: Receiving unconfirmed transaction
        await receiveTransactionService.handleIncomingTransaction(
            txid: generateTestTxid(),
            amount: pendingAmount,
            addresses: [testAddress.address],
            confirmed: false,
            blockHeight: nil
        )
        
        // Update balance
        await receiveTransactionService.updateAccountLocalBalance(testAccount)
        
        // Then: Should track pending balance separately
        XCTAssertEqual(testAccount.balance?.confirmed, 100_000_000)
        XCTAssertEqual(testAccount.balance?.pending, UInt64(pendingAmount))
        XCTAssertEqual(testAccount.balance?.total, 100_000_000 + UInt64(pendingAmount))
    }
    
    func testInstantSendBalanceImmediate() async {
        // Given: Account with balance
        let initialBalance = createMockLocalBalance(confirmed: 200_000_000)
        testAccount.balance = initialBalance
        
        let testAddress = createTestAddress()
        let instantAmount: Int64 = 100_000_000 // 1.0 DASH
        
        // When: Receiving InstantSend transaction
        await receiveTransactionService.handleInstantSendTransaction(
            txid: generateTestTxid(),
            amount: instantAmount,
            addresses: [testAddress.address]
        )
        
        // Update balance
        await receiveTransactionService.updateAccountLocalBalance(testAccount)
        
        // Then: Should be immediately available
        XCTAssertEqual(testAccount.balance?.instantLocked, UInt64(instantAmount))
        XCTAssertEqual(testAccount.balance?.total, 200_000_000 + UInt64(instantAmount))
    }
    
    // MARK: - Address Monitoring Tests
    
    func testAddressWatchingSetup() async throws {
        // Given: New addresses to watch
        let addressesToWatch = [
            generateTestAddress(index: 0, isChange: false),
            generateTestAddress(index: 1, isChange: false),
            generateTestAddress(index: 0, isChange: true)
        ]
        
        // When: Setting up address watching
        try await receiveTransactionService.watchAddresses(addressesToWatch)
        
        // Then: All addresses should be monitored
        for address in addressesToWatch {
            let isWatched = receiveTransactionService.isAddressWatched(address.address)
            XCTAssertTrue(isWatched, "Address \(address.address) should be watched")
        }
    }
    
    func testAddressWatchingError() async {
        // Given: Invalid address
        let invalidAddress = HDWatchedAddress(
            address: "invalid_address",
            index: 0,
            isChange: false,
            derivationPath: "m/44'/1'/0'/0/0",
            label: "Invalid"
        )
        
        // When: Attempting to watch invalid address
        do {
            try await receiveTransactionService.watchAddresses([invalidAddress])
            XCTFail("Should throw error for invalid address")
        } catch {
            // Then: Should handle error gracefully
            XCTAssertTrue(error is WatchAddressError)
        }
    }
    
    func testBulkAddressWatching() async throws {
        // Given: Many addresses to watch
        var addresses: [HDWatchedAddress] = []
        for i in 0..<50 {
            addresses.append(generateTestAddress(index: UInt32(i), isChange: false))
        }
        
        // When: Watching many addresses at once
        try await receiveTransactionService.watchAddresses(addresses)
        
        // Then: All should be watched successfully
        let watchedCount = receiveTransactionService.getWatchedAddressCount()
        XCTAssertGreaterThanOrEqual(watchedCount, 50)
    }
    
    // MARK: - QR Code Integration Tests
    
    func testQRCodeGeneration() {
        // Given: Address for QR code
        let address = generateValidTestnetAddress()
        let amount: Double = 1.5 // 1.5 DASH
        let label = "Test Payment"
        
        // When: Generating QR code data
        let qrData = receiveTransactionService.generateQRCodeData(
            address: address,
            amount: amount,
            label: label
        )
        
        // Then: Should create valid QR data
        XCTAssertFalse(qrData.isEmpty)
        XCTAssertTrue(qrData.contains(address))
        XCTAssertTrue(qrData.contains("1.5"))
        XCTAssertTrue(qrData.contains(label))
    }
    
    func testQRCodeWithoutAmount() {
        // Given: Address only (no amount specified)
        let address = generateValidTestnetAddress()
        
        // When: Generating QR code without amount
        let qrData = receiveTransactionService.generateQRCodeData(
            address: address,
            amount: nil,
            label: nil
        )
        
        // Then: Should contain address only
        XCTAssertTrue(qrData.contains(address))
        XCTAssertFalse(qrData.contains("amount="))
    }
    
    func testBIP21URIGeneration() {
        // Given: Payment request parameters
        let address = generateValidTestnetAddress()
        let amount: Double = 0.12345678
        let label = "Coffee Shop"
        let message = "Payment for coffee"
        
        // When: Generating BIP21 URI
        let uri = receiveTransactionService.generateBIP21URI(
            address: address,
            amount: amount,
            label: label,
            message: message
        )
        
        // Then: Should follow BIP21 format
        XCTAssertTrue(uri.hasPrefix("dash:"))
        XCTAssertTrue(uri.contains(address))
        XCTAssertTrue(uri.contains("amount=0.12345678"))
        XCTAssertTrue(uri.contains("label=Coffee%20Shop"))
        XCTAssertTrue(uri.contains("message=Payment%20for%20coffee"))
    }
    
    // MARK: - Transaction History Tests
    
    func testTransactionHistoryRetrieval() async {
        // Given: Account with transaction history
        let transactions = [
            createTestTransaction(amount: 100_000_000, confirmations: 6),
            createTestTransaction(amount: 50_000_000, confirmations: 3),
            createTestTransaction(amount: 25_000_000, confirmations: 0)
        ]
        
        // Add transactions to service
        for tx in transactions {
            await receiveTransactionService.addTransaction(tx)
        }
        
        // When: Retrieving transaction history
        let history = receiveTransactionService.getTransactionHistory(for: testAccount)
        
        // Then: Should return all transactions
        XCTAssertGreaterThanOrEqual(history.count, 3)
        
        // Should be sorted by timestamp (newest first)
        for i in 0..<(history.count - 1) {
            XCTAssertGreaterThanOrEqual(
                history[i].timestamp,
                history[i + 1].timestamp
            )
        }
    }
    
    func testTransactionHistoryFiltering() async {
        // Given: Mixed transaction types
        let confirmedTx = createTestTransaction(amount: 100_000_000, confirmations: 6)
        let pendingTx = createTestTransaction(amount: 50_000_000, confirmations: 0)
        let instantTx = createTestTransaction(amount: 75_000_000, confirmations: 0, isInstantLocked: true)
        
        await receiveTransactionService.addTransaction(confirmedTx)
        await receiveTransactionService.addTransaction(pendingTx)
        await receiveTransactionService.addTransaction(instantTx)
        
        // When: Filtering by status
        let confirmedTransactions = receiveTransactionService.getTransactionHistory(
            for: testAccount,
            filter: .confirmed
        )
        let pendingTransactions = receiveTransactionService.getTransactionHistory(
            for: testAccount,
            filter: .pending
        )
        
        // Then: Should filter correctly
        XCTAssertTrue(confirmedTransactions.allSatisfy { $0.isConfirmed })
        XCTAssertTrue(pendingTransactions.allSatisfy { $0.isPending })
    }
    
    func testTransactionHistoryPagination() async {
        // Given: Many transactions
        for i in 0..<100 {
            let tx = createTestTransaction(
                txid: "tx_\(i)",
                amount: Int64(i * 1000)
            )
            await receiveTransactionService.addTransaction(tx)
        }
        
        // When: Requesting paginated results
        let firstPage = receiveTransactionService.getTransactionHistory(
            for: testAccount,
            limit: 20,
            offset: 0
        )
        let secondPage = receiveTransactionService.getTransactionHistory(
            for: testAccount,
            limit: 20,
            offset: 20
        )
        
        // Then: Should return correct page sizes
        XCTAssertEqual(firstPage.count, 20)
        XCTAssertEqual(secondPage.count, 20)
        
        // Pages should be different
        let firstPageTxids = Set(firstPage.map { $0.txid })
        let secondPageTxids = Set(secondPage.map { $0.txid })
        XCTAssertTrue(firstPageTxids.isDisjoint(with: secondPageTxids))
    }
    
    // MARK: - Address Activity Tracking Tests
    
    func testAddressActivityTimestamps() async {
        // Given: Address with recent activity
        let testAddress = createTestAddress()
        let activityTime = Date()
        
        // When: Recording address activity
        await receiveTransactionService.recordAddressActivity(
            address: testAddress.address,
            timestamp: activityTime
        )
        
        // Then: Should track activity timestamp
        let lastActivity = receiveTransactionService.getLastActivity(for: testAddress.address)
        XCTAssertNotNil(lastActivity)
        XCTAssertEqual(lastActivity?.timeIntervalSince1970, activityTime.timeIntervalSince1970, accuracy: 1.0)
    }
    
    func testRecentActivityDetection() async {
        // Given: Address with very recent activity
        let testAddress = createTestAddress()
        let recentTime = Date().addingTimeInterval(-60) // 1 minute ago
        
        await receiveTransactionService.recordAddressActivity(
            address: testAddress.address,
            timestamp: recentTime
        )
        
        // When: Checking for recent activity
        let hasRecentActivity = receiveTransactionService.hasRecentActivity(
            address: testAddress.address,
            threshold: 300 // 5 minutes
        )
        
        // Then: Should detect recent activity
        XCTAssertTrue(hasRecentActivity)
    }
    
    func testOldActivityDetection() async {
        // Given: Address with old activity
        let testAddress = createTestAddress()
        let oldTime = Date().addingTimeInterval(-3600) // 1 hour ago
        
        await receiveTransactionService.recordAddressActivity(
            address: testAddress.address,
            timestamp: oldTime
        )
        
        // When: Checking for recent activity
        let hasRecentActivity = receiveTransactionService.hasRecentActivity(
            address: testAddress.address,
            threshold: 300 // 5 minutes
        )
        
        // Then: Should not detect as recent
        XCTAssertFalse(hasRecentActivity)
    }
    
    // MARK: - Notification Tests
    
    func testFundsReceivedNotification() async {
        // Given: Notification setup
        let expectation = XCTestExpectation(description: "Funds received notification")
        var receivedAmount: UInt64 = 0
        var receivedTxid: String = ""
        
        receiveTransactionService.onFundsReceived = { amount, txid in
            receivedAmount = amount
            receivedTxid = txid
            expectation.fulfill()
        }
        
        // When: Receiving funds
        let testAddress = createTestAddress()
        let amount: Int64 = 100_000_000 // 1.0 DASH
        let txid = generateTestTxid()
        
        await receiveTransactionService.handleIncomingTransaction(
            txid: txid,
            amount: amount,
            addresses: [testAddress.address],
            confirmed: false,
            blockHeight: nil
        )
        
        // Then: Should trigger notification
        await fulfillment(of: [expectation], timeout: 5.0)
        XCTAssertEqual(receivedAmount, UInt64(amount))
        XCTAssertEqual(receivedTxid, txid)
    }
    
    func testTransactionConfirmedNotification() async {
        // Given: Pending transaction
        let testAddress = createTestAddress()
        let txid = generateTestTxid()
        let amount: Int64 = 50_000_000
        
        // Add pending transaction
        await receiveTransactionService.handleIncomingTransaction(
            txid: txid,
            amount: amount,
            addresses: [testAddress.address],
            confirmed: false,
            blockHeight: nil
        )
        
        // Setup confirmation notification
        let expectation = XCTestExpectation(description: "Transaction confirmed")
        receiveTransactionService.onTransactionConfirmed = { confirmedTxid in
            if confirmedTxid == txid {
                expectation.fulfill()
            }
        }
        
        // When: Transaction gets confirmed
        await receiveTransactionService.handleTransactionConfirmation(
            txid: txid,
            blockHeight: 100000,
            confirmations: 1
        )
        
        // Then: Should trigger confirmation notification
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidTransactionHandling() async {
        // Given: Invalid transaction data
        let invalidTxid = "" // Empty TXID
        let testAddress = createTestAddress()
        
        // When: Handling invalid transaction
        await receiveTransactionService.handleIncomingTransaction(
            txid: invalidTxid,
            amount: 100_000_000,
            addresses: [testAddress.address],
            confirmed: false,
            blockHeight: nil
        )
        
        // Then: Should handle gracefully without crashing
        let transaction = receiveTransactionService.getTransaction(txid: invalidTxid)
        XCTAssertNil(transaction) // Should not be stored
    }
    
    func testAddressNotFoundHandling() async {
        // Given: Transaction for unknown address
        let unknownAddress = "yUnknownAddressNotInWallet123456789"
        let txid = generateTestTxid()
        
        // When: Handling transaction for unknown address
        await receiveTransactionService.handleIncomingTransaction(
            txid: txid,
            amount: 100_000_000,
            addresses: [unknownAddress],
            confirmed: false,
            blockHeight: nil
        )
        
        // Then: Should not affect account balance
        let originalBalance = testAccount.balance?.total ?? 0
        await receiveTransactionService.updateAccountLocalBalance(testAccount)
        XCTAssertEqual(testAccount.balance?.total, originalBalance)
    }
    
    // MARK: - Performance Tests
    
    func testManyAddressGeneration() {
        // Given: Need for many addresses
        let addressCount = 1000
        let startTime = Date()
        
        // When: Generating many addresses
        do {
            for _ in 0..<addressCount {
                let _ = try receiveTransactionService.generateNewReceiveAddress(for: testAccount)
            }
            
            let generationTime = Date().timeIntervalSince(startTime)
            
            // Then: Should generate efficiently
            XCTAssertLessThan(generationTime, 10.0) // Should complete within 10 seconds
        } catch {
            XCTFail("Address generation should not fail: \(error)")
        }
    }
    
    func testManyTransactionHandling() async {
        // Given: Many incoming transactions
        let transactionCount = 500
        let testAddress = createTestAddress()
        let startTime = Date()
        
        // When: Processing many transactions
        for i in 0..<transactionCount {
            await receiveTransactionService.handleIncomingTransaction(
                txid: "tx_\(i)",
                amount: Int64(i * 1000),
                addresses: [testAddress.address],
                confirmed: i % 2 == 0, // Mix of confirmed/unconfirmed
                blockHeight: i % 2 == 0 ? UInt32(100000 + i) : nil
            )
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        // Then: Should process efficiently
        XCTAssertLessThan(processingTime, 15.0) // Should complete within 15 seconds
        
        // And: All transactions should be tracked
        let history = receiveTransactionService.getTransactionHistory(for: testAccount)
        XCTAssertGreaterThanOrEqual(history.count, transactionCount)
    }
}

// MARK: - Receive Transaction Service Mock

/// Mock service for testing receive transaction functionality
class ReceiveTransactionService {
    private let walletService: WalletService
    private var watchedAddresses: Set<String> = []
    private var transactions: [String: Transaction] = [:]
    private var addressActivity: [String: Date] = [:]
    
    // Callbacks for testing
    var onTransactionReceived: ((String, Int64, [String]) -> Void)?
    var onFundsReceived: ((UInt64, String) -> Void)?
    var onTransactionConfirmed: ((String) -> Void)?
    
    init(walletService: WalletService) {
        self.walletService = walletService
    }
    
    // MARK: - Address Generation
    
    func generateNewReceiveAddress(for account: HDAccount) throws -> HDWatchedAddress {
        guard let wallet = account.wallet else {
            throw WalletError.invalidState
        }
        
        let index = account.lastUsedExternalIndex + 1
        let address = generateTestAddress(index: index, isChange: false, network: wallet.network)
        let derivationPath = generateDerivationPath(
            network: wallet.network,
            account: account.accountIndex,
            change: false,
            index: index
        )
        
        let watchedAddress = HDWatchedAddress(
            address: address,
            index: index,
            isChange: false,
            derivationPath: derivationPath,
            label: "Receive"
        )
        
        watchedAddress.account = account
        account.addresses.append(watchedAddress)
        account.lastUsedExternalIndex = index
        
        return watchedAddress
    }
    
    func generateChangeAddress(for account: HDAccount) throws -> HDWatchedAddress {
        guard let wallet = account.wallet else {
            throw WalletError.invalidState
        }
        
        let index = account.lastUsedInternalIndex + 1
        let address = generateTestAddress(index: index, isChange: true, network: wallet.network)
        let derivationPath = generateDerivationPath(
            network: wallet.network,
            account: account.accountIndex,
            change: true,
            index: index
        )
        
        let watchedAddress = HDWatchedAddress(
            address: address,
            index: index,
            isChange: true,
            derivationPath: derivationPath,
            label: "Change"
        )
        
        watchedAddress.account = account
        account.addresses.append(watchedAddress)
        account.lastUsedInternalIndex = index
        
        return watchedAddress
    }
    
    // MARK: - Address Discovery
    
    func discoverAddresses(for account: HDAccount, gapLimit: UInt32) async throws -> (external: [String], internal: [String]) {
        var externalAddresses: [String] = []
        var internalAddresses: [String] = []
        
        // Generate external addresses up to gap limit
        for i in 0..<gapLimit {
            let address = generateTestAddress(index: i, isChange: false, network: account.wallet?.network ?? .testnet)
            externalAddresses.append(address)
        }
        
        // Generate some internal addresses
        for i in 0..<(gapLimit / 2) {
            let address = generateTestAddress(index: i, isChange: true, network: account.wallet?.network ?? .testnet)
            internalAddresses.append(address)
        }
        
        return (externalAddresses, internalAddresses)
    }
    
    func markAddressAsUsed(_ address: String) {
        addressActivity[address] = Date()
    }
    
    // MARK: - Address Watching
    
    func watchAddresses(_ addresses: [HDWatchedAddress]) async throws {
        for address in addresses {
            guard validateDashAddress(address.address, network: .testnet) else {
                throw WatchAddressError.invalidAddress(address.address)
            }
            watchedAddresses.insert(address.address)
        }
    }
    
    func isAddressWatched(_ address: String) -> Bool {
        return watchedAddresses.contains(address)
    }
    
    func getWatchedAddressCount() -> Int {
        return watchedAddresses.count
    }
    
    // MARK: - Transaction Handling
    
    func handleIncomingTransaction(
        txid: String,
        amount: Int64,
        addresses: [String],
        confirmed: Bool,
        blockHeight: UInt32?
    ) async {
        guard !txid.isEmpty else { return }
        
        let transaction = Transaction(
            txid: txid,
            height: blockHeight,
            timestamp: Date(),
            amount: amount,
            fee: 0,
            confirmations: confirmed ? 1 : 0,
            isInstantLocked: false,
            raw: Data(),
            size: 250,
            version: 3
        )
        
        transactions[txid] = transaction
        
        // Trigger callbacks
        onTransactionReceived?(txid, amount, addresses)
        if amount > 0 {
            onFundsReceived?(UInt64(amount), txid)
        }
    }
    
    func handleTransactionConfirmation(txid: String, blockHeight: UInt32, confirmations: UInt32) async {
        guard let transaction = transactions[txid] else { return }
        
        transaction.height = blockHeight
        transaction.confirmations = confirmations
        
        onTransactionConfirmed?(txid)
    }
    
    func handleInstantSendTransaction(txid: String, amount: Int64, addresses: [String]) async {
        let transaction = Transaction(
            txid: txid,
            height: nil,
            timestamp: Date(),
            amount: amount,
            fee: 0,
            confirmations: 0,
            isInstantLocked: true,
            raw: Data(),
            size: 250,
            version: 3
        )
        
        transactions[txid] = transaction
        
        onTransactionReceived?(txid, amount, addresses)
        if amount > 0 {
            onFundsReceived?(UInt64(amount), txid)
        }
    }
    
    func handleMempoolTransaction(txid: String, amount: Int64, addresses: [String]) async {
        await handleIncomingTransaction(
            txid: txid,
            amount: amount,
            addresses: addresses,
            confirmed: false,
            blockHeight: nil
        )
    }
    
    func addTransaction(_ transaction: Transaction) async {
        transactions[transaction.txid] = transaction
    }
    
    func getTransaction(txid: String) -> Transaction? {
        return transactions[txid]
    }
    
    // MARK: - Balance Updates
    
    func updateAccountLocalBalance(_ account: HDAccount) async {
        var confirmedTotal: UInt64 = 0
        var pendingTotal: UInt64 = 0
        var instantLockedTotal: UInt64 = 0
        
        for transaction in transactions.values {
            if transaction.amount > 0 { // Received funds
                let amount = UInt64(transaction.amount)
                if transaction.isInstantLocked {
                    instantLockedTotal += amount
                } else if transaction.confirmations > 0 {
                    confirmedTotal += amount
                } else {
                    pendingTotal += amount
                }
            }
        }
        
        let newBalance = LocalBalance(
            confirmed: confirmedTotal,
            pending: pendingTotal,
            instantLocked: instantLockedTotal,
            mempool: 0,
            mempoolInstant: 0,
            total: confirmedTotal + pendingTotal + instantLockedTotal
        )
        
        account.balance = newBalance
    }
    
    // MARK: - Transaction History
    
    func getTransactionHistory(for account: HDAccount, filter: TransactionFilter? = nil, limit: Int? = nil, offset: Int = 0) -> [Transaction] {
        var filtered = Array(transactions.values)
        
        // Apply filter
        if let filter = filter {
            switch filter {
            case .confirmed:
                filtered = filtered.filter { $0.isConfirmed }
            case .pending:
                filtered = filtered.filter { $0.isPending }
            case .instantSend:
                filtered = filtered.filter { $0.isInstantLocked }
            }
        }
        
        // Sort by timestamp (newest first)
        filtered.sort { $0.timestamp > $1.timestamp }
        
        // Apply pagination
        let startIndex = offset
        let endIndex = limit.map { min(startIndex + $0, filtered.count) } ?? filtered.count
        
        guard startIndex < filtered.count else { return [] }
        return Array(filtered[startIndex..<endIndex])
    }
    
    // MARK: - QR Code Generation
    
    func generateQRCodeData(address: String, amount: Double?, label: String?) -> String {
        var uri = "dash:\(address)"
        var params: [String] = []
        
        if let amount = amount {
            params.append("amount=\(amount)")
        }
        
        if let label = label {
            let encodedLabel = label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? label
            params.append("label=\(encodedLabel)")
        }
        
        if !params.isEmpty {
            uri += "?" + params.joined(separator: "&")
        }
        
        return uri
    }
    
    func generateBIP21URI(address: String, amount: Double?, label: String?, message: String?) -> String {
        var uri = "dash:\(address)"
        var params: [String] = []
        
        if let amount = amount {
            params.append("amount=\(amount)")
        }
        
        if let label = label {
            let encoded = label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? label
            params.append("label=\(encoded)")
        }
        
        if let message = message {
            let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message
            params.append("message=\(encoded)")
        }
        
        if !params.isEmpty {
            uri += "?" + params.joined(separator: "&")
        }
        
        return uri
    }
    
    // MARK: - Address Activity
    
    func recordAddressActivity(address: String, timestamp: Date) async {
        addressActivity[address] = timestamp
    }
    
    func getLastActivity(for address: String) -> Date? {
        return addressActivity[address]
    }
    
    func hasRecentActivity(address: String, threshold: TimeInterval) -> Bool {
        guard let lastActivity = addressActivity[address] else { return false }
        return Date().timeIntervalSince(lastActivity) < threshold
    }
    
    // MARK: - Helpers
    
    private func generateTestAddress(index: UInt32, isChange: Bool, network: DashNetwork) -> String {
        let prefix = network == .mainnet ? "X" : "y"
        let changeChar = isChange ? "c" : "r"
        return "\(prefix)\(changeChar)\(String(format: "%08x", index))TestAddress"
    }
    
    private func generateDerivationPath(network: DashNetwork, account: UInt32, change: Bool, index: UInt32) -> String {
        let coinType = network == .mainnet ? 5 : 1
        let changeValue = change ? 1 : 0
        return "m/44'/\(coinType)'/\(account)'/\(changeValue)/\(index)"
    }
    
    private func validateDashAddress(_ address: String, network: DashNetwork) -> Bool {
        guard !address.isEmpty else { return false }
        
        let firstChar = address.first!
        switch network {
        case .mainnet:
            return firstChar == "X" || firstChar == "7"
        case .testnet, .devnet, .regtest:
            return firstChar == "y" || firstChar == "8" || firstChar == "9"
        }
    }
}

// MARK: - Supporting Types

enum TransactionFilter {
    case confirmed
    case pending
    case instantSend
}

enum WatchAddressError: Error {
    case invalidAddress(String)
    case networkError
    case tooManyAddresses
}

enum WalletError: Error {
    case invalidState
}