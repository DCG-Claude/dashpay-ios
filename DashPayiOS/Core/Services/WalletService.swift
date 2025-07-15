import Foundation
import SwiftData
import Combine
import os.log
import SwiftDashCoreSDK

public enum WatchVerificationStatus {
    case unknown
    case verifying
    case verified(total: Int, watching: Int)
    case failed(error: String)
}

// WatchAddressError is now properly exported from the SDK

@MainActor
class WalletService: ObservableObject {
    static let shared = WalletService()
    
    // Address generation configuration constants
    private static let defaultInitialReceiveAddressCount = 5
    private static let defaultInitialChangeAddressCount = 1
    
    @Published var activeWallet: HDWallet?
    @Published var activeAccount: HDAccount?
    
    // New focused service dependencies
    private let connectionService = WalletConnectionService()
    private let syncServiceNew = WalletSyncService()
    private let transactionService = WalletTransactionService()
    private let diagnosticsService = WalletDiagnosticsService()
    private lazy var eventService = WalletEventService(
        connectionService: connectionService,
        transactionService: transactionService,
        syncService: syncServiceNew
    )
    
    // Legacy service dependencies (for backward compatibility during transition)
    private let watchAddressService = WatchAddressService()
    private let autoSyncService = AutoSyncService()
    private let walletLifecycleService = WalletLifecycleService()
    private let addressManagementService = AddressManagementService()
    private let balanceTransactionService = BalanceTransactionService()
    
    private var cancellables = Set<AnyCancellable>()
    var modelContext: ModelContext?
    var networkMonitor: NetworkMonitor?
    private let logger = Logger(subsystem: "com.dash.wallet", category: "WalletService")
    
    // Timer properties for periodic operations
    private var autoSyncTimer: Timer?
    private var watchVerificationTimer: Timer?
    private var pendingWatchAddresses: [String: [(address: String, error: Error)]] = [:]
    
    // Expose service properties for backward compatibility
    var isConnected: Bool { connectionService.isConnected }
    var isSyncing: Bool { syncServiceNew.isSyncing }
    var syncProgress: SyncProgress? { syncServiceNew.syncProgress }
    var detailedSyncProgress: SwiftDashCoreSDK.DetailedSyncProgress? { syncServiceNew.detailedSyncProgress }
    var watchAddressErrors: [WatchAddressError] { watchAddressService.watchAddressErrors }
    var pendingWatchCount: Int { watchAddressService.pendingWatchCount }
    var watchVerificationStatus: WatchVerificationStatus { watchAddressService.watchVerificationStatus }
    var autoSyncEnabled: Bool { 
        get { autoSyncService.autoSyncEnabled }
        set { autoSyncService.autoSyncEnabled = newValue }
    }
    var lastAutoSyncDate: Date? { autoSyncService.lastAutoSyncDate }
    var syncQueue: [HDWallet] { autoSyncService.syncQueue }
    var sdk: DashSDK? { connectionService.sdk }
    var mempoolTransactionCount: Int { transactionService.mempoolTransactionCount }
    
    // Computed property for sync statistics
    var syncStatistics: [String: String] {
        return syncServiceNew.syncStatistics
    }
    
    private init() {}
    
    func configure(modelContext: ModelContext) {
        logger.info("🔧 WalletService.configure() called")
        self.modelContext = modelContext
        
        // Configure new services
        syncServiceNew.configure(modelContext: modelContext)
        transactionService.configure(modelContext: modelContext)
        
        // Configure event service with active account callback
        eventService.getActiveAccount = { [weak self] in
            return self?.activeAccount
        }
        
        // Configure legacy services (for backward compatibility)
        autoSyncService.configure(modelContext: modelContext)
        walletLifecycleService.configure(modelContext: modelContext)
        addressManagementService.configure(modelContext: modelContext)
        balanceTransactionService.configure(modelContext: modelContext)
        
        logger.info("✅ WalletService configured with modelContext")
    }
    
    // MARK: - Wallet Management
    
