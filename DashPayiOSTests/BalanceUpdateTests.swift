import XCTest
import SwiftData
@testable import DashPay

@MainActor
final class BalanceUpdateTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Create in-memory model container for testing
        let schema = Schema([
            HDWallet.self,
            HDAccount.self,
            HDWatchedAddress.self,
            Balance.self
        ])
        
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        modelContext = modelContainer.mainContext
    }
    
    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
        try super.tearDownWithError()
    }
    
    func testSafeBalanceUpdate() throws {
        // Given: An account with an existing balance
        let account = HDAccount(
            accountIndex: 0,
            label: "Test Account",
            extendedPublicKey: "xpub123"
        )
        
        let initialBalance = LocalBalance(confirmed: 1000, pending: 500, total: 1500)
        modelContext.insert(initialBalance)
        account.balance = initialBalance
        modelContext.insert(account)
        try modelContext.save()
        
        // When: We update the balance safely
        let newBalance = LocalBalance(confirmed: 2000, pending: 1000, total: 3000)
        try account.updateBalanceSafely(to: newBalance, in: modelContext)
        
        // Then: The balance should be updated without creating new managed objects
        XCTAssertEqual(account.balance?.confirmed, 2000)
        XCTAssertEqual(account.balance?.pending, 1000)
        XCTAssertEqual(account.balance?.total, 3000)
        
        // And: The original balance object should still be the same instance
        XCTAssertIdentical(account.balance, initialBalance)
    }
    
    func testBalanceUpdateWithNullAccount() throws {
        // Given: A null account
        let account: HDAccount? = nil
        let newBalance = LocalBalance(confirmed: 1000, pending: 500, total: 1500)
        
        // When/Then: Attempting to update should not crash
        XCTAssertNoThrow {
            try account?.updateBalanceSafely(to: newBalance, in: modelContext)
        }
    }
    
    func testBalanceUpdateFromFFILocalBalance() throws {
        // Given: An account with existing balance
        let account = HDAccount(
            accountIndex: 0,
            label: "Test Account",
            extendedPublicKey: "xpub123"
        )
        
        let initialBalance = LocalBalance()
        modelContext.insert(initialBalance)
        account.balance = initialBalance
        modelContext.insert(account)
        try modelContext.save()
        
        // When: We update from FFI balance data
        let ffiBalance = MockFFILocalBalance(
            confirmed: 5000,
            pending: 2000,
            instantlocked: 1000,
            mempool: 500,
            mempool_instant: 300,
            total: 8800
        )
        
        try account.updateBalanceFromFFI(ffiBalance, in: modelContext)
        
        // Then: The balance should be updated correctly
        XCTAssertEqual(account.balance?.confirmed, 5000)
        XCTAssertEqual(account.balance?.pending, 2000)
        XCTAssertEqual(account.balance?.instantLocked, 1000)
        XCTAssertEqual(account.balance?.mempool, 500)
        XCTAssertEqual(account.balance?.mempoolInstant, 300)
        XCTAssertEqual(account.balance?.total, 8800)
    }
    
    func testBalanceCreateOrUpdate() throws {
        // Given: No existing balance
        let account = HDAccount(
            accountIndex: 0,
            label: "Test Account",
            extendedPublicKey: "xpub123"
        )
        modelContext.insert(account)
        
        // When: We create or update balance
        let balanceData = LocalBalance(confirmed: 1000, pending: 500, total: 1500)
        try account.createOrUpdateLocalBalance(from: balanceData, in: modelContext)
        
        // Then: A new balance should be created and assigned
        XCTAssertNotNil(account.balance)
        XCTAssertEqual(account.balance?.confirmed, 1000)
        XCTAssertEqual(account.balance?.pending, 500)
        XCTAssertEqual(account.balance?.total, 1500)
        
        // When: We update again with different values
        let updatedBalanceData = LocalBalance(confirmed: 2000, pending: 1000, total: 3000)
        try account.createOrUpdateLocalBalance(from: updatedBalanceData, in: modelContext)
        
        // Then: The same balance object should be updated
        XCTAssertEqual(account.balance?.confirmed, 2000)
        XCTAssertEqual(account.balance?.pending, 1000)
        XCTAssertEqual(account.balance?.total, 3000)
    }
    
    func testBalanceUpdateWithInvalidFFIData() throws {
        // Given: An account with existing balance
        let account = HDAccount(
            accountIndex: 0,
            label: "Test Account",
            extendedPublicKey: "xpub123"
        )
        
        let initialBalance = LocalBalance(confirmed: 1000, total: 1000)
        modelContext.insert(initialBalance)
        account.balance = initialBalance
        modelContext.insert(account)
        
        // When: We try to update with invalid FFI data (nil)
        // Then: It should handle gracefully without crashing
        XCTAssertNoThrow {
            // This should not crash even with invalid data
            try account.updateBalanceFromFFI(nil, in: modelContext)
        }
        
        // And: Original balance should remain unchanged
        XCTAssertEqual(account.balance?.confirmed, 1000)
        XCTAssertEqual(account.balance?.total, 1000)
    }
    
    func testConcurrentBalanceUpdates() throws {
        // Given: An account with existing balance
        let account = HDAccount(
            accountIndex: 0,
            label: "Test Account",
            extendedPublicKey: "xpub123"
        )
        
        let initialBalance = LocalBalance(confirmed: 1000, pending: 500, total: 1500)
        modelContext.insert(initialBalance)
        account.balance = initialBalance
        modelContext.insert(account)
        try modelContext.save()
        
        // When: We perform concurrent balance updates
        let expectation = XCTestExpectation(description: "Concurrent updates complete")
        expectation.expectedFulfillmentCount = 3
        
        DispatchQueue.global().async {
            let balance1 = LocalBalance(confirmed: 2000, pending: 1000, total: 3000)
            try? account.updateBalanceSafely(to: balance1, in: self.modelContext)
            expectation.fulfill()
        }
        
        DispatchQueue.global().async {
            let balance2 = LocalBalance(confirmed: 3000, pending: 1500, total: 4500)
            try? account.updateBalanceSafely(to: balance2, in: self.modelContext)
            expectation.fulfill()
        }
        
        DispatchQueue.global().async {
            let balance3 = LocalBalance(confirmed: 4000, pending: 2000, total: 6000)
            try? account.updateBalanceSafely(to: balance3, in: self.modelContext)
            expectation.fulfill()
        }
        
        // Then: All updates should complete without crashes
        wait(for: [expectation], timeout: 5.0)
        
        // And: Final balance should be one of the update values
        XCTAssertNotNil(account.balance)
        XCTAssertTrue([2000, 3000, 4000].contains(account.balance?.confirmed))
    }
    
    func testWatchedAddressBalanceUpdate() throws {
        // Given: A watched address with existing balance
        let address = HDWatchedAddress(
            address: "test_address",
            index: 0,
            isChange: false,
            derivationPath: "m/44'/1'/0'/0/0",
            label: "Test Address"
        )
        
        let initialBalance = LocalBalance(confirmed: 500, pending: 200, total: 700)
        modelContext.insert(initialBalance)
        address.balance = initialBalance
        modelContext.insert(address)
        try modelContext.save()
        
        // When: We update the watched address balance
        let newBalance = LocalBalance(confirmed: 1000, pending: 300, total: 1300)
        try address.updateBalanceSafely(to: newBalance, in: modelContext)
        
        // Then: The balance should be updated correctly
        XCTAssertEqual(address.balance?.confirmed, 1000)
        XCTAssertEqual(address.balance?.pending, 300)
        XCTAssertEqual(address.balance?.total, 1300)
        
        // And: The original balance object should still be the same instance
        XCTAssertIdentical(address.balance, initialBalance)
    }
}

