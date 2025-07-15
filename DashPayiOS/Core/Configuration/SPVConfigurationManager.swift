import Foundation
import os.log
import SwiftDashSDK
import SwiftDashCoreSDK

/// Singleton manager for SPVClientConfiguration instances
/// Ensures each network configuration is created only once
@MainActor
public final class SPVConfigurationManager {
    public static let shared = SPVConfigurationManager()
    
    // One configuration per network
    private var configurations: [DashNetwork: SPVClientConfiguration] = [:]
    
    // Logger for configuration tracking
    private let logger = Logger(subsystem: "com.dash.wallet", category: "SPVConfigurationManager")
    
    private init() {
        logger.info("🔧 SPVConfigurationManager initialized")
    }
    
    /// Get the standard configuration for a network (creates once, reuses thereafter)
    public func configuration(for network: DashNetwork) -> SPVClientConfiguration {
        if let existing = configurations[network] {
            logger.info("♻️ Reusing existing configuration for network: \(network.rawValue)")
            return existing
        }
        
        logger.info("🆕 Creating new configuration for network: \(network.rawValue)")
        let config = createStandardConfiguration(for: network)
        configurations[network] = config
        logger.info("✅ Configuration cached for network: \(network.rawValue)")
        return config
    }
    
    /// Clear all cached configurations (useful for testing)
    public func clearCache() {
        let count = configurations.count
        configurations.removeAll()
        logger.info("🗑️ Cleared \(count) cached configurations")
    }
    
    /// Get diagnostic information about cached configurations
    public var diagnostics: String {
        let configInfo = configurations.map { network, _ in
            "- \(network.rawValue): cached"
        }.joined(separator: "\n")
        
        return """
        SPVConfigurationManager Diagnostics:
        Total cached configurations: \(configurations.count)
        \(configInfo.isEmpty ? "No configurations cached" : configInfo)
        """
    }
    
    // MARK: - Private Configuration Creation
    
    private func createStandardConfiguration(for network: DashNetwork) -> SPVClientConfiguration {
        let config: SPVClientConfiguration
        
        // Create base configuration for network
        switch network {
        case .testnet:
            config = SPVClientConfiguration.testnet()
        case .mainnet:
            config = SPVClientConfiguration.mainnet()
        case .devnet:
            config = SPVClientConfiguration.testnet()
            config.network = .devnet
        case .regtest:
            config = SPVClientConfiguration.regtest()
        }
        
        // Apply standard settings
        config.validationMode = .full
        config.mempoolConfig = .fetchAll(maxTransactions: 5000)
        config.logLevel = "info"
        config.maxPeers = NetworkConstants.maxPeers
        
        // Add testnet peer if needed
        if network == .testnet {
            config.additionalPeers = [NetworkConstants.primaryTestnetPeer]
        }
        
        // Set data directory
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            config.dataDirectory = documentsPath
                .appendingPathComponent("DashSPV")
                .appendingPathComponent(network.rawValue)
            
            // Create directory if needed
            do {
                try FileManager.default.createDirectory(at: config.dataDirectory!, withIntermediateDirectories: true, attributes: nil)
                logger.info("📁 Created data directory: \(config.dataDirectory!.path)")
            } catch {
                logger.error("❌ Failed to create data directory: \(error.localizedDescription)")
                logger.error("   Path: \(config.dataDirectory!.path)")
                // Don't throw here as SPV client might handle missing directory gracefully
                // But log the error so it's visible for debugging
            }
        }
        
        return config
    }
}