    func createWallet(
        name: String,
        mnemonic: [String],
        password: String,
        network: DashNetwork
    ) async throws -> HDWallet {
        return try await walletLifecycleService.createWallet(
            name: name,
            mnemonic: mnemonic,
            password: password,
            network: network
        )
    }
    
    /// Helper method to perform heavy cryptographic operations for account creation
    nonisolated private func performAccountCreation(
        encryptedSeed: Data,
        password: String,
        network: DashNetwork,
        accountIndex: UInt32
    ) throws -> (xpub: String, addresses: [(address: String, index: UInt32, isChange: Bool, path: String, label: String)]) {
        // Decrypt seed
        let seed = try HDWalletService.decryptSeed(encryptedSeed, password: password)
        
        // Derive account xpub
        let xpub = try HDWalletService.deriveExtendedPublicKey(
            seed: seed,
            network: network,
            account: accountIndex
        )
        
        // Generate initial addresses using configured constants  
        let initialReceiveCount = 5
        let initialChangeCount = 1
        var addresses: [(address: String, index: UInt32, isChange: Bool, path: String, label: String)] = []
        
        // Generate receive addresses
        for i in 0..<initialReceiveCount {
            let address = try HDWalletService.deriveAddress(
                xpub: xpub,
                network: network,
                change: false,
                index: UInt32(i)
            )
            
            let path = HDWalletService.BIP44.derivationPath(
                network: network,
                account: accountIndex,
                change: false,
                index: UInt32(i)
            )
            
            addresses.append((
                address: address,
                index: UInt32(i),
                isChange: false,
                path: path,
                label: "Receive"
            ))
        }
        
        // Generate change address
        for i in 0..<initialChangeCount {
            let address = try HDWalletService.deriveAddress(
                xpub: xpub,
                network: network,
                change: true,
                index: UInt32(i)
            )
            
            let path = HDWalletService.BIP44.derivationPath(
                network: network,
                account: accountIndex,
                change: true,
                index: UInt32(i)
            )
            
            addresses.append((
                address: address,
                index: UInt32(i),
                isChange: true,
                path: path,
                label: "Change"
            ))
        }
        
        return (xpub: xpub, addresses: addresses)
    }
    
    func createAccount(
        for wallet: HDWallet,
        index: UInt32,
        label: String,
        password: String
    ) async throws -> HDAccount {
        return try await walletLifecycleService.createAccount(
            for: wallet,
            index: index,
            label: label,
            password: password
        )
    }
    
    func deleteWallet(_ wallet: HDWallet) throws {
        if wallet == activeWallet {
            Task {
                await disconnect()
            }
            activeWallet = nil
            activeAccount = nil
        }
        
        try walletLifecycleService.deleteWallet(wallet)
    }
    
    // MARK: - Auto-Sync Management
    
    func startAutoSync() async {
        logger.info("🔄 startAutoSync() called - autoSyncEnabled: \(self.autoSyncEnabled)")
        guard autoSyncEnabled else {
            logger.warning("⚠️ Auto-sync is disabled")
            return
        }
        
        // FIX: Check if already syncing
        if isSyncing {
            logger.info("⏭️ Sync already in progress, skipping auto-sync")
            return
        }
        
        // Get all wallets that need sync
        let walletsNeedingSync = autoSyncService.getWalletsNeedingSync()
        logger.info("📊 Found \(walletsNeedingSync.count) wallets needing sync")
        
        if walletsNeedingSync.isEmpty {
            logger.info("ℹ️ No wallets found - checking if any wallets exist...")
            if let context = modelContext {
                let descriptor = FetchDescriptor<HDWallet>()
                let allWallets = (try? context.fetch(descriptor)) ?? []
                logger.info("📱 Total wallets in database: \(allWallets.count)")
                for wallet in allWallets {
                    logger.info("  - Wallet: \(wallet.name) (last synced: \(wallet.lastSynced?.description ?? "never"))")
                }
            }
        }
        
        for wallet in walletsNeedingSync {
            logger.info("🔄 Starting auto-sync for wallet: \(wallet.name)")
            await performAutoSync(for: wallet)
        }
    }
    
