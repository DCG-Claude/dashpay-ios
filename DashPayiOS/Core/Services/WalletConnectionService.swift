import Foundation
import SwiftDashCoreSDK
import os.log

/// Service responsible for wallet connection management and network configuration
@MainActor
class WalletConnectionService: ObservableObject {
    private let logger = Logger(subsystem: "com.dash.wallet", category: "WalletConnectionService")
    
    @Published var isConnected: Bool = false
    private(set) var sdk: DashSDK?
    
    func setSDK(_ sdk: DashSDK) {
        self.sdk = sdk
    }
    
    private let connectionService = ConnectionStateService()
    private let networkConfigurationService = NetworkConfigurationService()
    
    // Note: Peer discovery is now handled automatically by rust-dashcore SPV client
    // No need for hardcoded peer lists - the underlying library handles this
    
    // MARK: - Connection Management
    
    func setupConfiguration(wallet: HDWallet) async throws -> SPVClientConfiguration {
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
            // Use public peers - rust-dashcore will automatically discover and connect to peers
            logger.info("🌐 Using PUBLIC peer discovery for \(wallet.network.rawValue)")
            logger.info("   Rust-dashcore will automatically discover peers via DNS seeds")
            // Clear any additional peers to let the library handle discovery
            config.additionalPeers = []
            logger.info("   Peer discovery delegated to rust-dashcore SPV client")
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
    
    func initializeSDK(with config: SPVClientConfiguration) async throws {
        logger.info("📡 Initializing SDK components...")
        logger.info("   Thread before MainActor: \(Thread.isMainThread ? "Main" : "Background")")
        
        do {
            // Initialize SDK components on MainActor following rust-dashcore pattern
            let createdSDK = try await MainActor.run {
                logger.info("   Thread in MainActor: \(Thread.isMainThread ? "Main" : "Background")")
                
                // Create DashSDK (which includes SPVClient and PersistentWalletManager internally)
                logger.info("   Creating DashSDK...")
                let dashSDK = try DashSDK(configuration: config)
                logger.info("   ✅ DashSDK created")
                
                return dashSDK
            }
            self.sdk = createdSDK
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
    
    func connectToNetwork() async throws {
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
                connectionService.setConnected(true)
                connectionService.setSDK(sdk)
                isConnected = true
                logger.info("✅ Connected successfully!")
                logger.info("   Connection state: \(self.isConnected)")
                logger.info("   SDK connected: \(sdk.isConnected)")
                
                // Stop the SDK's automatic periodic sync immediately
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
    
    func disconnect() async {
        if let sdk = sdk {
            try? await sdk.disconnect()
        }
        
        connectionService.reset()
        isConnected = false
        sdk = nil
    }
    
    // MARK: - Peer Configuration
    
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
    
    /// Retry connection with exponential backoff
    func retryConnection(wallet: HDWallet, account: HDAccount, maxAttempts: Int = 3) async throws {
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
                
                // Setup configuration
                let config = try await setupConfiguration(wallet: wallet)
                
                // Initialize SDK
                try await initializeSDK(with: config)
                
                // Connect to network
                try await connectToNetwork()
                
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
    
    private func handlePeerConnectivityIssue() async {
        await networkConfigurationService.handlePeerConnectivityIssue()
    }
}