import Foundation
import os.log
import SwiftDashSDK
import SwiftDashCoreSDK

/// Singleton manager for SPVClientConfiguration instances
/// Ensures each network configuration is created only once
public final class SPVConfigurationManager {
    public static let shared = SPVConfigurationManager()
    
    // Concurrent queue for thread-safe access to shared resources
    private let concurrentQueue = DispatchQueue(label: "com.dash.wallet.spv-config", attributes: .concurrent)
    
    // One configuration per network
    private var configurations: [DashNetwork: SPVClientConfiguration] = [:]
    
    // Configuration flag to control error handling behavior
    private var _throwOnDirectoryCreationFailure: Bool = false
    public var throwOnDirectoryCreationFailure: Bool {
        get {
            return concurrentQueue.sync {
                return _throwOnDirectoryCreationFailure
            }
        }
        set {
            concurrentQueue.async(flags: .barrier) {
                self._throwOnDirectoryCreationFailure = newValue
            }
        }
    }
    
    // Logger for configuration tracking
    private let logger = Logger(subsystem: "com.dash.wallet", category: "SPVConfigurationManager")
    
    private init() {
        logger.info("🔧 SPVConfigurationManager initialized")
    }
    
    /// Get the standard configuration for a network (creates once, reuses thereafter)
    public func configuration(for network: DashNetwork) throws -> SPVClientConfiguration {
        // First, check if configuration exists using sync read
        if let existing = concurrentQueue.sync(execute: { configurations[network] }) {
            logger.info("♻️ Reusing existing configuration for network: \(network.rawValue)")
            return existing
        }
        
        // Create new configuration outside the queue to avoid blocking other readers
        logger.info("🆕 Creating new configuration for network: \(network.rawValue)")
        let config = try createStandardConfiguration(for: network)
        
        // Write to dictionary using barrier write
        concurrentQueue.async(flags: .barrier) {
            self.configurations[network] = config
        }
        
        logger.info("✅ Configuration cached for network: \(network.rawValue)")
        return config
    }
    
    /// Clear all cached configurations (useful for testing)
    public func clearCache() {
        concurrentQueue.async(flags: .barrier) {
            let count = self.configurations.count
            self.configurations.removeAll()
            self.logger.info("🗑️ Cleared \(count) cached configurations")
        }
    }
    
    /// Get diagnostic information about cached configurations
    public var diagnostics: String {
        return concurrentQueue.sync {
            let configInfo = configurations.map { network, _ in
                "- \(network.rawValue): cached"
            }.joined(separator: "\n")
            
            return """
            SPVConfigurationManager Diagnostics:
            Total cached configurations: \(configurations.count)
            \(configInfo.isEmpty ? "No configurations cached" : configInfo)
            """
        }
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