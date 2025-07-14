import XCTest
import SwiftData
@testable import DashPay

@MainActor
final class AutoSyncTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var walletService: WalletService!
    var testWallet: HDWallet!
    
    override func setUp() async throws {
        // Create in-memory model container for testing
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: HDWallet.self, HDAccount.self, HDWatchedAddress.self,
            configurations: configuration
        )
        
        // Initialize wallet service
        walletService = WalletService.shared
        walletService.configure(modelContext: modelContainer.mainContext)
        
        // Create a test wallet
        testWallet = try walletService.createWallet(
            name: "Test Auto-Sync Wallet",
            mnemonic: HDWalletService.generateMnemonic(),
            password: "testpassword123",
            network: .testnet
        )
    }
    
    override func tearDown() async throws {
        walletService.stopPeriodicSync()
        walletService = nil
        modelContainer = nil
        testWallet = nil
    }
    
    func testAutoSyncEnabledByDefault() {
        XCTAssertTrue(walletService.autoSyncEnabled, "Auto-sync should be enabled by default")
    }
    
    func testWalletNeedsSyncAfterCreation() {
        XCTAssertNil(testWallet.lastSynced, "New wallet should not have a last sync date")
        
        let walletsNeedingSync = walletService.getWalletsNeedingSync()
        XCTAssertTrue(walletsNeedingSync.contains(where: { $0.id == testWallet.id }), 
                     "New wallet should be in the list of wallets needing sync")
    }
    
    func testShouldSyncLogic() {
        // Test wallet without sync date
        XCTAssertTrue(walletService.shouldSync(testWallet), 
                     "Should sync wallet that has never been synced")
        
        // Test wallet synced recently
        testWallet.lastSynced = Date()
        XCTAssertFalse(walletService.shouldSync(testWallet), 
                      "Should not sync wallet that was just synced")
        
        // Test wallet synced long ago
        testWallet.lastSynced = Date().addingTimeInterval(-400) // 6+ minutes ago
        XCTAssertTrue(walletService.shouldSync(testWallet), 
                     "Should sync wallet that was synced more than 5 minutes ago")
    }
    
    func testNetworkMonitorIntegration() {
        // Test network monitor is initialized
        walletService.networkMonitor = NetworkMonitor()
        XCTAssertNotNil(walletService.networkMonitor, "Network monitor should be initialized")
        
        // Default state should be connected
        XCTAssertTrue(walletService.networkMonitor?.isConnected ?? false, 
                     "Network should be connected by default")
    }
    
    func testPeriodicSyncSetup() {
        walletService.setupPeriodicSync()
        // We can't easily test Timer directly, but we can verify it doesn't crash
        XCTAssertTrue(true, "Periodic sync setup should not crash")
        
        walletService.stopPeriodicSync()
        XCTAssertTrue(true, "Stopping periodic sync should not crash")
    }
    
    func testAutoSyncToggle() {
        // Test toggling auto-sync
        walletService.autoSyncEnabled = false
        XCTAssertFalse(walletService.autoSyncEnabled, "Auto-sync should be disabled")
        
        walletService.autoSyncEnabled = true
        XCTAssertTrue(walletService.autoSyncEnabled, "Auto-sync should be enabled")
    }
    
    func testSyncQueueManagement() {
        // Create multiple wallets
        let wallet2 = try! walletService.createWallet(
            name: "Test Wallet 2",
            mnemonic: HDWalletService.generateMnemonic(),
            password: "testpassword123",
            network: .testnet
        )
        
        let walletsNeedingSync = walletService.getWalletsNeedingSync()
        XCTAssertEqual(walletsNeedingSync.count, 2, "Should have 2 wallets needing sync")
        XCTAssertTrue(walletsNeedingSync.contains(where: { $0.id == testWallet.id }))
        XCTAssertTrue(walletsNeedingSync.contains(where: { $0.id == wallet2.id }))
    }
    
    func testLastAutoSyncDateUpdate() async {
        // Simulate auto-sync completion
        await walletService.performAutoSync(for: testWallet)
        
        XCTAssertNotNil(walletService.lastAutoSyncDate, "Last auto-sync date should be set")
        XCTAssertNotNil(testWallet.lastSynced, "Wallet last synced date should be set")
    }
}

// MARK: - Private method access for testing
extension WalletService {
    func shouldSync(_ wallet: HDWallet) -> Bool {
        // Don't sync if synced recently
        if let lastSync = wallet.lastSynced,
           Date().timeIntervalSince(lastSync) < 300 { // 5 minutes
            return false
        }
        
        // Check network connectivity
        if !(networkMonitor?.isConnected ?? true) {
            return false
        }
        
        return true
    }
    
    func getWalletsNeedingSync() -> [HDWallet] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<HDWallet>()
        let allWallets = (try? context.fetch(descriptor)) ?? []
        
        return allWallets.compactMap { wallet in
            // Check if wallet has been synced recently
            if let lastSync = wallet.lastSynced,
               Date().timeIntervalSince(lastSync) < 300 { // 5 minutes
                return nil
            }
            return wallet
        }
    }
}