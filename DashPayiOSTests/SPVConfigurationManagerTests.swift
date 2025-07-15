import XCTest
@testable import DashPay
import SwiftDashCoreSDK

@MainActor
class SPVConfigurationManagerTests: XCTestCase {
    
    override func setUp() async throws {
        try await super.setUp()
        // Clear any cached configurations before each test
        SPVConfigurationManager.shared.clearCache()
    }
    
    func testSingletonInstance() {
        // Verify singleton pattern
        let instance1 = SPVConfigurationManager.shared
        let instance2 = SPVConfigurationManager.shared
        XCTAssertTrue(instance1 === instance2, "SPVConfigurationManager should be a singleton")
    }
    
    func testConfigurationCaching() throws {
        // Get configuration for testnet
        let config1 = try SPVConfigurationManager.shared.configuration(for: .testnet)
        let config2 = try SPVConfigurationManager.shared.configuration(for: .testnet)
        
        // Verify same instance is returned (cached)
        XCTAssertTrue(config1 === config2, "Configuration should be cached and reused")
        
        // Get configuration for different network
        let config3 = try SPVConfigurationManager.shared.configuration(for: .mainnet)
        XCTAssertTrue(config1 !== config3, "Different networks should have different configurations")
    }
    
    func testConfigurationSettings() throws {
        // Test testnet configuration
        let testnetConfig = try SPVConfigurationManager.shared.configuration(for: .testnet)
        XCTAssertEqual(testnetConfig.network, .testnet)
        XCTAssertEqual(testnetConfig.validationMode, .full)
        XCTAssertEqual(testnetConfig.maxPeers, 12)
        XCTAssertEqual(testnetConfig.logLevel, "info")
        XCTAssertNotNil(testnetConfig.dataDirectory)
        XCTAssertTrue(testnetConfig.additionalPeers.contains(NetworkConstants.primaryTestnetPeer))
        
        // Test mainnet configuration
        let mainnetConfig = try SPVConfigurationManager.shared.configuration(for: .mainnet)
        XCTAssertEqual(mainnetConfig.network, .mainnet)
        XCTAssertEqual(mainnetConfig.validationMode, .full)
        XCTAssertEqual(mainnetConfig.maxPeers, 12)
    }
    
    func testClearCache() throws {
        // Create configurations
        _ = try SPVConfigurationManager.shared.configuration(for: .testnet)
        _ = try SPVConfigurationManager.shared.configuration(for: .mainnet)
        
        // Print diagnostics before clear
        let diagnosticsBefore = SPVConfigurationManager.shared.diagnostics
        print("Diagnostics before clear:\n\(diagnosticsBefore)")
        
        // Clear cache
        SPVConfigurationManager.shared.clearCache()
        
        // Print diagnostics after clear
        let diagnosticsAfter = SPVConfigurationManager.shared.diagnostics
        print("Diagnostics after clear:\n\(diagnosticsAfter)")
        
        // Get configurations again
        let config1 = try SPVConfigurationManager.shared.configuration(for: .testnet)
        let config2 = try SPVConfigurationManager.shared.configuration(for: .testnet)
        
        // Should still be cached after recreation
        XCTAssertTrue(config1 === config2, "Configuration should be cached after clear and recreation")
    }
    
    func testDiagnostics() throws {
        // Create some configurations
        _ = try SPVConfigurationManager.shared.configuration(for: .testnet)
        _ = try SPVConfigurationManager.shared.configuration(for: .mainnet)
        
        let diagnostics = SPVConfigurationManager.shared.diagnostics
        print("Configuration Manager Diagnostics:\n\(diagnostics)")
        
        XCTAssertTrue(diagnostics.contains("Total cached configurations: 2"))
        XCTAssertTrue(diagnostics.contains("testnet: cached"))
        XCTAssertTrue(diagnostics.contains("mainnet: cached"))
    }
    
    func testMemoryEfficiency() throws {
        // Create multiple references to same configuration
        var configs: [SPVClientConfiguration] = []
        
        for _ in 0..<10 {
            configs.append(try SPVConfigurationManager.shared.configuration(for: .testnet))
        }
        
        // All should be the same instance
        let firstConfig = configs[0]
        for config in configs {
            XCTAssertTrue(config === firstConfig, "All testnet configurations should be the same instance")
        }
        
        // Print final diagnostics
        print("\nFinal diagnostics:\n\(SPVConfigurationManager.shared.diagnostics)")
    }
}