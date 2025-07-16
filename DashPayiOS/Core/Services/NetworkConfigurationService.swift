import Foundation
import SwiftDashCoreSDK
import os.log

/// Service responsible for network configuration and peer management
class NetworkConfigurationService: ObservableObject {
    private let logger = Logger(subsystem: "com.dash.wallet", category: "NetworkConfigurationService")
    
    // Note: Peer discovery is now handled automatically by rust-dashcore SPV client
    // Legacy peer arrays kept for reference but no longer used
    
    /// Setup SPV configuration for a wallet
    func setupConfiguration(for network: DashNetwork) async throws -> SPVClientConfiguration {
        logger.info("🔧 Getting SPV configuration for network: \(network.rawValue)")
        let config = try SPVConfigurationManager.shared.configuration(for: network)
        logger.info("📁 SPV data directory: \(config.dataDirectory?.path ?? "nil")")
        
        // Override log level for debugging if needed (temporary)
        config.logLevel = "trace"
        
        // Configure peers based on user preference
        let useLocalPeers = UserDefaults.standard.bool(forKey: "useLocalPeers")
        logger.info("🌐 Configuring peer connections...")
        logger.info("   Use Local Peers: \(useLocalPeers)")
        
        if useLocalPeers {
            await configureLocalPeers(config: config, network: network)
        } else {
            await configurePublicPeers(config: config, network: network)
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
    
    /// Toggle between local and public peers
    func setUseLocalPeers(_ useLocal: Bool) {
        UserDefaults.standard.set(useLocal, forKey: "useLocalPeers")
        logger.info("🔧 Peer configuration updated: useLocalPeers = \(useLocal)")
    }
    
    /// Check current peer configuration
    func isUsingLocalPeers() -> Bool {
        return UserDefaults.standard.bool(forKey: "useLocalPeers")
    }
    
    /// Set custom local peer host (for development)
    func setLocalPeerHost(_ host: String) {
        UserDefaults.standard.set(host, forKey: "localPeerHost")
        logger.info("🔧 Local peer host updated: \(host)")
    }
    
    /// Get current local peer host
    func getLocalPeerHost() -> String {
        return UserDefaults.standard.string(forKey: "localPeerHost") ?? "127.0.0.1"
    }
    
    /// Handle peer connectivity issues with fallback strategy
    func handlePeerConnectivityIssue() async {
        logger.warning("🔄 Handling peer connectivity issue...")
        
        // Check if we're using local peers and should fallback to public
        if isUsingLocalPeers() {
            logger.info("📡 Local peers failed, switching to public peers...")
            setUseLocalPeers(false)
        } else {
            logger.error("❌ Public peers also failed to connect. Check network connectivity.")
        }
    }
    
    /// Test peer connectivity
    func testPeerConnectivity(for network: DashNetwork) async -> [String: Any] {
        logger.info("🧪 Testing peer connectivity for network: \(network.rawValue)")
        
        var result: [String: Any] = [:]
        result["network"] = network.rawValue
        result["useLocalPeers"] = isUsingLocalPeers()
        result["localPeerHost"] = getLocalPeerHost()
        
        do {
            let config = try await setupConfiguration(for: network)
            result["configuredPeers"] = config.additionalPeers
            result["maxPeers"] = config.maxPeers
            result["success"] = true
        } catch {
            result["error"] = error.localizedDescription
            result["success"] = false
        }
        
        logger.info("📊 Peer connectivity test completed")
        return result
    }
    
    // MARK: - Private Helper Methods
    
    private func configureLocalPeers(config: SPVClientConfiguration, network: DashNetwork) async {
        logger.info("🔧 Configuring LOCAL peers for \(network.rawValue)")
        
        // Get custom local peer from UserDefaults or use localhost as fallback
        let localPeerHost = getLocalPeerHost()
        logger.info("   Local peer host: \(localPeerHost)")
        
        if network == .mainnet {
            let localMainnetPeer = "\(localPeerHost):9999"
            config.additionalPeers = [localMainnetPeer]
            logger.info("   Local mainnet peer configured: \(localMainnetPeer)")
        } else if network == .testnet {
            let localTestnetPeer = "\(localPeerHost):19999"
            config.additionalPeers = [localTestnetPeer]
            logger.info("   Local testnet peer configured: \(localTestnetPeer)")
        }
    }
    
    private func configurePublicPeers(config: SPVClientConfiguration, network: DashNetwork) async {
        logger.info("🌐 Using AUTOMATIC peer discovery for \(network.rawValue)")
        logger.info("   SPV client will handle DNS seed resolution and peer management")
        
        // Clear any existing peers to let SPV client handle discovery
        config.additionalPeers = []
    }
}