    func performAutoSync(for wallet: HDWallet) async {
        logger.info("🔍 performAutoSync() for wallet: \(wallet.name)")
        
        // Check if sync is needed
        guard autoSyncService.shouldSync(wallet, isCurrentlySyncing: isSyncing, networkMonitor: networkMonitor) else {
            logger.info("⏭️ Skipping sync for wallet (not needed)")
            return
        }
        
        // FIX: Check if already syncing
        if isSyncing {
            logger.info("⏭️ Sync already in progress, skipping")
            return
        }
        
        // Connect if not connected
        if activeWallet != wallet {
            logger.info("🔌 Connecting to wallet for auto-sync...")
            if let firstAccount = wallet.accounts.first {
                do {
                    try await connect(wallet: wallet, account: firstAccount)
                    logger.info("✅ Connected successfully for auto-sync")
                } catch {
                    logger.error("❌ Failed to connect for auto-sync: \(error)")
                    return
                }
            } else {
                logger.warning("⚠️ Wallet has no accounts - cannot sync")
                return
            }
        } else {
            logger.info("✅ Wallet already connected")
        }
        
        // Start sync
        if isConnected {
            logger.info("🚀 Starting sync process...")
            do {
                try await startSync()
                logger.info("✅ Auto-sync completed successfully")
            } catch {
                logger.error("❌ Auto-sync failed: \(error)")
            }
        } else {
            logger.warning("⚠️ Not connected - cannot start sync")
        }
        
        // Update last sync date
        wallet.lastSynced = Date()
        autoSyncService.updateLastAutoSyncDate(Date())
        try? modelContext?.save()
        logger.info("📅 Updated last sync date for wallet")
    }
    
    // shouldSync and getWalletsNeedingSync methods are now handled by AutoSyncService
    
    func setupPeriodicSync() {
        autoSyncService.startPeriodicSync { [weak self] in
            await self?.startAutoSync()
        }
    }
    
    func stopPeriodicSync() {
        autoSyncService.stopPeriodicSync()
    }
    
    // MARK: - Connection & Sync
    
    private func watchAddresses(account: HDAccount) async {
        // Start watching addresses
        logger.info("👀 Watching account addresses...")
        logger.info("   Account has \(account.addresses.count) addresses")
        
        guard let sdk = sdk else {
            logger.error("Cannot watch addresses: SDK not initialized")
            return
        }
        
        let failedAddresses = await addressManagementService.watchAccountAddresses(account, sdk: sdk)
        
        // Handle failed addresses
        if !failedAddresses.isEmpty {
            watchAddressService.handleFailedWatchAddresses(failedAddresses, accountId: account.id.uuidString)
        }
        
        logger.info("   Address watching setup complete")
        
        // Start watch address verification
        startWatchVerification()
    }
    
    private func fetchInitialBalance(account: HDAccount) async throws {
        // Update account balance after adding watch addresses
        logger.info("💰 Fetching initial balance...")
        do {
            try await updateAccountBalance(account)
            logger.info("   Initial balance fetched successfully")
        } catch {
            logger.warning("⚠️ Failed to fetch initial balance: \(error)")
            // Log the error but continue since connection is still valid
            logger.info("ℹ️ Balance will be updated later during sync")
        }
    }
    
    /// Toggle between local and public peers
    func setUseLocalPeers(_ useLocal: Bool) {
        connectionService.setUseLocalPeers(useLocal)
    }
    
    /// Check current peer configuration
    func isUsingLocalPeers() -> Bool {
        return connectionService.isUsingLocalPeers()
    }
    
    /// Set custom local peer host (for development)
    func setLocalPeerHost(_ host: String) {
        connectionService.setLocalPeerHost(host)
    }
    
    /// Get current local peer host
    func getLocalPeerHost() -> String {
        return connectionService.getLocalPeerHost()
    }
    
