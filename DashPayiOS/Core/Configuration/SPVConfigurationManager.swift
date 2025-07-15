import Foundation
import os.log
import SwiftDashSDK
import SwiftDashCoreSDK

/// Singleton manager for SPVClientConfiguration instances
/// Ensures each network configuration is created only once
public final class SPVConfigurationManager {
    public static let shared = SPVConfigurationManager()
    
    // One configuration per network
    private var configurations: [DashNetwork: SPVClientConfiguration] = [:]
    
    // Configuration flag to control error handling behavior
    public var throwOnDirectoryCreationFailure: Bool = false
    
    // Logger for configuration tracking
    private let logger = Logger(subsystem: "com.dash.wallet", category: "SPVConfigurationManager")
    
    private init() {
        logger.info("🔧 SPVConfigurationManager initialized")
    }
    
    /// Get the standard configuration for a network (creates once, reuses thereafter)
    public func configuration(for network: DashNetwork) throws -> SPVClientConfiguration {
        if let existing = configurations[network] {
            logger.info("♻️ Reusing existing configuration for network: \(network.rawValue)")
            return existing
        }
        
        logger.info("🆕 Creating new configuration for network: \(network.rawValue)")
        let config = try createStandardConfiguration(for: network)
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
    
    /// Clear SPV data to enable checkpoint sync
    /// This forces the SPV client to start fresh and use the latest checkpoint
    public func clearSPVDataForCheckpointSync(network: DashNetwork) throws {
        logger.info("🔄 Clearing SPV data for checkpoint sync on \(network.rawValue)")
        
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "SPVConfig", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot find documents directory"])
        }
        
        let spvDataPath = documentsPath
            .appendingPathComponent("DashSPV")
            .appendingPathComponent(network.rawValue)
        
        // Check if directory exists
        if FileManager.default.fileExists(atPath: spvDataPath.path) {
            logger.info("📁 Found existing SPV data at: \(spvDataPath.path)")
            
            // Remove the directory and all its contents
            try FileManager.default.removeItem(at: spvDataPath)
            logger.info("✅ Cleared SPV data successfully")
            
            // Recreate empty directory
            try FileManager.default.createDirectory(at: spvDataPath, withIntermediateDirectories: true, attributes: nil)
            logger.info("📁 Recreated empty SPV data directory")
        } else {
            logger.info("ℹ️ No existing SPV data found - checkpoint sync will be used automatically")
        }
        
        // Clear cached configuration to force recreation
        configurations.removeValue(forKey: network)
        logger.info("♻️ Cleared cached configuration for \(network.rawValue)")
    }
    
    // MARK: - Private Configuration Creation
    
    private func createStandardConfiguration(for network: DashNetwork) throws -> SPVClientConfiguration {
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
        // Note: maxPeers is handled by rust-dashcore SPV client (defaults to 3)
        
        // Enable checkpoint sync for faster initial synchronization
        config.enableCheckpointSync()
        
        // Note: Peer discovery is now handled automatically by rust-dashcore SPV client
        // No manual peer configuration needed
        
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
                
                // Conditionally propagate the error based on configuration flag
                if throwOnDirectoryCreationFailure {
                    logger.error("🚨 Propagating directory creation error as requested by configuration")
                    throw error
                } else {
                    logger.info("ℹ️ Continuing despite directory creation failure (SPV client may handle gracefully)")
                }
            }
        }
        
        return config
    }
}