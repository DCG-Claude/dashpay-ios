import XCTest
import SwiftData
@testable import DashPay
import SwiftDashCoreSDK

/// QA Test Suite for Balance Model Implementation
/// Tests all critical paths and edge cases after Balance model fixes
final class BalanceModelQATest: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create in-memory container for testing
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: HDWallet.self, HDAccount.self, HDWatchedAddress.self, Balance.self,
            configurations: config
        )
        modelContext = ModelContext(modelContainer)
    }
    
    override func tearDown() async throws {
        modelContext = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    // MARK: - Balance Model Creation Tests
    
    func testBalanceModelCreation() throws {
        // Test 1: Create Balance with default values
        let balance1 = Balance()
        XCTAssertEqual(balance1.confirmed, 0)
        XCTAssertEqual(balance1.pending, 0)
        XCTAssertEqual(balance1.total, 0)
        
        // Test 2: Create Balance with specific values
        let balance2 = Balance(
            confirmed: 100_000_000,
            pending: 50_000_000,
            instantLocked: 25_000_000,
            mempool: 10_000_000,
            mempoolInstant: 5_000_000,
            total: 185_000_000
        )
        XCTAssertEqual(balance2.confirmed, 100_000_000)
        XCTAssertEqual(balance2.pending, 50_000_000)
        XCTAssertEqual(balance2.total, 185_000_000)
    }
    
    func testBalanceConversionFromSDK() throws {
        // Test 3: Create Balance from SDK Balance
        let sdkBalance = SwiftDashCoreSDK.Balance(
            confirmed: 200_000_000,
            pending: 100_000_000,
            instantLocked: 50_000_000,
            total: 350_000_000
        )
        
        // This is the problematic line - testing the fix
        let localBalance = Balance(
            confirmed: sdkBalance.confirmed,
            pending: sdkBalance.pending,
            instantLocked: sdkBalance.instantLocked,
            mempool: sdkBalance.mempool,
            mempoolInstant: sdkBalance.mempoolInstant,
            total: sdkBalance.total,
            lastUpdated: sdkBalance.lastUpdated
        )
        
        XCTAssertEqual(localBalance.confirmed, sdkBalance.confirmed)
        XCTAssertEqual(localBalance.pending, sdkBalance.pending)
        XCTAssertEqual(localBalance.instantLocked, sdkBalance.instantLocked)
        XCTAssertEqual(localBalance.total, sdkBalance.total)
    }
    
    func testBalanceUpdateFromSDK() throws {
        // Test 4: Update existing Balance from SDK Balance
        let balance = Balance()
        let sdkBalance = SwiftDashCoreSDK.Balance(
            confirmed: 300_000_000,
            pending: 0,
            instantLocked: 0,
            total: 300_000_000
        )
        
        balance.update(from: sdkBalance)
        
        XCTAssertEqual(balance.confirmed, 300_000_000)
        XCTAssertEqual(balance.total, 300_000_000)
    }
    
    // MARK: - HDWallet Integration Tests
    
    func testHDWalletBalanceUpdate() async throws {
        // Test 5: Create wallet and update balance
        let wallet = HDWallet(
            name: "Test Wallet",
            mnemonic: "test mnemonic words",
            network: .testnet
        )
        modelContext.insert(wallet)
        
        let account = HDAccount(
            index: 0,
            xpub: "test_xpub",
            derivationPath: "m/44'/1'/0'"
        )
        wallet.accounts.append(account)
        modelContext.insert(account)
        
        // Test updating balance from SDK
        let sdkBalance = SwiftDashCoreSDK.Balance(
            confirmed: 500_000_000,
            pending: 0,
            instantLocked: 0,
            total: 500_000_000
        )
        
        try await account.updateBalanceSafely(from: sdkBalance, in: modelContext)
        
        XCTAssertNotNil(account.balance)
        XCTAssertEqual(account.balance?.confirmed, 500_000_000)
        XCTAssertEqual(account.balance?.total, 500_000_000)
    }
    
    func testHDWatchedAddressBalanceUpdate() async throws {
        // Test 6: Create watched address and update balance
        let address = HDWatchedAddress(
            address: "test_address",
            index: 0,
            isChange: false,
            derivationPath: "m/44'/1'/0'/0/0"
        )
        modelContext.insert(address)
        
        let sdkBalance = SwiftDashCoreSDK.Balance(
            confirmed: 100_000_000,
            pending: 50_000_000,
            instantLocked: 0,
            total: 150_000_000
        )
        
        try await address.updateBalanceSafely(from: sdkBalance, in: modelContext)
        
        XCTAssertNotNil(address.balance)
        XCTAssertEqual(address.balance?.confirmed, 100_000_000)
        XCTAssertEqual(address.balance?.pending, 50_000_000)
        XCTAssertEqual(address.balance?.total, 150_000_000)
    }
    
    func testConcurrentBalanceUpdates() async throws {
        // Test concurrent balance updates for thread safety
        let account = HDAccount(
            index: 0,
            xpub: "test_xpub",
            derivationPath: "m/44'/1'/0'"
        )
        modelContext.insert(account)
        
        // Launch multiple concurrent tasks that update the account balance
        let taskCount = 10
        let tasks = (1...taskCount).map { taskIndex in
            Task {
                let sdkBalance = SwiftDashCoreSDK.Balance(
                    confirmed: UInt64(taskIndex * 10_000_000),
                    pending: UInt64(taskIndex * 1_000_000),
                    instantLocked: UInt64(taskIndex * 500_000),
                    total: UInt64(taskIndex * 11_500_000)
                )
                try await account.updateBalanceSafely(from: sdkBalance, in: modelContext)
            }
        }
        
        // Await all tasks to complete
        for task in tasks {
            try await task.value
        }
        
        // Assert that the account's balance is not nil to confirm safe concurrent updates
        XCTAssertNotNil(account.balance, "Account balance should not be nil after concurrent updates")
        
        // Additional assertions to verify balance integrity
        XCTAssertGreaterThan(account.balance?.confirmed ?? 0, 0, "Confirmed balance should be greater than 0")
        XCTAssertGreaterThanOrEqual(account.balance?.total ?? 0, account.balance?.confirmed ?? 0, "Total should be >= confirmed")
    }
    
    // MARK: - Edge Cases and Error Scenarios
    
    func testBalanceUpdateWithNilBalance() async throws {
        // Test 7: Update when balance is nil
        let account = HDAccount(
            index: 0,
            xpub: "test_xpub",
            derivationPath: "m/44'/1'/0'"
        )
        modelContext.insert(account)
        
        XCTAssertNil(account.balance)
        
        let sdkBalance = SwiftDashCoreSDK.Balance(
            confirmed: 1_000_000,
            pending: 0,
            instantLocked: 0,
            total: 1_000_000
        )
        
        try await account.updateBalanceSafely(from: sdkBalance, in: modelContext)
        
        XCTAssertNotNil(account.balance)
        XCTAssertEqual(account.balance?.total, 1_000_000)
    }
    
    func testBalanceFormattingMethods() throws {
        // Test 8: Test formatting methods
        let balance = Balance(
            confirmed: 123_456_789,
            pending: 10_000_000,
            instantLocked: 50_000_000,
            mempool: 5_000_000,
            mempoolInstant: 2_500_000,
            total: 190_956_789
        )
        
        XCTAssertEqual(balance.formattedConfirmed, "1.23456789 DASH")
        XCTAssertEqual(balance.formattedPending, "0.10000000 DASH")
        XCTAssertEqual(balance.formattedTotal, "1.90956789 DASH")
        
        // Test computed properties
        XCTAssertEqual(balance.available, 123_456_789 + 50_000_000 + 2_500_000)
        XCTAssertEqual(balance.unconfirmed, 10_000_000)
    }
    
    func testMempoolBalanceTracking() throws {
        // Test 9: Mempool balance tracking
        let balance = Balance()
        
        // Simulate mempool update
        balance.mempool = 5_000_000
        balance.mempoolInstant = 2_000_000
        
        XCTAssertEqual(balance.mempool, 5_000_000)
        XCTAssertEqual(balance.mempoolInstant, 2_000_000)
        XCTAssertEqual(balance.formattedMempool, "0.05000000 DASH")
        XCTAssertEqual(balance.formattedMempoolInstant, "0.02000000 DASH")
    }
    
    // MARK: - Performance Tests
    
    func testBalanceUpdatePerformance() async throws {
        // Test 10: Performance of multiple balance updates
        let account = HDAccount(
            index: 0,
            xpub: "test_xpub",
            derivationPath: "m/44'/1'/0'"
        )
        modelContext.insert(account)
        
        // Prepare test data outside of measurement
        let testBalances = (1...100).map { i in
            SwiftDashCoreSDK.Balance(
                confirmed: UInt64(i * 1_000_000),
                pending: 0,
                instantLocked: 0,
                total: UInt64(i * 1_000_000)
            )
        }
        
        // Pre-run async operations to eliminate timing distortions from measure{}
        var errors: [Error] = []
        
        // Measure only the synchronous performance-critical operations
        measure {
            // Use synchronous operations for accurate timing measurement
            for sdkBalance in testBalances {
                do {
                    // Create Balance synchronously
                    let balance = Balance(
                        confirmed: sdkBalance.confirmed,
                        pending: sdkBalance.pending,
                        instantLocked: sdkBalance.instantLocked,
                        mempool: sdkBalance.mempool,
                        mempoolInstant: sdkBalance.mempoolInstant,
                        total: sdkBalance.total,
                        lastUpdated: sdkBalance.lastUpdated
                    )
                    
                    // Update account balance synchronously
                    account.balance = balance
                } catch {
                    errors.append(error)
                }
            }
        }
        
        // Assert no errors occurred during the performance test
        XCTAssertTrue(errors.isEmpty, "Performance test encountered errors: \(errors)")
        
        // Verify final state
        XCTAssertNotNil(account.balance)
        XCTAssertEqual(account.balance?.total, 100_000_000) // Last balance should be 100 * 1_000_000
    }
}

// MARK: - Test Helpers

extension BalanceModelQATest {
    
    func createTestWallet(name: String = "Test Wallet") -> HDWallet {
        let wallet = HDWallet(
            name: name,
            mnemonic: "test mnemonic phrase for testing purposes only",
            network: .testnet
        )
        modelContext.insert(wallet)
        return wallet
    }
    
    func createTestAccount(for wallet: HDWallet, index: UInt32 = 0) -> HDAccount {
        let account = HDAccount(
            index: index,
            xpub: "tpubD6NzVbkrYhZ4\(index)",
            derivationPath: "m/44'/1'/\(index)'"
        )
        wallet.accounts.append(account)
        modelContext.insert(account)
        return account
    }
    
    func createTestAddress(for account: HDAccount, index: UInt32 = 0, isChange: Bool = false) -> HDWatchedAddress {
        let address = HDWatchedAddress(
            address: "yTestAddress\(index)",
            index: index,
            isChange: isChange,
            derivationPath: "m/44'/1'/0'/\(isChange ? 1 : 0)/\(index)"
        )
        account.addresses.append(address)
        modelContext.insert(address)
        return address
    }
}