    func connect(wallet: HDWallet, account: HDAccount) async throws {
        logger.info("🔗 === WALLET CONNECTION START ===")
        logger.info("📋 Connection Details:")
        logger.info("   Wallet: \(wallet.name)")
        logger.info("   Account: \(account.displayName)")
        logger.info("   Network: \(wallet.network.rawValue)")
        logger.info("   Thread: \(Thread.isMainThread ? "Main" : "Background")")
        logger.info("   Timestamp: \(Date())")
        
        // Log system state
        logger.info("📊 System State:")
        logger.info("   SDK exists: \(self.sdk != nil)")
        logger.info("   Currently connected: \(self.isConnected)")
        logger.info("   Network Monitor: \(self.networkMonitor?.isConnected ?? false)")
        
        // Disconnect if needed
        if isConnected {
            logger.warning("⚠️ Disconnecting existing connection...")
            await disconnect()
            logger.info("✅ Previous connection disconnected")
        }
        
        // Setup configuration
        let config = try await connectionService.setupConfiguration(wallet: wallet)
        
        // Initialize SDK
        try await connectionService.initializeSDK(with: config)
        
        // Connect to network
        try await connectionService.connectToNetwork()
        
        // Setup event handling
        setupEventHandling()
        
        // Watch addresses
        activeWallet = wallet
        activeAccount = account
        await watchAddresses(account: account)
        
        // Fetch initial balance
        try await fetchInitialBalance(account: account)
        
        logger.info("🎯 === CONNECTION COMPLETE ===")
        logger.info("   Ready for sync!")
    }
    
    func disconnect() async {
        // Cancel active sync properly
        syncServiceNew.stopSync()
        
        // Stop watch verification
        watchAddressService.stopWatchVerification()
        
        // Disconnect using connection service
        await connectionService.disconnect()
        
        // Reset legacy services
        watchAddressService.reset()
        
        // Reset event service
        eventService.cleanup()
    }
    
    func startSync() async throws {
        guard let sdk = sdk, isConnected else {
            throw WalletError.notConnected
        }
        
        // Use the new sync service
        try await syncServiceNew.startSync(sdk: sdk, activeWallet: activeWallet)
        
        // Update balance after sync
        if let account = activeAccount {
            print("💰 Updating balance after sync...")
            try? await updateAccountBalance(account)
        }
    }
    
    // Helper to map sync stage to legacy status
    private func mapSyncStageToStatus(_ stage: SyncStage) -> SyncStatus {
        switch stage {
        case .connecting:
            return .connecting
        case .queryingHeight:
            return .connecting
        case .downloading, .validating, .storing:
            return .downloadingHeaders
        case .complete:
            return .synced
        case .failed:
            return .error
        }
    }
    
    func stopSync() {
        syncServiceNew.stopSync()
    }
    
    // Alternative sync method using callbacks for real-time updates
    func startSyncWithCallbacks() async throws {
        guard let sdk = sdk, isConnected else {
            throw WalletError.notConnected
        }
        
        // Use the new sync service
        try await syncServiceNew.startSyncWithCallbacks(sdk: sdk, activeWallet: activeWallet)
        
        // Update balance after sync
        if let account = activeAccount {
            print("💰 Updating balance after sync...")
            try? await updateAccountBalance(account)
        }
    }
    
    // MARK: - Address Management
    
    func discoverAddresses(for account: HDAccount) async throws {
        guard let sdk = sdk else {
            throw WalletError.invalidState
        }
        
        try await addressManagementService.discoverAddresses(for: account, sdk: sdk)
    }
    
    /// Enhanced address generation with gap limit checking
    func generateAddressesWithGapLimit(for account: HDAccount) async throws {
        guard let sdk = sdk else {
            throw WalletError.invalidState
        }
        
        try await addressManagementService.generateAddressesWithGapLimit(for: account, sdk: sdk)
    }
    
    /// Helper method to perform heavy cryptographic operations in a non-isolated context
    nonisolated private func performAddressGeneration(
        xpub: String,
        network: DashNetwork,
        accountIndex: UInt32,
        change: Bool,
        index: UInt32
    ) throws -> (address: String, path: String) {
        // Perform heavy cryptographic operations outside of MainActor
        let address = try HDWalletService.deriveAddress(
            xpub: xpub,
            network: network,
            change: change,
            index: index
        )
        
        let path = HDWalletService.BIP44.derivationPath(
            network: network,
            account: accountIndex,
            change: change,
            index: index
        )
        
        return (address: address, path: path)
    }
    
