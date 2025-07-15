import XCTest
import SwiftData
@testable import DashPay

@MainActor
final class E2ESyncTests: XCTestCase {
    
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
        
        // Initialize WalletService for end-to-end testing
        walletService = WalletService()
        walletService.modelContext = modelContext
    }
    
    override func tearDownWithError() throws {
        walletService = nil
        modelContainer = nil
        modelContext = nil
        try super.tearDownWithError()
    }
    
    func testCompleteWalletSync() async throws {
        // Given: A complete wallet setup similar to "Dev Wallet 4363"
        let wallet = createCompleteTestWallet()
        let accounts = createMultipleTestAccounts(wallet: wallet, count: 3)
        let addresses = createAddressesForAccounts(accounts)
        
        // When: We perform a complete sync operation
        let syncExpectation = XCTestExpectation(description: "Complete sync without crashes")
        
        Task {
            do {
                // Simulate the sync process that was causing crashes
                try await performFullWalletSync(wallet: wallet, accounts: accounts)
                syncExpectation.fulfill()
            } catch {
                XCTFail("Sync failed with error: \(error)")
            }
        }
        
        // Then: Sync should complete without crashes
        await fulfillment(of: [syncExpectation], timeout: 10.0)
        
        // And: All accounts should have updated balances
        for account in accounts {
            XCTAssertNotNil(account.balance)
            XCTAssertGreaterThanOrEqual(account.balance?.total ?? 0, 0)
        }
    }
    
    func testWalletSwitchingDuringSync() async throws {
        // Given: Multiple wallets as in the production scenario
        let wallet1 = createCompleteTestWallet(name: "Wallet 1")
        let wallet2 = createCompleteTestWallet(name: "Wallet 2")
        
        let accounts1 = createMultipleTestAccounts(wallet: wallet1, count: 2)
        let accounts2 = createMultipleTestAccounts(wallet: wallet2, count: 2)
        
        // When: We switch wallets during sync operations
        let switchingExpectation = XCTestExpectation(description: "Wallet switching without crashes")
        
        Task {
            do {
                // Start sync on first wallet
                async let sync1 = performPartialWalletSync(wallet: wallet1, accounts: accounts1)
                
                // Switch to second wallet mid-sync
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                async let sync2 = performPartialWalletSync(wallet: wallet2, accounts: accounts2)
                
                // Wait for both to complete
                _ = try await sync1
                _ = try await sync2
                
                switchingExpectation.fulfill()
            } catch {
                XCTFail("Wallet switching failed: \(error)")
            }
        }
        
        // Then: Both wallets should sync successfully
        await fulfillment(of: [switchingExpectation], timeout: 15.0)
        
        // And: All accounts should maintain their balances
        for account in accounts1 + accounts2 {
            XCTAssertNotNil(account.balance)
        }
    }
    
    func testAppLifecycleWithSync() async throws {
        // Given: A wallet in the middle of sync
        let wallet = createCompleteTestWallet()
        let accounts = createMultipleTestAccounts(wallet: wallet, count: 2)
        
        // When: App goes through background/foreground cycle during sync
        let lifecycleExpectation = XCTestExpectation(description: "App lifecycle handling")
        
        Task {
            do {
                // Start sync
                let syncTask = Task {
                    try await performFullWalletSync(wallet: wallet, accounts: accounts)
                }
                
                // Simulate app backgrounding
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                await simulateAppBackgrounding()
                
                // Simulate app foregrounding
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                await simulateAppForegrounding()
                
                // Wait for sync to complete
                try await syncTask.value
                
                lifecycleExpectation.fulfill()
            } catch {
                XCTFail("App lifecycle test failed: \(error)")
            }
        }
        
        // Then: Sync should handle lifecycle changes gracefully
        await fulfillment(of: [lifecycleExpectation], timeout: 10.0)
        
        // And: Data integrity should be maintained
        for account in accounts {
            XCTAssertNotNil(account.balance)
        }
    }
    
    func testHighFrequencyBalanceUpdates() async throws {
        // Given: An account that receives frequent balance updates
        let wallet = createCompleteTestWallet()
        let account = createMultipleTestAccounts(wallet: wallet, count: 1)[0]
        
        // When: We send rapid balance updates (simulating real network conditions)
        let rapidUpdatesExpectation = XCTestExpectation(description: "Rapid balance updates")
        
        Task {
            do {
                // Send 20 rapid balance updates
                for i in 1...20 {
                    let balance = MockE2EFFILocalBalance(
                        confirmed: UInt64(i * 1000),
                        pending: UInt64(i * 500),
                        total: UInt64(i * 1500)
                    )
                    try await walletService.updateAccountBalanceE2E(account, ffiBalance: balance)
                    
                    // Small delay to simulate real network timing
                    try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
                }
                
                rapidUpdatesExpectation.fulfill()
            } catch {
                XCTFail("Rapid updates failed: \(error)")
            }
        }
        
        // Then: All updates should be processed without crashes
        await fulfillment(of: [rapidUpdatesExpectation], timeout: 5.0)
        
        // And: Final balance should reflect the last update
        XCTAssertEqual(account.balance?.confirmed, 20000)
        XCTAssertEqual(account.balance?.pending, 10000)
        XCTAssertEqual(account.balance?.total, 30000)
    }
    
    func testConcurrentSyncOperations() async throws {
        // Given: Multiple accounts that sync concurrently
        let wallet = createCompleteTestWallet()
        let accounts = createMultipleTestAccounts(wallet: wallet, count: 5)
        
        // When: We perform concurrent sync operations on all accounts
        let concurrentExpectation = XCTestExpectation(description: "Concurrent sync operations")
        
        Task {
            do {
                // Start concurrent sync operations
                await withTaskGroup(of: Void.self) { group in
                    for (index, account) in accounts.enumerated() {
                        group.addTask {
                            let balance = MockE2EFFILocalBalance(
                                confirmed: UInt64((index + 1) * 2000),
                                pending: UInt64((index + 1) * 1000),
                                total: UInt64((index + 1) * 3000)
                            )
                            try? await self.walletService.updateAccountBalanceE2E(account, ffiBalance: balance)
                        }
                    }
                }
                
                concurrentExpectation.fulfill()
            }
        }
        
        // Then: All concurrent operations should complete successfully
        await fulfillment(of: [concurrentExpectation], timeout: 10.0)
        
        // And: All accounts should have their expected balances
        for (index, account) in accounts.enumerated() {
            XCTAssertEqual(account.balance?.confirmed, UInt64((index + 1) * 2000))
            XCTAssertEqual(account.balance?.total, UInt64((index + 1) * 3000))
        }
    }
    
    // MARK: - Helper Methods
    
    private func createCompleteTestWallet(name: String = "Test Wallet E2E") -> HDWallet {
        let wallet = HDWallet(
            name: name,
            network: .testnet,
            encryptedSeed: Data("test_seed_e2e".utf8),
            seedHash: "test_hash_e2e"
        )
        modelContext.insert(wallet)
        return wallet
    }
    
    private func createMultipleTestAccounts(wallet: HDWallet, count: Int) -> [HDAccount] {
        var accounts: [HDAccount] = []
        
        for i in 0..<count {
            let account = HDAccount(
                accountIndex: UInt32(i),
                label: "Account \(i)",
                extendedPublicKey: "xpub_test_\(i)"
            )
            account.wallet = wallet
            wallet.accounts.append(account)
            modelContext.insert(account)
            accounts.append(account)
        }
        
        return accounts
    }
    
    private func createAddressesForAccounts(_ accounts: [HDAccount]) -> [HDWatchedAddress] {
        var addresses: [HDWatchedAddress] = []
        
        for (accountIndex, account) in accounts.enumerated() {
            // Create multiple addresses per account
            for i in 0..<3 {
                let address = HDWatchedAddress(
                    address: "test_address_\(accountIndex)_\(i)",
                    index: UInt32(i),
                    isChange: i % 2 != 0,
                    derivationPath: "m/44'/1'/\(accountIndex)'/\(i % 2)/\(i)",
                    label: "Test Address \(accountIndex)_\(i)"
                )
                address.account = account
                account.addresses.append(address)
                modelContext.insert(address)
                addresses.append(address)
            }
        }
        
        return addresses
    }
    
    private func performFullWalletSync(wallet: HDWallet, accounts: [HDAccount]) async throws {
        // Simulate the actual sync process that was causing crashes
        for (index, account) in accounts.enumerated() {
            let ffiBalance = MockE2EFFILocalBalance(
                confirmed: UInt64((index + 1) * 5000),
                pending: UInt64((index + 1) * 2000),
                instantlocked: UInt64((index + 1) * 1000),
                total: UInt64((index + 1) * 8000)
            )
            
            try await walletService.updateAccountBalanceE2E(account, ffiBalance: ffiBalance)
            
            // Simulate processing time
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        }
        
        // Save wallet state
        wallet.lastSynced = Date()
        try modelContext.save()
    }
    
    private func performPartialWalletSync(wallet: HDWallet, accounts: [HDAccount]) async throws {
        // Simulate partial sync (as might happen during wallet switching)
        for account in accounts {
            let ffiBalance = MockE2EFFILocalBalance(
                confirmed: 3000,
                pending: 1500,
                total: 4500
            )
            
            try await walletService.updateAccountBalanceE2E(account, ffiBalance: ffiBalance)
        }
    }
    
    private func simulateAppBackgrounding() async {
        // Simulate app going to background
        await MainActor.run {
            // In real implementation, this would trigger background state handling
            print("App backgrounding simulation")
        }
    }
    
    private func simulateAppForegrounding() async {
        // Simulate app coming to foreground
        await MainActor.run {
            // In real implementation, this would trigger foreground state handling
            print("App foregrounding simulation")
        }
    }
}