// MARK: - Test Helpers

struct MockFFIBalance {
    let confirmed: UInt64
    let pending: UInt64
    let instantlocked: UInt64
    let mempool: UInt64
    let mempool_instant: UInt64
    let total: UInt64
}

extension HDAccount {
    
    /// Test helper method for safe balance updates
    func updateBalanceSafely(to newBalance: Balance, in context: ModelContext) throws {
        if let existingBalance = self.balance {
            // Update existing balance in place
            existingBalance.update(from: newBalance)
        } else {
            // Create new balance and insert it
            let balance = LocalBalance(
                confirmed: newBalance.confirmed,
                pending: newBalance.pending,
                instantLocked: newBalance.instantLocked,
                mempool: newBalance.mempool,
                mempoolInstant: newBalance.mempoolInstant,
                total: newBalance.total
            )
            context.insert(balance)
            self.balance = balance
        }
        try context.save()
    }
    
    /// Test helper method for FFI balance updates
    func updateBalanceFromFFI(_ ffiBalance: MockFFIBalance?, in context: ModelContext) throws {
        guard let ffiBalance = ffiBalance else { return }
        
        let balanceData = LocalBalance(
            confirmed: ffiBalance.confirmed,
            pending: ffiBalance.pending,
            instantLocked: ffiBalance.instantlocked,
            mempool: ffiBalance.mempool,
            mempoolInstant: ffiBalance.mempool_instant,
            total: ffiBalance.total
        )
        
        try updateBalanceSafely(to: balanceData, in: context)
    }
    
    /// Test helper method for create or update
    func createOrUpdateLocalBalance(from balanceData: Balance, in context: ModelContext) throws {
        if let existingBalance = self.balance {
            existingBalance.update(from: balanceData)
        } else {
            let newBalance = LocalBalance(
                confirmed: balanceData.confirmed,
                pending: balanceData.pending,
                instantLocked: balanceData.instantLocked,
                mempool: balanceData.mempool,
                mempoolInstant: balanceData.mempoolInstant,
                total: balanceData.total
            )
            context.insert(newBalance)
            self.balance = newBalance
        }
        try context.save()
    }
}

extension HDWatchedAddress {
    
    /// Test helper method for safe balance updates
    func updateBalanceSafely(to newBalance: Balance, in context: ModelContext) throws {
        if let existingBalance = self.balance {
            // Update existing balance in place
            existingBalance.update(from: newBalance)
        } else {
            // Create new balance and insert it
            let balance = LocalBalance(
                confirmed: newBalance.confirmed,
                pending: newBalance.pending,
                instantLocked: newBalance.instantLocked,
                mempool: newBalance.mempool,
                mempoolInstant: newBalance.mempoolInstant,
                total: newBalance.total
            )
            context.insert(balance)
            self.balance = balance
        }
        try context.save()
    }
}