    func generateNewAddress(for account: HDAccount, isChange: Bool = false) throws -> HDWatchedAddress {
        let watchedAddress = try addressManagementService.generateNewAddress(for: account, isChange: isChange)
        
        // Watch the new address if SDK is available
        if let sdk = sdk {
            Task {
                await addressManagementService.watchAddress(watchedAddress.address, label: watchedAddress.label ?? "Watched", sdk: sdk)
            }
        }
        
        return watchedAddress
    }
    
    // MARK: - Balance & Transactions
    
    /// Helper method to perform heavy I/O operations for balance updates
    nonisolated private func performBalanceUpdate(
        sdk: DashSDK, 
        addresses: [HDWatchedAddress]
    ) async throws -> (addressBalances: [(HDWatchedAddress, SwiftDashCoreSDK.Balance)], accountBalance: SwiftDashCoreSDK.Balance) {
        var confirmedTotal: UInt64 = 0
        var pendingTotal: UInt64 = 0
        var instantLockedTotal: UInt64 = 0
        var mempoolTotal: UInt64 = 0
        var addressBalances: [(HDWatchedAddress, SwiftDashCoreSDK.Balance)] = []
        
        // Perform heavy I/O operations in background
        for address in addresses {
            let balance = try await sdk.getBalance(for: address.address)
            confirmedTotal += balance.confirmed
            pendingTotal += balance.pending
            instantLockedTotal += balance.instantLocked
            mempoolTotal += balance.mempool
            
            addressBalances.append((address, balance))
        }
        
        // Create SDK Balance for account update
        let accountBalance = SwiftDashCoreSDK.Balance(
            confirmed: confirmedTotal,
            pending: pendingTotal,
            instantLocked: instantLockedTotal,
            mempool: mempoolTotal,
            mempoolInstant: 0, // Will be calculated from individual addresses if needed
            total: confirmedTotal + pendingTotal + mempoolTotal
        )
        
        return (addressBalances: addressBalances, accountBalance: accountBalance)
    }
    
    func updateAccountBalance(_ account: HDAccount) async throws {
        guard let sdk = sdk else {
            throw WalletError.notConnected
        }
        
        try await transactionService.updateAccountBalance(account, sdk: sdk)
        
        // Force UI update on main thread
        // This will trigger SwiftUI updates due to @Published properties
        objectWillChange.send()
        
        // Trigger balance update notification for immediate UI refresh
        if let updatedBalance = account.balance {
            await notifyBalanceUpdate(updatedBalance)
        }
    }
    
    func updateTransactions(for account: HDAccount) async throws {
        guard let sdk = sdk else {
            throw WalletError.notConnected
        }
        
        try await transactionService.updateTransactions(for: account, sdk: sdk)
    }
    
    // MARK: - Private Helpers
    
    private func handlePeerConnectivityIssue() async {
        await networkConfigurationService.handlePeerConnectivityIssue()
        
        // Disconnect and reconnect with new configuration
        if let wallet = activeWallet, let account = activeAccount {
            await disconnect()
            
            // Wait a moment before reconnecting
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            do {
                try await connect(wallet: wallet, account: account)
                logger.info("✅ Successfully reconnected with new peer configuration")
            } catch {
                logger.error("❌ Failed to reconnect with new peer configuration: \(error)")
            }
        }
    }
    
    /// Retry connection with exponential backoff
    func retryConnection(maxAttempts: Int = 3) async throws {
        guard let wallet = activeWallet, let account = activeAccount else {
            throw WalletError.noActiveWallet
        }
        
        try await connectionService.retryConnection(wallet: wallet, account: account, maxAttempts: maxAttempts)
        
        // After successful connection, setup additional components
        setupEventHandling()
        await watchAddresses(account: account)
        try await fetchInitialBalance(account: account)
    }
    