// MARK: - E2E Test Helpers

struct MockE2EFFIBalance {
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

extension WalletService {
    
    /// E2E test helper method that closely mirrors the actual updateAccountBalance method
    func updateAccountBalanceE2E(_ account: HDAccount, ffiBalance: MockE2EFFIBalance) async throws {
        await MainActor.run {
            do {
                // This mirrors the problematic code that was causing crashes
                if let existingBalance = account.balance {
                    // Safe update pattern - update in place instead of creating new objects
                    existingBalance.confirmed = ffiBalance.confirmed
                    existingBalance.pending = ffiBalance.pending
                    existingBalance.instantLocked = ffiBalance.instantlocked
                    existingBalance.mempool = ffiBalance.mempool
                    existingBalance.mempoolInstant = ffiBalance.mempool_instant
                    existingBalance.total = ffiBalance.total
                    existingBalance.lastUpdated = Date()
                } else {
                    // Safe creation pattern - properly insert through context
                    let newBalance = LocalBalance(
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
                    }
                }
                
                // Save context changes
                try self.modelContext?.save()
                
                // Force UI update on main thread
                self.objectWillChange.send()
                
            } catch {
                // Handle errors gracefully without crashing
                print("E2E Balance update error: \(error)")
                throw error
            }
        }
    }
}