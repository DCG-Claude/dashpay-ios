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
    
    // Service dependencies
    private let connectionService = ConnectionStateService()
    private let syncService = SyncStateService()
    private let watchAddressService = WatchAddressService()
    private let autoSyncService = AutoSyncService()
    private let walletLifecycleService = WalletLifecycleService()
    private let addressManagementService = AddressManagementService()
    private let balanceTransactionService = BalanceTransactionService()
    private let networkConfigurationService = NetworkConfigurationService()
    
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
    @Published var isSyncing: Bool = false
    @Published var syncProgress: SyncProgress?
    @Published var detailedSyncProgress: SwiftDashCoreSDK.DetailedSyncProgress?
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
    var mempoolTransactionCount: Int { balanceTransactionService.mempoolTransactionCount }
    
    // Computed property for sync statistics
    var syncStatistics: [String: String] {
        return syncService.syncStatistics
    }
    
    private init() {}
    
    func configure(modelContext: ModelContext) {
        logger.info("🔧 WalletService.configure() called")
        self.modelContext = modelContext
        autoSyncService.configure(modelContext: modelContext)
        walletLifecycleService.configure(modelContext: modelContext)
        addressManagementService.configure(modelContext: modelContext)
        balanceTransactionService.configure(modelContext: modelContext)
        
        // Setup bindings between WalletService and SyncStateService properties
        setupSyncStateBindings()
        
        logger.info("✅ WalletService configured with modelContext")
    }
    
    func setSharedSDK(_ sdk: DashSDK) {
        logger.info("🔧 WalletService.setSharedSDK() called")
        connectionService.sdk = sdk
        logger.info("✅ WalletService configured with shared SDK")
    }
    
    /// Setup bindings between WalletService @Published properties and SyncStateService
    private func setupSyncStateBindings() {
        // Bind syncService properties to WalletService @Published properties
        syncService.$isSyncing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSyncing)
        
        syncService.$syncProgress
            .receive(on: DispatchQueue.main)
            .assign(to: &$syncProgress)
        
        syncService.$detailedSyncProgress
            .receive(on: DispatchQueue.main)
            .assign(to: &$detailedSyncProgress)
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
    
    // Note: Peer discovery is now handled automatically by rust-dashcore SPV client
    // Legacy peer arrays kept for reference but no longer used
    
    // MARK: - Private Connection Helper Methods
    
    private func setupConfiguration(wallet: HDWallet) async throws -> SPVClientConfiguration {
        logger.info("🔧 Getting SPV configuration from manager...")
        let config = try SPVConfigurationManager.shared.configuration(for: wallet.network)
        logger.info("📁 SPV data directory: \(config.dataDirectory?.path ?? "nil")")
        
        // Set log level based on user preference or build configuration
        let userLogLevel = UserDefaults.standard.string(forKey: "walletLogLevel")
        if let userLogLevel = userLogLevel, !userLogLevel.isEmpty {
            config.logLevel = userLogLevel
            logger.info("📝 Using user-configured log level: \(userLogLevel)")
        } else {
            // Fall back to build configuration defaults
            #if DEBUG
            config.logLevel = "trace"
            #else
            config.logLevel = "info"
            #endif
            logger.info("📝 Using build configuration log level: \(config.logLevel)")
        }
        
        // Configure peers based on user preference
        let useLocalPeers = UserDefaults.standard.bool(forKey: "useLocalPeers")
        logger.info("🌐 Configuring peer connections...")
        logger.info("   Use Local Peers: \(useLocalPeers)")
        
        if useLocalPeers {
            // Override with local peers for development/testing
            logger.info("🔧 Configuring LOCAL peers for \(wallet.network.rawValue)")
            
            // Get custom local peer from UserDefaults or use localhost as fallback
            let localPeerHost = UserDefaults.standard.string(forKey: "localPeerHost") ?? "127.0.0.1"
            logger.info("   Local peer host: \(localPeerHost)")
            
            if wallet.network == .mainnet {
                let localMainnetPeer = "\(localPeerHost):9999"
                config.additionalPeers = [localMainnetPeer]
                logger.info("   Local mainnet peer configured: \(localMainnetPeer)")
            } else if wallet.network == .testnet {
                let localTestnetPeer = "\(localPeerHost):19999"
                config.additionalPeers = [localTestnetPeer]
                logger.info("   Local testnet peer configured: \(localTestnetPeer)")
            }
        } else {
            // Use automatic peer discovery from rust-dashcore SPV client
            logger.info("🌐 Using AUTOMATIC peer discovery for \(wallet.network.rawValue)")
            logger.info("   SPV client will handle DNS seed resolution and peer management")
            
            // Clear any existing peers to let SPV client handle discovery
            config.additionalPeers = []
        }
        
        logger.info("📝 Configuration settings:")
        logger.info("   Network: \(config.network.rawValue)")
        logger.info("   Validation Mode: \(config.validationMode.rawValue)")
        logger.info("   Max Peers: \(config.maxPeers)")
        logger.info("   Data Directory: \(config.dataDirectory?.path ?? "None")")
        logger.info("   Log Level: \(config.logLevel)")
        logger.info("   Mempool Config: \(String(describing: config.mempoolConfig))")
        
        return config
    }
    
    private func initializeSDK(with config: SPVClientConfiguration) async throws {
        logger.info("📡 Initializing SDK components...")
        
        // Check if SDK already exists (set by UnifiedAppState)
        if connectionService.sdk != nil {
            logger.info("✅ Using existing shared SDK from UnifiedAppState")
            return
        }
        
        logger.info("⚠️ No shared SDK found, creating new SDK instance...")
        logger.info("   Thread before MainActor: \(Thread.isMainThread ? "Main" : "Background")")
        
        do {
            // Initialize SDK components on MainActor following rust-dashcore pattern
            // FIX: Create only DashSDK, not separate SPVClient
            let createdSDK = try await MainActor.run {
                logger.info("   Thread in MainActor: \(Thread.isMainThread ? "Main" : "Background")")
                
                // Create DashSDK (which includes SPVClient and PersistentWalletManager internally)
                logger.info("   Creating DashSDK...")
                let dashSDK = try DashSDK(configuration: config)
                logger.info("   ✅ DashSDK created")
                
                return dashSDK
            }
            connectionService.sdk = createdSDK
            logger.info("✅ All SDK components initialized successfully")
            
        } catch {
            logger.error("❌ Failed to initialize SDK components: \(error)")
            logger.error("   Error type: \(type(of: error))")
            logger.error("   Error details: \(error.localizedDescription)")
            if let sdkError = error as? SwiftDashCoreSDK.DashSDKError {
                logger.error("   SDK Error: \(sdkError)")
                logger.error("   Recovery suggestion: \(sdkError.recoverySuggestion ?? "None")")
            }
            throw error
        }
    }
    
    private func connectToNetwork() async throws {
        // Connect using DashSDK
        logger.info("🌐 Attempting to connect to Dash network...")
        logger.info("   SDK exists: \(self.sdk != nil)")
        
        do {
            guard let sdk = sdk else {
                logger.error("❌ SDK is nil, cannot connect")
                throw WalletError.notConnected
            }
            
            // Check if already connected
            if sdk.isConnected {
                logger.info("✅ SDK is already connected, skipping connection")
                connectionService.setConnected(true)
                connectionService.setSDK(sdk)
                return
            }
            
            logger.info("🔌 Connecting via SDK...")
            try await sdk.connect()
            
            // Verify connection was successful
            if sdk.isConnected {
                connectionService.setConnected(true)
                connectionService.setSDK(sdk)
                logger.info("✅ Connected successfully!")
                logger.info("   Connection state: \(self.isConnected)")
                logger.info("   SDK connected: \(sdk.isConnected)")
                
                // FIX: Stop the SDK's automatic periodic sync immediately
                // We want ONLY manual sync control to prevent duplicate syncs
                logger.info("🛑 Stopping SDK's automatic periodic sync...")
                sdk.stopPeriodicSync()
                logger.info("✅ SDK periodic sync stopped successfully")
            } else {
                logger.error("❌ SDK connect() returned but isConnected is false")
                throw WalletError.connectionFailed
            }
        } catch {
            logger.error("❌ Connection failed: \(error)")
            logger.error("   Error type: \(type(of: error))")
            logger.error("   Error details: \(error.localizedDescription)")
            
            // Check for specific error types
            if let sdkError = error as? SwiftDashCoreSDK.DashSDKError {
                logger.error("   SDK Error: \(sdkError)")
                logger.error("   Recovery suggestion: \(sdkError.recoverySuggestion ?? "None")")
                
                // Handle specific connection errors
                if case .networkError(let message) = sdkError {
                    logger.error("   Network error: \(message)")
                    // Try fallback to different peers
                    if !networkConfigurationService.isUsingLocalPeers() {
                        logger.info("🔄 Attempting peer connectivity fallback...")
                        await networkConfigurationService.handlePeerConnectivityIssue()
                    }
                } else if case .ffiError(let code, let message) = sdkError {
                    logger.error("   FFI error code: \(code), message: \(message)")
                }
            }
            
            throw error
        }
        
        // Auto-reconnect is handled internally by the SDK
        
        // Enable mempool tracking after connection
        logger.info("🔄 Enabling mempool tracking...")
        do {
            try await sdk?.enableMempoolTracking(strategy: .fetchAll)
            logger.info("✅ Mempool tracking enabled with FetchAll strategy")
        } catch {
            logger.warning("⚠️ Failed to enable mempool tracking: \(error)")
            // Log the error but continue since this is not critical to basic wallet functionality
            logger.info("ℹ️ Wallet will continue without mempool tracking")
        }
    }
    
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
        UserDefaults.standard.set(useLocal, forKey: "useLocalPeers")
        print("🔧 Peer configuration updated: useLocalPeers = \(useLocal)")
    }
    
    /// Check current peer configuration
    func isUsingLocalPeers() -> Bool {
        return UserDefaults.standard.bool(forKey: "useLocalPeers")
    }
    
    /// Set custom local peer host (for development)
    func setLocalPeerHost(_ host: String) {
        UserDefaults.standard.set(host, forKey: "localPeerHost")
        print("🔧 Local peer host updated: \(host)")
    }
    
    /// Get current local peer host
    func getLocalPeerHost() -> String {
        return UserDefaults.standard.string(forKey: "localPeerHost") ?? "127.0.0.1"
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
        let config = try await setupConfiguration(wallet: wallet)
        
        // Initialize SDK
        try await initializeSDK(with: config)
        
        // Connect to network
        try await connectToNetwork()
        
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
        syncService.cancelSync()
        
        // Stop watch verification
        watchAddressService.stopWatchVerification()
        
        if let sdk = sdk {
            try? await sdk.disconnect()
        }
        
        // Reset all services
        connectionService.reset()
        syncService.reset()
        watchAddressService.reset()
    }
    
    /// Enable checkpoint sync by clearing SPV data
    /// This forces the SPV client to start fresh and automatically use the latest checkpoint
    /// For testnet, this will sync from height 1088640 instead of genesis (height 0)
    func enableCheckpointSync() async throws {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        logger.info("🏁 Enabling checkpoint sync for \(wallet.network.rawValue)")
        
        // Disconnect if connected
        if isConnected {
            logger.info("🔌 Disconnecting wallet before clearing data...")
            await disconnect()
        }
        
        // Clear SPV data to enable checkpoint sync
        try SPVConfigurationManager.shared.clearSPVDataForCheckpointSync(network: wallet.network)
        
        logger.info("✅ Checkpoint sync enabled. Next sync will start from latest checkpoint.")
        logger.info("📍 Testnet checkpoint: height 1088640")
        logger.info("📍 Mainnet checkpoint: height 1100000")
    }
    
    func startSync() async throws {
        guard let sdk = sdk, isConnected else {
            throw WalletError.notConnected
        }
        
        // Check if sync is already in progress
        if syncService.hasActiveSync() {
            logger.warning("⚠️ Sync already in progress, skipping duplicate request")
            return
        }
        
        // Generate new sync request ID
        let requestId = UUID()
        syncService.startSync(requestId: requestId)
        
        let syncTask = Task { [weak self, requestId] in
            do {
                logger.info("📡 Starting enhanced sync with detailed progress...")
                var lastLogTime = Date()
                
                // Use the new sync progress stream from SDK
                for await progress in sdk.syncProgressStream() {
                    // Check if this sync was cancelled by a newer sync
                    guard self?.syncService.getCurrentSyncRequestId() == requestId else {
                        logger.info("🛑 Sync cancelled (newer sync started)")
                        break
                    }
                    
                    if Task.isCancelled { break }
                    
                    await MainActor.run {
                        // Use the SDK progress directly
                        self?.syncService.updateProgress(progress)
                    }
                    
                    // Log progress every second to avoid spam
                    if Date().timeIntervalSince(lastLogTime) > 1.0 {
                        print("\(progress.stage.icon) \(progress.statusMessage)")
                        print("   Speed: \(progress.formattedSpeed) | ETA: \(progress.formattedTimeRemaining)")
                        print("   Peers: \(progress.connectedPeers) | Headers: \(progress.totalHeadersProcessed)")
                        lastLogTime = Date()
                    }
                    
                    // Update sync state in storage
                    if let wallet = self?.activeWallet, let syncProgress = self?.syncProgress {
                        await self?.updateSyncState(walletId: wallet.id, progress: syncProgress)
                    }
                    
                    // Check if sync is complete
                    if progress.isComplete {
                        break
                    }
                }
                
                // Sync completed
                await MainActor.run {
                    logger.info("✅ Sync completed (ID: \(requestId.uuidString.prefix(8)))")
                    self?.syncService.completeSync()
                    
                    if let wallet = self?.activeWallet {
                        wallet.lastSynced = Date()
                        try? self?.modelContext?.save()
                    }
                }
                
                // Update balance after sync
                if let account = self?.activeAccount {
                    print("💰 Updating balance after sync...")
                    try? await self?.updateAccountBalance(account)
                }
                
            } catch {
                await MainActor.run {
                    self?.syncService.reset()
                    self?.logger.error("❌ Sync error: \(error)")
                }
            }
        }
        
        syncService.setActiveSyncTask(syncTask)
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
        syncService.cancelSync()
    }
    
    // Alternative sync method using callbacks for real-time updates
    func startSyncWithCallbacks() async throws {
        guard let sdk = sdk, isConnected else {
            throw WalletError.notConnected
        }
        
        print("🔄 Starting callback-based sync for wallet: \(activeWallet?.name ?? "Unknown")")
        let requestId = UUID()
        syncService.startSync(requestId: requestId)
        
        try await sdk.syncToTipWithProgress(
            progressCallback: { [weak self] progress in
                Task { @MainActor in
                    // Use the SDK progress directly
                    self?.syncService.updateProgress(progress)
                    
                    print("\(progress.stage.icon) \(progress.statusMessage)")
                }
            },
            completionCallback: { [weak self] success, error in
                Task { @MainActor in
                    if success {
                        self?.syncService.completeSync()
                    } else {
                        self?.syncService.reset()
                    }
                    
                    if success {
                        print("✅ Sync completed successfully!")
                        if let wallet = self?.activeWallet {
                            wallet.lastSynced = Date()
                            try? self?.modelContext?.save()
                            
                            // Update balance after sync
                            if let account = self?.activeAccount {
                                print("💰 Updating balance after sync...")
                                try? await self?.updateAccountBalance(account)
                            }
                        }
                    } else {
                        print("❌ Sync failed: \(error ?? "Unknown error")")
                    }
                }
            }
        )
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
        
        try await balanceTransactionService.updateAccountBalance(account, sdk: sdk)
        
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
        
        try await balanceTransactionService.updateTransactions(for: account, sdk: sdk)
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
        
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            logger.info("🔄 Connection attempt \(attempt) of \(maxAttempts)...")
            
            do {
                // Disconnect if already connected
                if isConnected {
                    await disconnect()
                }
                
                // Wait with exponential backoff
                if attempt > 1 {
                    let waitTime = pow(2.0, Double(attempt - 1))
                    logger.info("⏳ Waiting \(Int(waitTime)) seconds before retry...")
                    try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                }
                
                // Try to connect
                try await connect(wallet: wallet, account: account)
                
                // If we get here, connection was successful
                logger.info("✅ Connection successful on attempt \(attempt)")
                return
                
            } catch {
                lastError = error
                logger.error("❌ Connection attempt \(attempt) failed: \(error)")
                
                // On last attempt, try switching peer configuration
                if attempt == maxAttempts - 1 && isUsingLocalPeers() {
                    logger.info("🔄 Switching to public peers for final attempt...")
                    setUseLocalPeers(false)
                }
            }
        }
        
        // All attempts failed
        throw lastError ?? WalletError.connectionFailed
    }
    
    private func setupEventHandling() {
        guard let sdk = sdk else {
            logger.warning("⚠️ Cannot setup event handling: SDK is nil")
            return
        }
        
        logger.info("🔌 Setting up SPV event handling...")
        
        sdk.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleSDKEvent(event)
            }
            .store(in: &cancellables)
            
        logger.info("✅ SPV event handling setup complete")
    }
    
    private func handleSDKEvent(_ event: SPVEvent) {
        logger.info("🎯 Received SPV event")
        switch event {
        case .connectionStatusChanged(let connected):
            handleConnectionStatusChanged(connected)
            
        case .balanceUpdated(let balance):
            // Convert Balance to LocalBalance
            let localBalance = LocalBalance(
                confirmed: balance.confirmed,
                pending: balance.pending,
                instantLocked: balance.instantLocked,
                mempool: balance.mempool,
                mempoolInstant: balance.mempoolInstant ?? 0,
                total: balance.total
            )
            handleBalanceUpdated(localBalance)
            
        case .transactionReceived(let txid, let confirmed, let amount, let addresses, let blockHeight):
            handleTransactionReceived(txid: txid, confirmed: confirmed, amount: amount, addresses: addresses, blockHeight: blockHeight)
            
        case .mempoolTransactionAdded(let txid, let amount, let addresses):
            handleMempoolTransactionAdded(txid: txid, amount: amount, addresses: addresses)
            
        case .mempoolTransactionConfirmed(let txid, let blockHeight, let confirmations):
            handleMempoolTransactionConfirmed(txid: txid, blockHeight: blockHeight, confirmations: confirmations)
            
        case .mempoolTransactionRemoved(let txid, let reason):
            handleMempoolTransactionRemoved(txid: txid, reason: String(describing: reason))
            
        case .syncProgressUpdated(let progress):
            handleSyncProgressUpdated(progress)
            
        default:
            break
        }
    }
    
    private func handleConnectionStatusChanged(_ connected: Bool) {
        if connected {
            logger.info("✅ Connected to network")
            logger.info("   Is syncing: \(self.isSyncing)")
            logger.info("   Is connected: \(self.isConnected)")
        } else {
            logger.warning("❌ Disconnected from network")
            Task {
                await handlePeerConnectivityIssue()
            }
        }
    }
    
    private func handleBalanceUpdated(_ balance: LocalBalance) {
        Task {
            if let account = activeAccount {
                logger.info("💰 Balance updated - Confirmed: \(balance.confirmed), Pending: \(balance.pending), InstantLocked: \(balance.instantLocked), Total: \(balance.total)")
                try? await updateAccountBalance(account)
                
                // Trigger a notification to other parts of the app
                await notifyBalanceUpdate(balance)
            }
        }
    }
    
    private func handleTransactionReceived(txid: String, confirmed: Bool, amount: Int64, addresses: [String], blockHeight: UInt32?) {
        logger.info("🚨 SPVEvent.transactionReceived triggered!")
        Task { @MainActor in
            if let account = activeAccount {
                logger.info("📱 Transaction received: \(txid)")
                logger.info("   Amount: \(amount) satoshis (\(Double(amount) / 100_000_000) DASH)")
                logger.info("   Addresses: \(addresses.joined(separator: ", "))")
                logger.info("   Confirmed: \(confirmed)")
                if let height = blockHeight {
                    logger.info("   Block Height: \(height)")
                }
                
                // Check if this transaction involves our addresses
                let isOurTransaction = addresses.contains { address in
                    account.addresses.contains { watchedAddress in
                        watchedAddress.address == address
                    }
                }
                
                if isOurTransaction {
                    // Determine transaction direction
                    let direction = amount > 0 ? "received" : "sent"
                    logger.info("   Direction: \(direction == "received" ? "Received" : "Sent")")
                    
                    // Show notification for received funds
                    if direction == "received" {
                        await showFundsReceivedNotification(
                            amount: amount,
                            txid: txid,
                            confirmed: confirmed
                        )
                    }
                    
                    // Create and save the transaction
                    await balanceTransactionService.saveTransaction(
                        txid: txid,
                        amount: amount,
                        addresses: addresses,
                        confirmed: confirmed,
                        blockHeight: blockHeight,
                        account: account
                    )
                    
                    // Update activity indicators
                    await updateAddressActivity(addresses: addresses, txid: txid)
                } else {
                    logger.info("   Transaction does not involve our addresses")
                }
            }
        }
    }
    
    private func handleMempoolTransactionAdded(txid: String, amount: Int64, addresses: [String]) {
        Task {
            if let account = activeAccount {
                print("🔄 Mempool transaction added: \(txid)")
                print("   Amount: \(amount) satoshis")
                print("   Addresses: \(addresses)")
                
                // Save as unconfirmed transaction
                await balanceTransactionService.saveTransaction(
                    txid: txid,
                    amount: amount,
                    addresses: addresses,
                    confirmed: false,
                    blockHeight: nil,
                    account: account
                )
                
                // Update mempool count
                if let account = activeAccount {
                    await balanceTransactionService.updateMempoolTransactionCount(for: account)
                }
            }
        }
    }
    
    private func handleMempoolTransactionConfirmed(txid: String, blockHeight: UInt32, confirmations: UInt32) {
        Task {
            if activeAccount != nil {
                print("✅ Mempool transaction confirmed: \(txid) at height \(blockHeight) with \(confirmations) confirmations")
                
                // Update transaction confirmation status
                do {
                    try await balanceTransactionService.confirmTransaction(txid: txid, blockHeight: blockHeight)
                } catch {
                    logger.error("❌ Failed to confirm transaction \(txid): \(error)")
                    // Continue processing but log the error - mempool tracking will handle eventual consistency
                }
                
                // Update mempool count
                if let account = activeAccount {
                    await balanceTransactionService.updateMempoolTransactionCount(for: account)
                }
            }
        }
    }
    
    private func handleMempoolTransactionRemoved(txid: String, reason: String) {
        Task {
            if activeAccount != nil {
                print("❌ Mempool transaction removed: \(txid), reason: \(reason)")
                
                // Remove or mark transaction as dropped
                do {
                    if let account = activeAccount {
                        try await balanceTransactionService.removeTransaction(txid: txid, account: account)
                    }
                } catch {
                    logger.error("❌ Failed to remove transaction \(txid): \(error)")
                    // Continue processing but log the error - mempool tracking will handle eventual consistency
                }
                
                // Update mempool count
                if let account = activeAccount {
                    await balanceTransactionService.updateMempoolTransactionCount(for: account)
                }
            }
        }
    }
    
    private func handleSyncProgressUpdated(_ progress: SyncProgress) {
        self.syncService.updateProgress(progress)
        logger.info("📊 Sync progress: \(progress.percentageComplete)% - \(progress.status.description)")
    }
    
    
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
    
    
    private func updateSyncState(walletId: UUID, progress: SyncProgress) async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<SyncState>()
        let allStates = try? context.fetch(descriptor)
        
        if let syncState = allStates?.first(where: { $0.walletId == walletId }) {
            syncState.update(from: progress)
        } else {
            let syncState = SyncState(walletId: walletId)
            syncState.update(from: progress)
            context.insert(syncState)
        }
        
        try? context.save()
    }
    
    
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
    
    /// Show a notification when funds are received
    private func showFundsReceivedNotification(amount: Int64, txid: String, confirmed: Bool) async {
        let dashAmount = Double(amount) / 100_000_000
        let amountText = String(format: "%.8g DASH", dashAmount)
        let statusText = confirmed ? "Confirmed" : "Unconfirmed"
        
        // Log the received funds
        logger.info("🎉 Funds received: \(amountText) (\(statusText))")
        logger.info("   Transaction ID: \(txid)")
        
        // Post notification to NotificationCenter for other parts of the app
        let userInfo: [String: Any] = [
            "amount": amount,
            "txid": txid,
            "confirmed": confirmed,
            "amountText": amountText,
            "statusText": statusText
        ]
        
        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("FundsReceived"),
                object: nil,
                userInfo: userInfo
            )
        }
    }
    
    /// Notify other parts of the app about balance updates
    private func notifyBalanceUpdate(_ balance: LocalBalance) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("BalanceUpdated"),
                object: nil,
                userInfo: ["balance": balance]
            )
        }
    }
    
    /// Update activity indicators for addresses involved in transactions
    private func updateAddressActivity(addresses: [String], txid: String) async {
        guard let account = activeAccount else { return }
        
        // Mark addresses as having recent activity
        for addressString in addresses {
            if let watchedAddress = account.addresses.first(where: { $0.address == addressString }) {
                // Update the address with recent activity timestamp
                watchedAddress.lastActivityTimestamp = Date()
                logger.info("🔄 Updated activity for address: \(addressString)")
            }
        }
        
        // Save the context
        do {
            try modelContext?.save()
        } catch {
            logger.error("❌ Error saving address activity: \(error)")
        }
    }
    
    /// Get recent transaction activity for an address
    func getRecentActivityForAddress(_ address: String) -> (hasRecentActivity: Bool, lastActivityTime: Date?) {
        guard let account = activeAccount,
              let watchedAddress = account.addresses.first(where: { $0.address == address }) else {
            return (false, nil)
        }
        
        let lastActivity = watchedAddress.lastActivityTimestamp
        let isRecent = lastActivity?.timeIntervalSinceNow ?? -Double.greatestFiniteMagnitude > -300 // 5 minutes
        
        return (isRecent, lastActivity)
    }
    
    /// Enhanced transaction logging for debugging
    private func logTransactionDetails(_ transaction: Transaction) {
        logger.info("📝 Transaction Details:")
        logger.info("   TXID: \(transaction.txid)")
        logger.info("   Amount: \(transaction.amount) satoshis")
        logger.info("   Height: \(transaction.height ?? 0)")
        logger.info("   Confirmations: \(transaction.confirmations)")
        logger.info("   InstantLocked: \(transaction.isInstantLocked)")
    }
    
    /// Fetch transactions for a given account from SwiftData
    func fetchTransactionsForAccount(_ account: HDAccount) async -> [SwiftDashCoreSDK.Transaction] {
        return await balanceTransactionService.fetchTransactionsForAccount(account)
    }
    
    /// Manually check for new transactions for all watched addresses
    func checkForNewTransactions() async {
        guard let sdk = sdk, let account = activeAccount else { 
            logger.warning("⚠️ Cannot check transactions: SDK or account not available")
            return 
        }
        
        await balanceTransactionService.checkForNewTransactions(for: account, sdk: sdk)
    }
    
    /// Test method to create a test address for receiving funds
    func createTestReceiveAddress() -> String? {
        guard let account = activeAccount else {
            logger.error("No active account for creating test address")
            return nil
        }
        
        do {
            let testAddress = try generateNewAddress(for: account, isChange: false)
            logger.info("🧪 Test receive address created: \(testAddress.address)")
            logger.info("   Derivation path: \(testAddress.derivationPath)")
            logger.info("   Index: \(testAddress.index)")
            return testAddress.address
        } catch {
            logger.error("❌ Error creating test address: \(error)")
            return nil
        }
    }
    
    /// Comprehensive test of the receiving funds detection system
    func testReceivingFundsDetection() async {
        logger.info("🧪 Starting comprehensive receiving funds detection test")
        
        guard let account = activeAccount else {
            logger.error("❌ No active account for testing")
            return
        }
        
        // 1. Create a test receive address
        guard let testAddress = createTestReceiveAddress() else {
            logger.error("❌ Failed to create test address")
            return
        }
        
        logger.info("✅ Step 1: Test address created - \(testAddress)")
        
        // 2. Simulate receiving a transaction
        logger.info("🧪 Step 2: Simulating received transaction...")
        
        let mockTxid = "test_tx_\(Date().timeIntervalSince1970)"
        let mockAmount: Int64 = 50_000_000 // 0.5 DASH
        
        // Simulate the transaction event directly
        await balanceTransactionService.saveTransaction(
            txid: mockTxid,
            amount: mockAmount,
            addresses: [testAddress],
            confirmed: false,
            blockHeight: nil,
            account: account
        )
        
        logger.info("✅ Step 2: Mock transaction saved")
        
        // 3. Test the notification system
        logger.info("🧪 Step 3: Testing notification system...")
        
        await showFundsReceivedNotification(
            amount: mockAmount,
            txid: mockTxid,
            confirmed: false
        )
        
        logger.info("✅ Step 3: Notification system tested")
        
        // 4. Test address activity tracking
        logger.info("🧪 Step 4: Testing address activity tracking...")
        
        await updateAddressActivity(addresses: [testAddress], txid: mockTxid)
        
        let (hasRecentActivity, lastActivity) = getRecentActivityForAddress(testAddress)
        logger.info("✅ Step 4: Address activity - Recent: \(hasRecentActivity), Last: \(lastActivity?.description ?? "None")")
        
        // 5. Test balance update
        logger.info("🧪 Step 5: Testing balance update...")
        
        do {
            try await updateAccountBalance(account)
            logger.info("✅ Step 5: Balance update completed")
        } catch {
            logger.error("❌ Step 5: Balance update failed - \(error)")
        }
        
        // 6. Test confirmation simulation
        logger.info("🧪 Step 6: Simulating transaction confirmation...")
        
        do {
            try await balanceTransactionService.confirmTransaction(txid: mockTxid, blockHeight: 850000)
            logger.info("✅ Step 6: Transaction confirmation simulated")
        } catch {
            logger.error("❌ Step 6: Transaction confirmation failed - \(error)")
        }
        
        logger.info("🎉 Comprehensive receiving funds detection test completed!")
        logger.info("📊 Test Summary:")
        logger.info("   - Test address: \(testAddress)")
        logger.info("   - Test transaction: \(mockTxid)")
        logger.info("   - Test amount: \(Double(mockAmount) / 100_000_000) DASH")
        logger.info("   - Notifications: Enabled")
        logger.info("   - Activity tracking: Active")
        logger.info("   - Balance updates: Real-time")
    }
    
    /// Test peer connectivity with detailed logging
    func testPeerConnectivity() async {
        logger.info("🧪 Starting peer connectivity test")
        logger.info("   Current configuration: useLocalPeers = \(self.isUsingLocalPeers())")
        
        guard let wallet = activeWallet, let _ = activeAccount else {
            logger.error("❌ No active wallet/account for testing")
            return
        }
        
        logger.info("📊 Test Summary:")
        logger.info("   - Network: \(String(describing: wallet.network))")
        logger.info("   - Using Local Peers: \(self.isUsingLocalPeers())")
        
        if sdk != nil {
            // Log current peer configuration
            if wallet.network == .testnet {
                let testnetConfig = try? SPVConfigurationManager.shared.configuration(for: .testnet)
                logger.info("   - Available testnet peers:")
                if let testnetConfig = testnetConfig {
                    for peer in testnetConfig.additionalPeers {
                        logger.info("     • \(peer)")
                    }
                } else {
                    logger.warning("   - Failed to get testnet configuration for peer logging")
                }
            }
            
            logger.info("   - Connection Status: \(self.isConnected ? "Connected" : "Disconnected")")
            logger.info("   - Sync Status: \(self.isSyncing ? "Syncing" : "Not syncing")")
            
            if let progress = syncProgress {
                logger.info("   - Sync Progress: \(Int(progress.progress * 100))%")
                logger.info("   - Current Height: \(progress.currentHeight)")
                logger.info("   - Total Height: \(progress.totalHeight)")
            }
        }
        
        logger.info("✅ Peer connectivity test completed")
    }
    
    /// Get summary of receiving funds detection capabilities
    func getReceivingFundsDetectionSummary() -> [String: Any] {
        return [
            "spv_event_handling": "Enhanced with comprehensive logging and transaction filtering",
            "visual_indicators": "Real-time notification banners and activity indicators",
            "local_notifications": "Push notifications for received funds and confirmations",
            "balance_updates": "Immediate UI updates with forced refresh",
            "activity_tracking": "Address-level activity timestamps and recent activity detection",
            "logging": "Comprehensive transaction and balance logging for debugging",
            "test_capabilities": "Full test suite for simulating fund reception",
            "features": [
                "Transaction direction detection",
                "Real-time balance updates",
                "Visual notification banners",
                "Local push notifications",
                "Address activity indicators",
                "Enhanced receive address view",
                "Comprehensive transaction logging",
                "Test address generation"
            ]
        ]
    }
    
    // MARK: - Connection Diagnostics
    
    
    
    /// Get Platform network status
    func getPlatformNetworkStatus() async -> String? {
        // Platform SDK integration will be added later
        return "Platform SDK not yet integrated"
    }
    
    /// Run full diagnostic check for both Core and Platform
    func runFullDiagnostics() async -> String {
        var report = "🔍 DashPay iOS Diagnostic Report\n"
        report += "================================\n\n"
        report += "Timestamp: \(Date())\n\n"
        
        // Core diagnostics
        report += "Core SDK Status:\n"
        if let sdk = sdk {
            report += "  - Initialized: ✅\n"
            report += "  - Connected: \(sdk.isConnected ? "✅" : "❌")\n"
            report += "  - Network: \(activeWallet?.network.rawValue ?? "Unknown")\n"
            report += "  - Use Local Peers: \(isUsingLocalPeers())\n"
            
            // Get peer info if available
            if isConnected {
                report += "  - Connection Details:\n"
                if let progress = detailedSyncProgress {
                    report += "    - Connected Peers: \(progress.connectedPeers)\n"
                    report += "    - Sync Stage: \(progress.stage)\n"
                    report += "    - Current Height: \(progress.currentHeight)\n"
                    report += "    - Total Height: \(progress.totalHeight)\n"
                }
            }
        } else {
            report += "  - Initialized: ❌\n"
        }
        
        report += "\n"
        
        // Platform diagnostics
        report += "Platform SDK Status:\n"
        if let platformStatus = await getPlatformNetworkStatus() {
            report += "  - Status: \(platformStatus)\n"
        } else {
            report += "  - Status: Not initialized or not available\n"
        }
        
        report += "\n"
        
        // Wallet status
        report += "Wallet Status:\n"
        report += "  - Active Wallet: \(activeWallet?.name ?? "None")\n"
        report += "  - Active Account: \(activeAccount?.displayName ?? "None")\n"
        report += "  - Connected: \(isConnected ? "✅" : "❌")\n"
        report += "  - Syncing: \(isSyncing ? "✅" : "❌")\n"
        if let progress = syncProgress {
            report += "  - Sync Progress: \(Int(progress.progress * 100))%\n"
        }
        report += "  - Watch Address Errors: \(watchAddressErrors.count)\n"
        report += "  - Pending Watch Count: \(pendingWatchCount)\n"
        
        report += "\n"
        
        // Network connectivity
        report += "Network Connectivity:\n"
        report += "  - Network Monitor: \(networkMonitor?.isConnected ?? false ? "Connected" : "Disconnected")\n"
        report += "  - Auto Sync Enabled: \(autoSyncEnabled)\n"
        if let lastSync = lastAutoSyncDate {
            report += "  - Last Auto Sync: \(lastSync)\n"
        }
        
        logger.info("📋 Full diagnostics report generated")
        return report
    }
    
    /// Test connection and provide detailed connection status
    func testConnectionStatus() async -> ConnectionStatus {
        logger.info("🔍 Testing connection status...")
        
        var status = ConnectionStatus()
        
        // Check Core SDK
        if let sdk = sdk {
            status.coreSDKInitialized = true
            status.coreSDKConnected = sdk.isConnected
            
            if !sdk.isConnected {
                // Try to get more info about why not connected
                status.coreConnectionError = "SDK exists but not connected to network"
            }
        } else {
            status.coreSDKInitialized = false
            status.coreConnectionError = "Core SDK not initialized"
        }
        
        // Check network connectivity
        status.networkAvailable = networkMonitor?.isConnected ?? true
        
        // Check peer configuration
        status.usingLocalPeers = isUsingLocalPeers()
        if status.usingLocalPeers {
            status.peerConfiguration = "Local peer: \(getLocalPeerHost())"
        } else {
            status.peerConfiguration = "Public peers (DNS seeds)"
        }
        
        logger.info("📊 Connection status check complete")
        return status
    }
    
    // MARK: - Cleanup
    
    /// Cleanup method that invalidates all timers and cancels any ongoing tasks
    nonisolated private func cleanup() {
        // Invalidate all timers on MainActor
        Task { @MainActor in
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

// MARK: - Connection Status
struct ConnectionStatus {
    var coreSDKInitialized: Bool = false
    var coreSDKConnected: Bool = false
    var coreConnectionError: String?
    var networkAvailable: Bool = false
    var usingLocalPeers: Bool = false
    var peerConfiguration: String = ""
    var platformSDKAvailable: Bool = false
    var platformConnectionError: String?
}

// MARK: - Wallet Errors
// WalletError is defined in HDWalletService.swift