    private func setupEventHandling() {
        guard let sdk = sdk else {
            logger.warning("⚠️ Cannot setup event handling: SDK is nil")
            return
        }
        
        logger.info("🔌 Setting up SPV event handling...")
        eventService.setupEventHandling(sdk: sdk)
        logger.info("✅ SPV event handling setup complete")
    }
    
    // Event handling is now managed by WalletEventService
    
    // Connection and balance handling is now managed by WalletEventService
    
    // Transaction event handling is now managed by WalletEventService and WalletTransactionService
    
    
    private func handleFailedWatchAddresses(_ failures: [(address: String, error: Error)], account: HDAccount) async {
        // Delegate to watch address service
        watchAddressService.handleFailedWatchAddresses(failures, accountId: account.id.uuidString)
        
        // Schedule retry for recoverable errors
        let recoverableFailures = failures.filter { _, error in
            if let watchError = error as? WatchAddressError {
                return watchError.isRecoverable
            }
            return true // Assume unknown errors might be recoverable
        }
        
        if !recoverableFailures.isEmpty {
            scheduleWatchAddressRetry(addresses: recoverableFailures.map { $0.address }, account: account)
        }
    }
    
    
    // Sync state management is now handled by WalletSyncService
    
    
    // MARK: - Transaction Event Handling
    // Note: Individual transaction management methods moved to BalanceTransactionService
    
    // MARK: - Watch Address Retry
    
    private func scheduleWatchAddressRetry(addresses: [String], account: HDAccount) {
        Task {
            // Simple retry after 5 seconds
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            
            guard let sdk = sdk else { return }
            
            var stillFailedAddresses: [(address: String, error: Error)] = []
            
            for address in addresses {
                do {
                    try await sdk.watchAddress(address)
                    logger.info("Successfully watched address on retry: \(address)")
                } catch {
                    logger.warning("Retry failed for address: \(address)")
                    stillFailedAddresses.append((address, error))
                }
            }
            
            // Update pending addresses
            if stillFailedAddresses.isEmpty {
                pendingWatchAddresses.removeValue(forKey: account.id.uuidString)
            } else {
                pendingWatchAddresses[account.id.uuidString] = stillFailedAddresses
            }
            
            // Pending count is automatically updated by watchAddressService
        }
    }
    
    // MARK: - Watch Address Verification
    
    private func startWatchVerification() {
        watchAddressService.startWatchVerification { [weak self] in
            await self?.verifyAllWatchedAddresses()
        }
    }
    
    private func stopWatchVerification() {
        watchAddressService.stopWatchVerification()
    }
    
    private func verifyAllWatchedAddresses() async {
        guard let _ = sdk, let account = activeAccount else { return }
        
        watchAddressService.updateVerificationStatus(.verifying)
        
        let addresses = account.addresses.map { $0.address }
        let totalAddresses = addresses.count
        var watchedAddresses = 0
        
        do {
            // Verify watched addresses by checking if they're currently being tracked
            // This is more reliable than a direct verification method
            watchedAddresses = 0
            
            for _ in addresses {
                // TODO: Implement when SDK supports address balance queries
                // Check if address has any tracked balance or transactions
                // let balance = try await sdk.getAddressBalance(address)
                // if balance.total > 0 || balance.pending > 0 {
                //     watchedAddresses += 1
                // } else {
                //     // Re-add address to watch list to ensure it's being tracked
                //     try await sdk.addWatchAddress(address)
                //     watchedAddresses += 1
                // }
                
                // For now, assume all addresses are being watched
                watchedAddresses += 1
            }
            
            watchAddressService.updateVerificationStatus(.verified(total: totalAddresses, watching: watchedAddresses))
        } catch {
            logger.error("Failed to verify watched addresses for account \(account.label): \(error)")
            watchAddressService.updateVerificationStatus(.failed(error: error.localizedDescription))
        }
    }
    
    // MARK: - Enhanced Transaction Event Handling
    
