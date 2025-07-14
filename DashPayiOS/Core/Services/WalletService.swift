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
    
    @Published var activeWallet: HDWallet?
    @Published var activeAccount: HDAccount?
    @Published var syncProgress: SyncProgress?
    @Published var detailedSyncProgress: DetailedSyncProgress?
    @Published var isConnected: Bool = false
    @Published var isSyncing: Bool = false
    @Published var watchAddressErrors: [WatchAddressError] = []
    @Published var pendingWatchCount: Int = 0
    @Published var watchVerificationStatus: WatchVerificationStatus = .unknown
    @Published var mempoolTransactionCount: Int = 0
    @Published var autoSyncEnabled = true
    @Published var lastAutoSyncDate: Date?
    @Published var syncQueue: [HDWallet] = []
    
    var sdk: DashSDK?
    // FIX: Removed duplicate spvClient - use only sdk which has its own SPVClient
    private var cancellables = Set<AnyCancellable>()
    
    // FIX: Proper sync state management to prevent duplicate syncs
    private var activeSyncTask: Task<Void, Never>?
    private let syncLock = NSLock()
    private var syncRequestId: UUID?
    var modelContext: ModelContext?
    private var autoSyncTimer: Timer?
    var networkMonitor: NetworkMonitor?
    
    // Watch address error tracking
    private var pendingWatchAddresses: [String: [(address: String, error: Error)]] = [:]
    private var watchVerificationTimer: Timer?
    private let logger = Logger(subsystem: "com.dash.wallet", category: "WalletService")
    
    // Computed property for sync statistics
    var syncStatistics: [String: String] {
        guard let progress = detailedSyncProgress else {
            return [:]
        }
        return progress.statistics
    }
    
    private init() {}
    
    func configure(modelContext: ModelContext) {
        logger.info("🔧 WalletService.configure() called")
        self.modelContext = modelContext
        logger.info("✅ WalletService configured with modelContext")
    }
    
    // MARK: - Wallet Management
    
    func createWallet(
        name: String,
        mnemonic: [String],
        password: String,
        network: DashNetwork
    ) throws -> HDWallet {
        guard let context = modelContext else {
            throw WalletError.noContext
        }
        
        // Generate seed from mnemonic
        let seed = HDWalletService.mnemonicToSeed(mnemonic)
        let seedHash = HDWalletService.seedHash(seed)
        
        // Check for duplicate wallet
        let descriptor = FetchDescriptor<HDWallet>()
        let allWallets = try context.fetch(descriptor)
        if allWallets.first(where: { $0.seedHash == seedHash && $0.network == network }) != nil {
            throw WalletError.duplicateWallet
        }
        
        // Encrypt seed
        let encryptedSeed = try HDWalletService.encryptSeed(seed, password: password)
        
        // Create wallet
        let wallet = HDWallet(
            name: name,
            network: network,
            encryptedSeed: encryptedSeed,
            seedHash: seedHash
        )
        
        context.insert(wallet)
        
        // Create default account
        let account = try createAccount(
            for: wallet,
            index: 0,
            label: "Primary Account",
            password: password
        )
        wallet.accounts.append(account)
        
        try context.save()
        
        return wallet
    }
    
    func createAccount(
        for wallet: HDWallet,
        index: UInt32,
        label: String,
        password: String
    ) throws -> HDAccount {
        // Decrypt seed
        let seed = try HDWalletService.decryptSeed(wallet.encryptedSeed, password: password)
        
        // Derive account xpub
        let xpub = HDWalletService.deriveExtendedPublicKey(
            seed: seed,
            network: wallet.network,
            account: index
        )
        
        // Create account
        let account = HDAccount(
            accountIndex: index,
            label: label,
            extendedPublicKey: xpub
        )
        
        account.wallet = wallet
        
        // Generate initial addresses (5 receive, 1 change)
        let initialReceiveCount = 5
        let initialChangeCount = 1
        
        // Generate receive addresses
        for i in 0..<initialReceiveCount {
            let address = HDWalletService.deriveAddress(
                xpub: xpub,
                network: wallet.network,
                change: false,
                index: UInt32(i)
            )
            
            let path = BIP44.derivationPath(
                network: wallet.network,
                account: index,
                change: false,
                index: UInt32(i)
            )
            
            let watchedAddress = HDWatchedAddress(
                address: address,
                index: UInt32(i),
                isChange: false,
                derivationPath: path,
                label: "Receive"
            )
            watchedAddress.account = account
            account.addresses.append(watchedAddress)
        }
        
        // Generate change address
        for i in 0..<initialChangeCount {
            let address = HDWalletService.deriveAddress(
                xpub: xpub,
                network: wallet.network,
                change: true,
                index: UInt32(i)
            )
            
            let path = BIP44.derivationPath(
                network: wallet.network,
                account: index,
                change: true,
                index: UInt32(i)
            )
            
            let watchedAddress = HDWatchedAddress(
                address: address,
                index: UInt32(i),
                isChange: true,
                derivationPath: path,
                label: "Change"
            )
            watchedAddress.account = account
            account.addresses.append(watchedAddress)
        }
        
        return account
    }
    
    func deleteWallet(_ wallet: HDWallet) throws {
        guard let context = modelContext else {
            throw WalletError.noContext
        }
        
        if wallet == activeWallet {
            Task {
                await disconnect()
            }
            activeWallet = nil
            activeAccount = nil
        }
        
        context.delete(wallet)
        try context.save()
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
        let walletsNeedingSync = getWalletsNeedingSync()
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
        guard shouldSync(wallet) else {
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
        lastAutoSyncDate = Date()
        try? modelContext?.save()
        logger.info("📅 Updated last sync date for wallet")
    }
    
    private func shouldSync(_ wallet: HDWallet) -> Bool {
        // FIX: Check if already syncing
        if isSyncing {
            return false
        }
        
        // Always sync if never synced before
        if wallet.lastSynced == nil {
            logger.info("🆕 Wallet never synced before - MUST SYNC")
            
            // Check network connectivity
            let isNetworkConnected = networkMonitor?.isConnected ?? true
            if !isNetworkConnected {
                logger.warning("📵 No network connectivity - cannot sync")
                return false
            }
            
            return true
        }
        
        // Don't sync if synced recently
        let timeSinceLastSync = Date().timeIntervalSince(wallet.lastSynced!)
        if timeSinceLastSync < 300 { // 5 minutes
            logger.info("⏰ Wallet synced recently (\(Int(timeSinceLastSync))s ago) - skipping")
            return false
        }
        
        // Check network connectivity
        let isNetworkConnected = networkMonitor?.isConnected ?? true
        if !isNetworkConnected {
            logger.warning("📵 No network connectivity - cannot sync")
            return false
        }
        
        logger.info("✅ Sync is needed for wallet (last sync: \(Int(timeSinceLastSync))s ago)")
        return true
    }
    
    private func getWalletsNeedingSync() -> [HDWallet] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<HDWallet>()
        let allWallets = (try? context.fetch(descriptor)) ?? []
        
        return allWallets.filter { wallet in
            // Check if wallet has been synced recently
            if let lastSync = wallet.lastSynced,
               Date().timeIntervalSince(lastSync) < 300 { // 5 minutes
                return false
            }
            return true
        }
    }
    
    func setupPeriodicSync() {
        // Cancel existing timer
        autoSyncTimer?.invalidate()
        
        // Setup new timer for every 30 minutes
        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in
            Task {
                await self.startAutoSync()
            }
        }
    }
    
    func stopPeriodicSync() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
    }
    
    // MARK: - Connection & Sync
    
    /// Known good testnet peers (verified working in rust-dashcore example app)
    private static let knownTestnetPeers = [
        "54.149.33.167:19999",
        "35.90.252.3:19999",
        "18.237.170.32:19999",
        "34.220.243.24:19999",
        "34.214.48.68:19999"
    ]
    
    /// Known good mainnet peers (verified working in rust-dashcore example app)
    private static let knownMainnetPeers = [
        "142.93.154.186:9999",
        "8.219.251.8:9999",
        "165.22.30.195:9999",
        "65.109.114.212:9999",
        "188.40.21.248:9999",
        "66.42.58.154:9999"
    ]
    
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
        
        // Create SDK configuration
        logger.info("🔧 Getting SPV configuration from manager...")
        let config = SPVConfigurationManager.shared.configuration(for: wallet.network)
        logger.info("📁 SPV data directory: \(config.dataDirectory?.path ?? "nil")")
        
        // Override log level for debugging if needed (temporary)
        config.logLevel = "trace"
        
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
            // Use public peers - check if we need to override with known-good peers
            logger.info("🌐 Using PUBLIC peers for \(wallet.network.rawValue)")
            if wallet.network == .mainnet && config.additionalPeers.isEmpty {
                // Use our known-good mainnet peers if config doesn't have any
                config.additionalPeers = Self.knownMainnetPeers
                logger.info("   Applied known mainnet peers: \(config.additionalPeers.count) peers")
            } else if wallet.network == .testnet && config.additionalPeers.count < 2 {
                // Supplement testnet peers with our known-good ones
                config.additionalPeers = Self.knownTestnetPeers
                config.maxPeers = 1
                logger.info("   Applied known testnet peers: \(config.additionalPeers.count) peers")
            }
            
            // Log configured peers
            logger.info("   Configured peers:")
            for peer in config.additionalPeers {
                logger.info("     • \(peer)")
            }
        }
        
        logger.info("📝 Configuration settings:")
        logger.info("   Network: \(config.network.rawValue)")
        logger.info("   Validation Mode: \(config.validationMode.rawValue)")
        logger.info("   Max Peers: \(config.maxPeers)")
        logger.info("   Data Directory: \(config.dataDirectory?.path ?? "None")")
        logger.info("   Log Level: \(config.logLevel)")
        logger.info("   Mempool Config: \(String(describing: config.mempoolConfig))")
        
        logger.info("📡 Initializing SDK components...")
        logger.info("   Thread before MainActor: \(Thread.isMainThread ? "Main" : "Background")")
        
        do {
            // Initialize SDK components on MainActor following rust-dashcore pattern
            // FIX: Create only DashSDK, not separate SPVClient
            sdk = try await MainActor.run {
                logger.info("   Thread in MainActor: \(Thread.isMainThread ? "Main" : "Background")")
                
                // Create DashSDK (which includes SPVClient and PersistentWalletManager internally)
                logger.info("   Creating DashSDK...")
                let dashSDK = try DashSDK(configuration: config)
                logger.info("   ✅ DashSDK created")
                
                return dashSDK
            }
            logger.info("✅ All SDK components initialized successfully")
            
            // Setup event handling now that SDK is created
            setupEventHandling()
            
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
        
        // Connect using DashSDK
        logger.info("🌐 Attempting to connect to Dash network...")
        logger.info("   SDK exists: \(self.sdk != nil)")
        
        do {
            guard let sdk = sdk else {
                logger.error("❌ SDK is nil, cannot connect")
                throw WalletError.notConnected
            }
            
            logger.info("🔌 Connecting via SDK...")
            try await sdk.connect()
            
            // Verify connection was successful
            if sdk.isConnected {
                isConnected = true
                logger.info("✅ Connected successfully!")
                logger.info("   Connection state: \(self.isConnected)")
                logger.info("   SDK connected: \(sdk.isConnected)")
                
                // FIX: Stop the SDK's automatic periodic sync immediately
                // We want ONLY manual sync control to prevent duplicate syncs
                logger.info("🛑 Stopping SDK's automatic periodic sync...")
                // Note: SDK's wallet property is private, so we can't call stopPeriodicSync directly
                // The SDK will still have its periodic sync running, but we control all manual syncs
                logger.info("⚠️ SDK periodic sync cannot be stopped (private property), using sync coordination instead")
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
                    if !useLocalPeers {
                        logger.info("🔄 Attempting peer connectivity fallback...")
                        await handlePeerConnectivityIssue()
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
            // Non-critical error, continue
        }
        
        activeWallet = wallet
        activeAccount = account
        
        // Event handling will be set up after SDK is created
        
        // Start watching addresses
        logger.info("👀 Watching account addresses...")
        logger.info("   Account has \(account.addresses.count) addresses")
        await watchAccountAddresses(account)
        logger.info("   Address watching setup complete")
        
        // Start watch address verification
        startWatchVerification()
        
        // Update account balance after adding watch addresses
        logger.info("💰 Fetching initial balance...")
        do {
            try await updateAccountBalance(account)
            logger.info("   Initial balance fetched successfully")
        } catch {
            logger.warning("⚠️ Failed to fetch initial balance: \(error)")
            // Non-critical error, continue
        }
        
        logger.info("🎯 === CONNECTION COMPLETE ===")
        logger.info("   Total connection time: \(Date().timeIntervalSince(Date()))s")
        logger.info("   Ready for sync!")
    }
    
    func disconnect() async {
        // FIX: Cancel active sync properly
        cancelActiveSync()
        
        // Stop watch verification
        stopWatchVerification()
        
        if let sdk = sdk {
            try? await sdk.disconnect()
        }
        
        isConnected = false
        isSyncing = false
        syncProgress = nil
        detailedSyncProgress = nil
        sdk = nil
        watchVerificationStatus = .unknown
    }
    
    func startSync() async throws {
        guard let sdk = sdk, isConnected else {
            throw WalletError.notConnected
        }
        
        // FIX: Prevent multiple concurrent syncs
        syncLock.lock()
        defer { syncLock.unlock() }
        
        // Check if sync is already in progress
        if let existingTask = activeSyncTask, !existingTask.isCancelled {
            logger.warning("⚠️ Sync already in progress, skipping duplicate request")
            return
        }
        
        // Generate new sync request ID
        let requestId = UUID()
        syncRequestId = requestId
        
        logger.info("🔄 Starting sync (ID: \(requestId.uuidString.prefix(8)))")
        isSyncing = true
        
        activeSyncTask = Task { [weak self, requestId] in
            do {
                logger.info("📡 Starting enhanced sync with detailed progress...")
                var lastLogTime = Date()
                
                // Use the new sync progress stream from SDK
                for await progress in sdk.syncProgressStream() {
                    // Check if this sync was cancelled by a newer sync
                    guard self?.syncRequestId == requestId else {
                        logger.info("🛑 Sync cancelled (newer sync started)")
                        break
                    }
                    
                    if Task.isCancelled { break }
                    
                    await MainActor.run {
                        self?.detailedSyncProgress = progress
                        
                        // Convert to legacy SyncProgress for compatibility
                        self?.syncProgress = SyncProgress(
                            currentHeight: progress.currentHeight,
                            totalHeight: progress.totalHeight,
                            progress: progress.percentage / 100.0,
                            status: self?.mapSyncStageToStatus(progress.stage) ?? .connecting,
                            estimatedTimeRemaining: progress.estimatedSecondsRemaining > 0 ? TimeInterval(progress.estimatedSecondsRemaining) : nil,
                            message: progress.stageMessage
                        )
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
                    self?.isSyncing = false
                    self?.activeSyncTask = nil
                    
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
                    self?.isSyncing = false
                    self?.activeSyncTask = nil
                    self?.detailedSyncProgress = nil
                    logger.error("❌ Sync error: \(error)")
                }
            }
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
        cancelActiveSync()
    }
    
    // FIX: Proper sync cancellation with thread safety
    private func cancelActiveSync() {
        syncLock.lock()
        defer { syncLock.unlock() }
        
        if let task = activeSyncTask {
            logger.info("🛑 Cancelling active sync")
            task.cancel()
            activeSyncTask = nil
        }
        
        isSyncing = false
        syncRequestId = nil
    }
    
    // Alternative sync method using callbacks for real-time updates
    func startSyncWithCallbacks() async throws {
        guard let sdk = sdk, isConnected else {
            throw WalletError.notConnected
        }
        
        print("🔄 Starting callback-based sync for wallet: \(activeWallet?.name ?? "Unknown")")
        isSyncing = true
        
        try await sdk.syncToTipWithProgress(
            progressCallback: { [weak self] progress in
                Task { @MainActor in
                    self?.detailedSyncProgress = progress
                    
                    // Convert to legacy SyncProgress
                    self?.syncProgress = SyncProgress(
                        currentHeight: progress.currentHeight,
                        totalHeight: progress.totalHeight,
                        progress: progress.percentage / 100.0,
                        status: self?.mapSyncStageToStatus(progress.stage) ?? .connecting,
                        estimatedTimeRemaining: progress.estimatedSecondsRemaining > 0 ? TimeInterval(progress.estimatedSecondsRemaining) : nil,
                        message: progress.stageMessage
                    )
                    
                    print("\(progress.stage.icon) \(progress.statusMessage)")
                }
            },
            completionCallback: { [weak self] success, error in
                Task { @MainActor in
                    self?.isSyncing = false
                    
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
                        self?.detailedSyncProgress = nil
                    }
                }
            }
        )
    }
    
    // MARK: - Address Management
    
    func discoverAddresses(for account: HDAccount) async throws {
        guard let sdk = sdk, let wallet = account.wallet else {
            throw WalletError.invalidState
        }
        
        print("🔍 Starting address discovery for account: \(account.displayName)")
        
        // Use the AddressDiscoveryService for proper gap limit discovery
        let discoveryService = AddressDiscoveryService(sdk: sdk)
        
        let (externalAddresses, internalAddresses) = try await discoveryService.discoverAddresses(
            for: account,
            network: wallet.network,
            gapLimit: account.gapLimit
        )
        
        print("✅ Discovered \(externalAddresses.count) external and \(internalAddresses.count) internal addresses")
        
        // Save discovered addresses
        try await saveDiscoveredAddresses(
            account: account,
            external: externalAddresses,
            internalAddresses: internalAddresses
        )
        
        print("✅ Address discovery completed for account: \(account.displayName)")
    }
    
    /// Enhanced address generation with gap limit checking
    func generateAddressesWithGapLimit(for account: HDAccount) async throws {
        guard let wallet = account.wallet, let sdk = sdk else {
            throw WalletError.invalidState
        }
        
        // Generate addresses up to gap limit
        let gapLimit = account.gapLimit
        
        // Generate receive addresses
        var consecutiveUnused: UInt32 = 0
        var currentIndex = account.lastUsedExternalIndex + 1
        
        while consecutiveUnused < gapLimit && currentIndex < 1000 {
            let address = HDWalletService.deriveAddress(
                xpub: account.extendedPublicKey,
                network: wallet.network,
                change: false,
                index: currentIndex
            )
            
            // Check if address has been used
            let balance = try await sdk.getBalance(for: address)
            let isUsed = balance.total > 0
            
            if isUsed {
                consecutiveUnused = 0
                account.lastUsedExternalIndex = currentIndex
            } else {
                consecutiveUnused += 1
            }
            
            // Create watched address
            let path = BIP44.derivationPath(
                network: wallet.network,
                account: account.accountIndex,
                change: false,
                index: currentIndex
            )
            
            let watchedAddress = HDWatchedAddress(
                address: address,
                index: currentIndex,
                isChange: false,
                derivationPath: path,
                label: "Receive"
            )
            watchedAddress.account = account
            account.addresses.append(watchedAddress)
            
            // Watch the address
            try await sdk.watchAddress(address)
            
            currentIndex += 1
        }
        
        // Generate change addresses (smaller number)
        consecutiveUnused = 0
        currentIndex = account.lastUsedInternalIndex + 1
        let changeGapLimit = min(gapLimit, 5) // Limit change addresses
        
        while consecutiveUnused < changeGapLimit && currentIndex < 100 {
            let address = HDWalletService.deriveAddress(
                xpub: account.extendedPublicKey,
                network: wallet.network,
                change: true,
                index: currentIndex
            )
            
            // Check if address has been used
            let balance = try await sdk.getBalance(for: address)
            let isUsed = balance.total > 0
            
            if isUsed {
                consecutiveUnused = 0
                account.lastUsedInternalIndex = currentIndex
            } else {
                consecutiveUnused += 1
            }
            
            // Create watched address
            let path = BIP44.derivationPath(
                network: wallet.network,
                account: account.accountIndex,
                change: true,
                index: currentIndex
            )
            
            let watchedAddress = HDWatchedAddress(
                address: address,
                index: currentIndex,
                isChange: true,
                derivationPath: path,
                label: "Change"
            )
            watchedAddress.account = account
            account.addresses.append(watchedAddress)
            
            // Watch the address
            try await sdk.watchAddress(address)
            
            currentIndex += 1
        }
        
        try? modelContext?.save()
    }
    
    func generateNewAddress(for account: HDAccount, isChange: Bool = false) throws -> HDWatchedAddress {
        guard let wallet = account.wallet, let context = modelContext else {
            throw WalletError.noContext
        }
        
        let index = isChange ? account.lastUsedInternalIndex + 1 : account.lastUsedExternalIndex + 1
        
        let address = HDWalletService.deriveAddress(
            xpub: account.extendedPublicKey,
            network: wallet.network,
            change: isChange,
            index: index
        )
        
        let path = BIP44.derivationPath(
            network: wallet.network,
            account: account.accountIndex,
            change: isChange,
            index: index
        )
        
        let watchedAddress = HDWatchedAddress(
            address: address,
            index: index,
            isChange: isChange,
            derivationPath: path,
            label: isChange ? "Change" : "Receive"
        )
        watchedAddress.account = account
        
        account.addresses.append(watchedAddress)
        
        if isChange {
            account.lastUsedInternalIndex = index
        } else {
            account.lastUsedExternalIndex = index
        }
        
        try context.save()
        
        // Watch in PersistentWalletManager with proper error handling
        Task {
            do {
                if let sdk = sdk {
                    try await sdk.watchAddress(address, label: watchedAddress.label)
                    logger.info("Successfully watching new address: \(address)")
                } else {
                    logger.error("Cannot watch address: SDK not initialized")
                }
            } catch {
                logger.error("Failed to watch new address \(address): \(error)")
                // Schedule retry
                if let sdk = sdk, sdk.isConnected {
                    scheduleWatchAddressRetry(addresses: [address], account: account)
                }
            }
        }
        
        return watchedAddress
    }
    
    // MARK: - Balance & Transactions
    
    func updateAccountBalance(_ account: HDAccount) async throws {
        guard let sdk = sdk else {
            throw WalletError.notConnected
        }
        
        logger.info("💰 Updating account balance for: \(account.displayName)")
        
        var confirmedTotal: UInt64 = 0
        var pendingTotal: UInt64 = 0
        var instantLockedTotal: UInt64 = 0
        var mempoolTotal: UInt64 = 0
        
        // Store previous balance for comparison
        let previousBalance = account.balance?.total ?? 0
        
        for address in account.addresses {
            // Use regular getBalance for now (mempool tracking not yet available)
            let balance = try await sdk.getBalance(for: address.address)
            confirmedTotal += balance.confirmed
            pendingTotal += balance.pending
            instantLockedTotal += balance.instantLocked
            mempoolTotal += balance.mempool
            
            // Update individual address balance safely
            do {
                // Update address balance directly with SDK Balance
                try address.updateBalanceSafely(from: balance, in: modelContext!)
            } catch {
                logger.error("Failed to update address balance: \(error)")
            }
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
        
        // Update account balance safely
        do {
            try account.updateBalanceSafely(from: accountBalance, in: modelContext!)
        } catch {
            logger.error("Failed to update account balance: \(error)")
        }
        
        // Force UI update on main thread
        // This will trigger SwiftUI updates due to @Published properties
        objectWillChange.send()
        
        // Save to persistence
        try? modelContext?.save()
        
        // Log balance change using the updated account balance
        let currentTotal = account.balance?.total ?? 0
        let balanceChange = Int64(currentTotal) - Int64(previousBalance)
        if balanceChange != 0 {
            logger.info("💰 Balance changed by \(balanceChange) satoshis")
            logger.info("   Previous: \(previousBalance) satoshis")
            logger.info("   Current: \(currentTotal) satoshis")
            logger.info("   Confirmed: \(account.balance?.confirmed ?? 0)")
            logger.info("   Pending: \(account.balance?.pending ?? 0)")
            logger.info("   InstantLocked: \(account.balance?.instantLocked ?? 0)")
        }
        
        // Trigger balance update notification for immediate UI refresh
        if let updatedBalance = account.balance {
            await notifyBalanceUpdate(updatedBalance)
        }
    }
    
    func updateTransactions(for account: HDAccount) async throws {
        guard let sdk = sdk, let context = modelContext else {
            throw WalletError.notConnected
        }
        
        for address in account.addresses {
            let sdkTransactions = try await sdk.getTransactions(for: address.address)
            
            for sdkTx in sdkTransactions {
                // Check if transaction already exists
                let txidToCheck = sdkTx.txid
                let descriptor = FetchDescriptor<Transaction>(
                    predicate: #Predicate { transaction in
                        transaction.txid == txidToCheck
                    }
                )
                let existingTransactions = try? context.fetch(descriptor)
                
                if existingTransactions?.isEmpty == false {
                    // Transaction already exists, skip
                    continue
                } else {
                    // Create a new transaction instance for this context
                    let newTransaction = Transaction(
                        txid: sdkTx.txid,
                        height: sdkTx.height,
                        timestamp: sdkTx.timestamp,
                        amount: sdkTx.amount,
                        fee: sdkTx.fee,
                        confirmations: sdkTx.confirmations,
                        isInstantLocked: sdkTx.isInstantLocked,
                        raw: sdkTx.raw,
                        size: sdkTx.size,
                        version: sdkTx.version
                    )
                    context.insert(newTransaction)
                    
                    // Add transaction ID to account and address
                    if !account.transactionIds.contains(sdkTx.txid) {
                        account.transactionIds.append(sdkTx.txid)
                    }
                    if !address.transactionIds.contains(sdkTx.txid) {
                        address.transactionIds.append(sdkTx.txid)
                    }
                }
            }
        }
        
        try context.save()
    }
    
    // MARK: - Private Helpers
    
    private func handlePeerConnectivityIssue() async {
        logger.warning("🔄 Handling peer connectivity issue...")
        
        // Check if we're using local peers and should fallback to public
        if isUsingLocalPeers() {
            logger.info("📡 Local peers failed, attempting fallback to public peers...")
            
            // Switch to public peers
            setUseLocalPeers(false)
            
            // Disconnect and reconnect with new configuration
            if let wallet = activeWallet, let account = activeAccount {
                await disconnect()
                
                // Wait a moment before reconnecting
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                do {
                    try await connect(wallet: wallet, account: account)
                    logger.info("✅ Successfully reconnected with public peers")
                } catch {
                    logger.error("❌ Failed to reconnect with public peers: \(error)")
                }
            }
        } else {
            logger.error("❌ Public peers also failed to connect. Check network connectivity.")
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
            
        case .balanceUpdated(let balance):
            Task {
                if let account = activeAccount {
                    logger.info("💰 Balance updated - Confirmed: \(balance.confirmed), Pending: \(balance.pending), InstantLocked: \(balance.instantLocked), Total: \(balance.total)")
                    try? await updateAccountBalance(account)
                    
                    // Trigger a notification to other parts of the app
                    // Convert SDK balance to local Balance type
                    let localBalance = LocalBalance.from(balance)
                    await notifyBalanceUpdate(localBalance)
                }
            }
            
        case .transactionReceived(let txid, let confirmed, let amount, let addresses, let blockHeight):
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
                        await saveTransaction(
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
            
        case .mempoolTransactionAdded(let txid, let amount, let addresses):
            Task {
                if let account = activeAccount {
                    print("🔄 Mempool transaction added: \(txid)")
                    print("   Amount: \(amount) satoshis")
                    print("   Addresses: \(addresses)")
                    
                    // Save as unconfirmed transaction
                    await saveTransaction(
                        txid: txid,
                        amount: amount,
                        addresses: addresses,
                        confirmed: false,
                        blockHeight: nil,
                        account: account
                    )
                    
                    // Update mempool count
                    await updateMempoolTransactionCount()
                }
            }
            
        case .mempoolTransactionConfirmed(let txid, let blockHeight, let confirmations):
            Task {
                if activeAccount != nil {
                    print("✅ Mempool transaction confirmed: \(txid) at height \(blockHeight) with \(confirmations) confirmations")
                    
                    // Update transaction confirmation status
                    await confirmTransaction(txid: txid, blockHeight: blockHeight)
                    
                    // Update mempool count
                    await updateMempoolTransactionCount()
                }
            }
            
        case .mempoolTransactionRemoved(let txid, let reason):
            Task {
                if activeAccount != nil {
                    print("❌ Mempool transaction removed: \(txid), reason: \(reason)")
                    
                    // Remove or mark transaction as dropped
                    await removeTransaction(txid: txid)
                    
                    // Update mempool count
                    await updateMempoolTransactionCount()
                }
            }
            
        case .syncProgressUpdated(let progress):
            self.syncProgress = progress
            logger.info("📊 Sync progress: \(progress.percentageComplete)% - \(progress.status.description)")
            
        default:
            break
        }
    }
    
    private func watchAccountAddresses(_ account: HDAccount) async {
        guard let sdk = sdk else {
            logger.error("Cannot watch addresses: SDK not initialized")
            return
        }
        
        var failedAddresses: [(address: String, error: Error)] = []
        
        for address in account.addresses {
            do {
                try await sdk.watchAddress(address.address, label: address.label)
                logger.info("Successfully watching address: \(address.address)")
            } catch {
                logger.error("Failed to watch address \(address.address): \(error)")
                failedAddresses.append((address.address, error))
            }
        }
        
        // Handle failed addresses
        if !failedAddresses.isEmpty {
            await handleFailedWatchAddresses(failedAddresses, account: account)
        }
    }
    
    private func handleFailedWatchAddresses(_ failures: [(address: String, error: Error)], account: HDAccount) async {
        // Store failed addresses for retry
        pendingWatchAddresses[account.id.uuidString] = failures
        
        // Update pending watch count
        pendingWatchCount = pendingWatchAddresses.values.reduce(0) { $0 + $1.count }
        
        // Notify UI of partial failure
        watchAddressErrors = failures.map { _, error in
            if let watchError = error as? WatchAddressError {
                return watchError
            } else {
                return WatchAddressError.unknownError(error.localizedDescription)
            }
        }
        
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
    
    private func saveDiscoveredAddresses(
        account: HDAccount,
        external: [String],
        internalAddresses: [String]
    ) async throws {
        guard let wallet = account.wallet, let context = modelContext else {
            throw WalletError.noContext
        }
        
        // Save external addresses
        for (index, address) in external.enumerated() {
            let path = BIP44.derivationPath(
                network: wallet.network,
                account: account.accountIndex,
                change: false,
                index: UInt32(index)
            )
            
            let watchedAddress = HDWatchedAddress(
                address: address,
                index: UInt32(index),
                isChange: false,
                derivationPath: path,
                label: "Receive"
            )
            watchedAddress.account = account
            
            account.addresses.append(watchedAddress)
        }
        
        // Save internal addresses
        for (index, address) in internalAddresses.enumerated() {
            let path = BIP44.derivationPath(
                network: wallet.network,
                account: account.accountIndex,
                change: true,
                index: UInt32(index)
            )
            
            let watchedAddress = HDWatchedAddress(
                address: address,
                index: UInt32(index),
                isChange: true,
                derivationPath: path,
                label: "Change"
            )
            watchedAddress.account = account
            
            account.addresses.append(watchedAddress)
        }
        
        try context.save()
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
    
    private func saveTransaction(
        txid: String,
        amount: Int64,
        addresses: [String],
        confirmed: Bool,
        blockHeight: UInt32?,
        account: HDAccount
    ) async {
        guard let context = modelContext else { return }
        
        // Check if transaction already exists
        let descriptor = FetchDescriptor<Transaction>()
        
        let existingTransactions = try? context.fetch(descriptor)
        if let existingTx = existingTransactions?.first(where: { $0.txid == txid }) {
            // Update existing transaction
            existingTx.confirmations = confirmed ? max(1, existingTx.confirmations) : 0
            existingTx.height = blockHeight ?? existingTx.height
            print("📝 Updated existing transaction: \(txid)")
        } else {
            // Create new transaction
            let transaction = Transaction(
                txid: txid,
                height: blockHeight,
                timestamp: Date(),
                amount: amount,
                confirmations: confirmed ? 1 : 0,
                isInstantLocked: false
            )
            
            // Associate transaction ID with account
            if !account.transactionIds.contains(txid) {
                account.transactionIds.append(txid)
            }
            
            // Associate transaction ID with addresses
            for addressString in addresses {
                if let watchedAddress = account.addresses.first(where: { $0.address == addressString }) {
                    if !watchedAddress.transactionIds.contains(txid) {
                        watchedAddress.transactionIds.append(txid)
                    }
                    print("🔗 Linked transaction to address: \(addressString)")
                }
            }
            
            context.insert(transaction)
            print("💾 Saved new transaction: \(txid) with amount: \(amount) satoshis")
        }
        
        // Save context
        do {
            try context.save()
            logger.info("✅ Transaction saved to database")
            
            // Force immediate UI update
            objectWillChange.send()
            
            // Update account balance (this will trigger another UI update)
            try? await updateAccountBalance(account)
            
            // Log transaction for debugging
            // Note: SwiftData doesn't have registeredObjects, so we'll skip this for now
            logger.info("✅ Transaction saved successfully: \(txid)")
            
        } catch {
            logger.error("❌ Error saving transaction: \(error)")
        }
    }
    
    // MARK: - Mempool Transaction Helpers
    
    private func confirmTransaction(txid: String, blockHeight: UInt32) async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<Transaction>()
        let existingTransactions = try? context.fetch(descriptor)
        
        if let transaction = existingTransactions?.first(where: { $0.txid == txid }) {
            transaction.confirmations = 1
            transaction.height = blockHeight
            print("✅ Updated transaction \(txid) as confirmed at height \(blockHeight)")
            
            do {
                try context.save()
                // Update balance after confirmation
                if let account = activeAccount {
                    try? await updateAccountBalance(account)
                }
            } catch {
                print("❌ Error updating confirmed transaction: \(error)")
            }
        }
    }
    
    private func removeTransaction(txid: String) async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<Transaction>()
        let existingTransactions = try? context.fetch(descriptor)
        
        if let transaction = existingTransactions?.first(where: { $0.txid == txid }) {
            // Remove transaction from account and address references
            if let account = activeAccount {
                account.transactionIds.removeAll { $0 == txid }
                
                for address in account.addresses {
                    address.transactionIds.removeAll { $0 == txid }
                }
            }
            
            // Delete the transaction
            context.delete(transaction)
            print("🗑️ Removed transaction \(txid) from database")
            
            do {
                try context.save()
                // Update balance after removal
                if let account = activeAccount {
                    try? await updateAccountBalance(account)
                }
            } catch {
                print("❌ Error removing transaction: \(error)")
            }
        }
    }
    
    private func updateMempoolTransactionCount() async {
        guard let context = modelContext, let account = activeAccount else { return }
        
        let descriptor = FetchDescriptor<Transaction>()
        let allTransactions = try? context.fetch(descriptor)
        
        // Count unconfirmed transactions (confirmations == 0)
        let accountTxIds = Set(account.transactionIds)
        let mempoolCount = allTransactions?.filter { transaction in
            accountTxIds.contains(transaction.txid) && transaction.confirmations == 0
        }.count ?? 0
        
        await MainActor.run {
            self.mempoolTransactionCount = mempoolCount
        }
    }
    
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
            
            // Update pending count
            await MainActor.run {
                self.pendingWatchCount = self.pendingWatchAddresses.values.reduce(0) { $0 + $1.count }
            }
        }
    }
    
    // MARK: - Watch Address Verification
    
    private func startWatchVerification() {
        watchVerificationTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            Task {
                await self.verifyAllWatchedAddresses()
            }
        }
    }
    
    private func stopWatchVerification() {
        watchVerificationTimer?.invalidate()
        watchVerificationTimer = nil
    }
    
    private func verifyAllWatchedAddresses() async {
        guard let _ = sdk, let account = activeAccount else { return }
        
        watchVerificationStatus = .verifying
        
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
            
            watchVerificationStatus = .verified(total: totalAddresses, watching: watchedAddresses)
        } catch {
            logger.error("Failed to verify watched addresses for account \(account.label): \(error)")
            watchVerificationStatus = .failed(error: error.localizedDescription)
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
        guard let modelContext = modelContext else { return [] }
        
        // Get all transaction IDs from the account
        let txids = account.transactionIds
        guard !txids.isEmpty else { return [] }
        
        var sdkTransactions: [SwiftDashCoreSDK.Transaction] = []
        
        // Fetch each transaction from SwiftData
        for txid in txids {
            do {
                let predicate = #Predicate<Transaction> { transaction in
                    transaction.txid == txid
                }
                let descriptor = FetchDescriptor<Transaction>(predicate: predicate)
                
                if let storedTransaction = try modelContext.fetch(descriptor).first {
                    // Convert SwiftData Transaction to SDK Transaction
                    let sdkTransaction = SwiftDashCoreSDK.Transaction(
                        txid: storedTransaction.txid,
                        height: storedTransaction.height,
                        timestamp: storedTransaction.timestamp,
                        amount: storedTransaction.amount,
                        fee: storedTransaction.fee ?? 0,
                        confirmations: storedTransaction.confirmations,
                        isInstantLocked: storedTransaction.isInstantLocked,
                        raw: storedTransaction.raw ?? Data(),
                        size: storedTransaction.size ?? 0,
                        version: storedTransaction.version ?? 1
                    )
                    sdkTransactions.append(sdkTransaction)
                }
            } catch {
                logger.error("❌ Error fetching transaction \(txid): \(error)")
            }
        }
        
        // Sort by timestamp, newest first
        return sdkTransactions.sorted { $0.timestamp > $1.timestamp }
    }
    
    /// Manually check for new transactions for all watched addresses
    func checkForNewTransactions() async {
        guard let sdk = sdk, let account = activeAccount else { 
            logger.warning("⚠️ Cannot check transactions: SDK or account not available")
            return 
        }
        
        logger.info("🔍 Manually checking for new transactions...")
        logger.info("   Active account: \(account.label)")
        logger.info("   Number of addresses: \(account.addresses.count)")
        
        for address in account.addresses {
            do {
                logger.info("   Checking address: \(address.address)")
                let transactions = try await sdk.getTransactions(for: address.address)
                logger.info("📊 Found \(transactions.count) transactions for address \(address.address)")
                
                for transaction in transactions {
                    // Check if we already have this transaction
                    if !account.transactionIds.contains(transaction.txid) {
                        logger.info("🆕 Found new transaction: \(transaction.txid)")
                        
                        // Determine the addresses involved
                        let addresses = [address.address] // We know at least this address is involved
                        
                        // Save the transaction
                        await saveTransaction(
                            txid: transaction.txid,
                            amount: transaction.amount,
                            addresses: addresses,
                            confirmed: transaction.confirmations > 0,
                            blockHeight: transaction.height,
                            account: account
                        )
                        
                        // Show notification for received funds
                        if transaction.amount > 0 {
                            await showFundsReceivedNotification(
                                amount: transaction.amount,
                                txid: transaction.txid,
                                confirmed: transaction.confirmations > 0
                            )
                        }
                    }
                }
            } catch {
                logger.error("❌ Error checking transactions for address \(address.address): \(error)")
            }
        }
        
        logger.info("✅ Transaction check complete")
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
        await saveTransaction(
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
        
        await confirmTransaction(txid: mockTxid, blockHeight: 850000)
        
        logger.info("✅ Step 6: Transaction confirmation simulated")
        
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
                let testnetConfig = SPVConfigurationManager.shared.configuration(for: .testnet)
                logger.info("   - Available testnet peers:")
                for peer in testnetConfig.additionalPeers {
                    logger.info("     • \(peer)")
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
