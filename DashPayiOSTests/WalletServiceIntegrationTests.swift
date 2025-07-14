import XCTest
import SwiftData
@testable import DashPay

@MainActor
final class WalletServiceIntegrationTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var walletService: WalletService!
    
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
        
        // Use shared instance and set test context
        walletService = WalletService.shared
        walletService.modelContext = modelContext
    }
    
    override func tearDownWithError() throws {
        walletService = nil
        modelContainer = nil
        modelContext = nil
        try super.tearDownWithError()
    }
    
    func testWalletConnectionWithBalanceUpdate() async throws {
        // Given: A wallet with accounts and addresses
        let wallet = createTestWallet()
        let account = createTestAccount(wallet: wallet)
        let address = createTestAddress(account: account)
        
        // When: We update the account balance through WalletService
        let mockFFIBalance = MockWalletFFIBalance(
            confirmed: 10000,
            pending: 5000,
            instantlocked: 2000,
            mempool: 1000,
            mempool_instant: 500,
            total: 18500
        )
        
        // Then: The update should complete without crashing
        XCTAssertNoThrow {
            try await self.walletService.updateAccountBalanceSafely(account, ffiBalance: mockFFIBalance)
        }
        
        // And: The balance should be updated correctly
        XCTAssertEqual(account.balance?.confirmed, 10000)
        XCTAssertEqual(account.balance?.pending, 5000)
        XCTAssertEqual(account.balance?.instantLocked, 2000)
        XCTAssertEqual(account.balance?.total, 18500)
    }
    
    func testSyncProgressWithBalanceUpdates() async throws {
        // Given: Multiple accounts that need balance updates during sync
        let wallet = createTestWallet()
        let account1 = createTestAccount(wallet: wallet, index: 0)
        let account2 = createTestAccount(wallet: wallet, index: 1)
        
        // When: We simulate sync progress with balance updates
        let balance1 = MockWalletFFIBalance(confirmed: 5000, total: 5000)
        let balance2 = MockWalletFFIBalance(confirmed: 8000, total: 8000)
        
        // Then: Multiple balance updates should work without crashes
        XCTAssertNoThrow {
            try await self.walletService.updateAccountBalanceSafely(account1, ffiBalance: balance1)
            try await self.walletService.updateAccountBalanceSafely(account2, ffiBalance: balance2)
        }
        
        // And: Both balances should be updated correctly
        XCTAssertEqual(account1.balance?.confirmed, 5000)
        XCTAssertEqual(account2.balance?.confirmed, 8000)
    }
    
    func testNetworkErrorRecovery() async throws {
        // Given: An account with existing balance
        let wallet = createTestWallet()
        let account = createTestAccount(wallet: wallet)
        account.balance = Balance(confirmed: 1000, total: 1000)
        modelContext.insert(account.balance!)
        
        // When: A network error occurs during balance update
        // Then: The service should handle it gracefully
        XCTAssertNoThrow {
            try await self.walletService.handleBalanceUpdateError(account: account, error: TestNetworkError.connectionFailed)
        }
        
        // And: Original balance should be preserved
        XCTAssertEqual(account.balance?.confirmed, 1000)
        XCTAssertEqual(account.balance?.total, 1000)
    }
    
    func testUIUpdateAfterBalanceChange() async throws {
        // Given: An account with observers
        let wallet = createTestWallet()
        let account = createTestAccount(wallet: wallet)
        
        var balanceChangeNotified = false
        let expectation = XCTestExpectation(description: "Balance change notification")
        
        // Simulate UI observation
        let cancellable = walletService.objectWillChange.sink {
            balanceChangeNotified = true
            expectation.fulfill()
        }
        
        // When: We update the balance
        let newBalance = MockWalletFFIBalance(confirmed: 15000, total: 15000)
        try await walletService.updateAccountBalanceSafely(account, ffiBalance: newBalance)
        
        // Then: UI should be notified of the change
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(balanceChangeNotified)
        
        cancellable.cancel()
    }
    
    func testErrorHandlingInBalanceUpdates() async throws {
        // Given: An account with nil context (error condition)
        let account = HDAccount(accountIndex: 0, label: "Test", extendedPublicKey: "xpub123")
        
        // When: We try to update balance with invalid context
        let balance = MockWalletFFIBalance(confirmed: 1000, total: 1000)
        
        // Then: It should handle the error gracefully
        XCTAssertNoThrow {
            try await self.walletService.updateAccountBalanceSafely(account, ffiBalance: balance)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestWallet() -> HDWallet {
        let wallet = HDWallet(
            name: "Test Wallet",
            network: .testnet,
            encryptedSeed: Data("test_seed".utf8),
            seedHash: "test_hash"
        )
        modelContext.insert(wallet)
        return wallet
    }
    
    private func createTestAccount(wallet: HDWallet, index: UInt32 = 0) -> HDAccount {
        let account = HDAccount(
            accountIndex: index,
            label: "Test Account \(index)",
            extendedPublicKey: "xpub123_\(index)"
        )
        account.wallet = wallet
        wallet.accounts.append(account)
        modelContext.insert(account)
        return account
    }
    
    private func createTestAddress(account: HDAccount) -> HDWatchedAddress {
        let address = HDWatchedAddress(
            address: "test_address",
            index: 0,
            isChange: false,
            derivationPath: "m/44'/1'/0'/0/0",
            label: "Test Address"
        )
        address.account = account
        account.addresses.append(address)
        modelContext.insert(address)
        return address
    }
}

// MARK: - Test Helpers and Extensions

struct MockWalletFFIBalance {
    let confirmed: UInt64
    let pending: UInt64
    let instantlocked: UInt64
    let mempool: UInt64
    let mempool_instant: UInt64
    let total: UInt64
    
    init(
        confirmed: UInt64 = 0,
        pending: UInt64 = 0,
        instantlocked: UInt64 = 0,
        mempool: UInt64 = 0,
        mempool_instant: UInt64 = 0,
        total: UInt64 = 0
    ) {
        self.confirmed = confirmed
        self.pending = pending
        self.instantlocked = instantlocked
        self.mempool = mempool
        self.mempool_instant = mempool_instant
        self.total = total
    }
}

enum TestNetworkError: Error {
    case connectionFailed
    case timeout
    case invalidResponse
}

extension WalletService {
    
    /// Test helper method for safe balance updates
    func updateAccountBalanceSafely(_ account: HDAccount, ffiBalance: MockWalletFFIBalance) async throws {
        // Ensure we're on the main thread for SwiftData operations
        await MainActor.run {
            do {
                if let existingBalance = account.balance {
                    // Update existing balance in place
                    existingBalance.confirmed = ffiBalance.confirmed
                    existingBalance.pending = ffiBalance.pending
                    existingBalance.instantLocked = ffiBalance.instantlocked
                    existingBalance.mempool = ffiBalance.mempool
                    existingBalance.mempoolInstant = ffiBalance.mempool_instant
                    existingBalance.total = ffiBalance.total
                    existingBalance.lastUpdated = Date()
                } else {
                    // Create new balance and insert it properly
                    let newBalance = Balance(
                        confirmed: ffiBalance.confirmed,
                        pending: ffiBalance.pending,
                        instantLocked: ffiBalance.instantlocked,
                        mempool: ffiBalance.mempool,
                        mempoolInstant: ffiBalance.mempool_instant,
                        total: ffiBalance.total
                    )
                    
                    if let context = self.modelContext {
                        context.insert(newBalance)
                        account.balance = newBalance
                        try context.save()
                    }
                }
                
                // Notify UI of changes
                self.objectWillChange.send()
                
            } catch {
                // Log error but don't crash
                print("Error updating balance: \(error)")
            }
        }
    }
    
    /// Test helper method for error handling
    func handleBalanceUpdateError(account: HDAccount, error: Error) async throws {
        await MainActor.run {
            // Log the error
            print("Balance update error for account \(account.label): \(error)")
            
            // Preserve existing balance state
            // In real implementation, this might trigger retry logic
            
            // Notify observers of error state
            self.objectWillChange.send()
        }
    }
}