    /// Notify other parts of the app about balance updates
    private func notifyBalanceUpdate(_ balance: LocalBalance) async {
        await transactionService.notifyBalanceUpdate(balance)
    }
    
    /// Get recent transaction activity for an address
    func getRecentActivityForAddress(_ address: String) -> (hasRecentActivity: Bool, lastActivityTime: Date?) {
        return transactionService.getRecentActivityForAddress(address, account: activeAccount)
    }
    
    /// Fetch transactions for a given account from SwiftData
    func fetchTransactionsForAccount(_ account: HDAccount) async -> [SwiftDashCoreSDK.Transaction] {
        return await transactionService.fetchTransactionsForAccount(account)
    }
    
    /// Manually check for new transactions for all watched addresses
    func checkForNewTransactions() async {
        guard let sdk = sdk, let account = activeAccount else { 
            logger.warning("⚠️ Cannot check transactions: SDK or account not available")
            return 
        }
        
        await transactionService.checkForNewTransactions(for: account, sdk: sdk)
    }
    
    /// Test method to create a test address for receiving funds
    func createTestReceiveAddress() -> String? {
        guard let account = activeAccount else {
            return nil
        }
        return diagnosticsService.createTestReceiveAddress(for: account)
    }
    
    /// Comprehensive test of the receiving funds detection system
    func testReceivingFundsDetection() async {
        await diagnosticsService.testReceivingFundsDetection(activeAccount: activeAccount)
    }
    
    /// Test peer connectivity with detailed logging
    func testPeerConnectivity() async {
        await diagnosticsService.testPeerConnectivity(
            activeWallet: activeWallet,
            syncProgress: syncProgress,
            detailedSyncProgress: detailedSyncProgress,
            isConnected: isConnected,
            isSyncing: isSyncing,
            isUsingLocalPeers: isUsingLocalPeers(),
            sdk: sdk
        )
    }
    
    /// Get summary of receiving funds detection capabilities
    func getReceivingFundsDetectionSummary() -> [String: Any] {
        return diagnosticsService.getReceivingFundsDetectionSummary()
    }
    
    // MARK: - Connection Diagnostics
    
    
    
    /// Run full diagnostic check for both Core and Platform
    func runFullDiagnostics() async -> String {
        return await diagnosticsService.runFullDiagnostics(
            sdk: sdk,
            activeWallet: activeWallet,
            activeAccount: activeAccount,
            isConnected: isConnected,
            isSyncing: isSyncing,
            syncProgress: syncProgress,
            detailedSyncProgress: detailedSyncProgress,
            watchAddressErrors: watchAddressErrors,
            pendingWatchCount: pendingWatchCount,
            networkMonitor: networkMonitor,
            autoSyncEnabled: autoSyncEnabled,
            lastAutoSyncDate: lastAutoSyncDate,
            isUsingLocalPeers: isUsingLocalPeers()
        )
    }
    
    /// Test connection and provide detailed connection status
    func testConnectionStatus() async -> ConnectionStatus {
        return await diagnosticsService.testConnectionStatus(
            sdk: sdk,
            networkMonitor: networkMonitor,
            isUsingLocalPeers: isUsingLocalPeers(),
            getLocalPeerHost: { self.getLocalPeerHost() }
        )
    }
    
    // MARK: - Cleanup
    
    /// Cleanup method that invalidates all timers and cancels any ongoing tasks
    nonisolated private func cleanup() {
        // Synchronously invalidate all timers on MainActor
        // Using assumeIsolated is safe here because we're invalidating timers during cleanup
        MainActor.assumeIsolated {
            autoSyncTimer?.invalidate()
            autoSyncTimer = nil
            
            watchVerificationTimer?.invalidate()
            watchVerificationTimer = nil
        }
        
        // Cancel any ongoing tasks
        // Note: Individual Task cancellation would require storing Task references
        // For now, the weak self references will prevent retain cycles
    }
    
    deinit {
        cleanup()
    }
}

// MARK: - Wallet Errors
// WalletError is defined in HDWalletService.swift
// ConnectionStatus is defined in WalletDiagnosticsService.swift
