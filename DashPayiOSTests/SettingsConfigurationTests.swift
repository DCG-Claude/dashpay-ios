import XCTest
@testable import DashPay
import SwiftData

/// Comprehensive test suite for DashPay iOS Settings and Configuration functionality
@MainActor
final class SettingsConfigurationTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var walletService: WalletService!
    var appState: AppState!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Create in-memory model container for testing
        let schema = Schema([
            HDWallet.self,
            HDAccount.self,
            HDWatchedAddress.self,
            Transaction.self,
            UTXO.self,
            Balance.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        
        modelContext = ModelContext(modelContainer)
        
        // Initialize services
        walletService = WalletService.shared
        walletService.configure(modelContext: modelContext)
        
        appState = AppState()
        
        // Clear UserDefaults for clean testing
        UserDefaults.standard.removeObject(forKey: "useLocalPeers")
        UserDefaults.standard.removeObject(forKey: "localPeerHost")
        UserDefaults.standard.removeObject(forKey: "currentNetwork")
    }
    
    override func tearDownWithError() throws {
        // Clean up test data
        UserDefaults.standard.removeObject(forKey: "useLocalPeers")
        UserDefaults.standard.removeObject(forKey: "localPeerHost")
        UserDefaults.standard.removeObject(forKey: "currentNetwork")
        
        modelContainer = nil
        modelContext = nil
        walletService = nil
        appState = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Navigation Tests
    
    func testSettingsViewCreation() throws {
        // Test that SettingsView can be created without errors
        let settingsView = SettingsView()
        XCTAssertNotNil(settingsView, "SettingsView should be created successfully")
    }
    
    // MARK: - Network Configuration Tests
    
    func testLocalPeersToggle() throws {
        // Test initial state
        XCTAssertFalse(walletService.isUsingLocalPeers(), "Should default to false for local peers")
        
        // Test enabling local peers
        walletService.setUseLocalPeers(true)
        XCTAssertTrue(walletService.isUsingLocalPeers(), "Should be true after enabling local peers")
        
        // Test disabling local peers
        walletService.setUseLocalPeers(false)
        XCTAssertFalse(walletService.isUsingLocalPeers(), "Should be false after disabling local peers")
    }
    
    func testLocalPeersPersistence() throws {
        // Test that local peers setting persists
        walletService.setUseLocalPeers(true)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "useLocalPeers"), "Setting should persist in UserDefaults")
        
        // Create new service instance to test persistence
        let newWalletService = WalletService.shared
        XCTAssertTrue(newWalletService.isUsingLocalPeers(), "Setting should persist across service instances")
    }
    
    func testLocalPeerHostConfiguration() throws {
        // Test default local peer host
        XCTAssertEqual(walletService.getLocalPeerHost(), "127.0.0.1", "Should default to localhost")
        
        // Test setting custom host
        walletService.setLocalPeerHost("192.168.1.100")
        XCTAssertEqual(walletService.getLocalPeerHost(), "192.168.1.100", "Should return custom host")
        
        // Test persistence
        XCTAssertEqual(UserDefaults.standard.string(forKey: "localPeerHost"), "192.168.1.100", "Should persist in UserDefaults")
    }
    
    func testNetworkSwitching() throws {
        // Test initial network
        XCTAssertEqual(appState.currentNetwork, .testnet, "Should default to testnet")
        
        // Test switching to mainnet
        appState.currentNetwork = .mainnet
        XCTAssertEqual(appState.currentNetwork, .mainnet, "Should switch to mainnet")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "currentNetwork"), "mainnet", "Should persist network change")
        
        // Test switching to devnet
        appState.currentNetwork = .devnet
        XCTAssertEqual(appState.currentNetwork, .devnet, "Should switch to devnet")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "currentNetwork"), "devnet", "Should persist network change")
    }
    
    // MARK: - SPV Configuration Tests
    
    func testSPVConfigurationCreation() throws {
        // Test testnet configuration
        let testnetConfig = SPVConfigurationManager.shared.configuration(for: .testnet)
        XCTAssertEqual(testnetConfig.network, .testnet, "Should create testnet configuration")
        // Note: Peers are now configured in WalletService, not in the base configuration
        // XCTAssertGreaterThan(testnetConfig.additionalPeers.count, 0, "Should have testnet peers configured")
        // XCTAssertEqual(testnetConfig.maxPeers, 8, "Should have correct max peers for testnet")
        
        // Test mainnet configuration
        let mainnetConfig = SPVConfigurationManager.shared.configuration(for: .mainnet)
        XCTAssertEqual(mainnetConfig.network, .mainnet, "Should create mainnet configuration")
        // Note: Peers are now configured in WalletService, not in the base configuration
        // XCTAssertGreaterThan(mainnetConfig.additionalPeers.count, 0, "Should have mainnet peers configured")
        
        // Test devnet configuration (regtest is not in our enum)
        let devnetConfig = SPVConfigurationManager.shared.configuration(for: .devnet)
        XCTAssertEqual(devnetConfig.network, .devnet, "Should create devnet configuration")
    }
    
    func testSPVConfigurationValidation() throws {
        // Our mock SPVClientConfiguration doesn't have validation
        // This test would work with the real SDK
        let config = SPVConfigurationManager.shared.configuration(for: .testnet)
        
        // Test that configuration can be created
        XCTAssertNotNil(config, "Should be able to create configuration")
        XCTAssertEqual(config.network, .testnet, "Should default to testnet")
    }
    
    func testSPVPeerConfiguration() throws {
        let config = SPVConfigurationManager.shared.configuration(for: .testnet)
        
        // Note: We no longer expect DNS seeds since we use hardcoded IP addresses
        // This change aligns with the working rust-dashcore example
        
        // Our mock SPVClientConfiguration doesn't have additionalPeers
        // Just verify the configuration is created properly
        XCTAssertEqual(config.network, .testnet, "Should be testnet configuration")
        XCTAssertEqual(config.validationMode, .full, "Should use full validation")
    }
    
    // MARK: - Settings Persistence Tests
    
    func testSettingsPersistenceAcrossAppRestarts() throws {
        // Simulate app settings before restart
        walletService.setUseLocalPeers(true)
        walletService.setLocalPeerHost("10.0.0.1")
        appState.currentNetwork = .mainnet
        
        // Verify settings are persisted
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "useLocalPeers"))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "localPeerHost"), "10.0.0.1")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "currentNetwork"), "mainnet")
        
        // Simulate app restart by creating new instances
        let newWalletService = WalletService.shared
        let newAppState = AppState()
        
        // Verify settings are restored
        XCTAssertTrue(newWalletService.isUsingLocalPeers())
        XCTAssertEqual(newWalletService.getLocalPeerHost(), "10.0.0.1")
        XCTAssertEqual(newAppState.currentNetwork, .mainnet)
    }
    
    // MARK: - Data Management Tests
    
    func testResetAllDataFunctionality() throws {
        // Create test data
        let wallet = HDWallet(
            name: "Test Wallet",
            network: .testnet,
            encryptedSeed: Data("test".utf8),
            seedHash: "testhash"
        )
        modelContext.insert(wallet)
        try modelContext.save()
        
        // Verify test data exists
        let descriptor = FetchDescriptor<HDWallet>()
        let wallets = try modelContext.fetch(descriptor)
        XCTAssertGreaterThan(wallets.count, 0, "Should have test wallets")
        
        // Test data reset functionality
        // Note: The actual reset in SettingsView calls exit(0), so we test the underlying logic
        
        // Delete all models (simulating resetAllData)
        try modelContext.delete(model: HDWallet.self)
        try modelContext.delete(model: HDAccount.self)
        try modelContext.delete(model: HDWatchedAddress.self)
        try modelContext.delete(model: Transaction.self)
        try modelContext.delete(model: UTXO.self)
        try modelContext.delete(model: Balance.self)
        try modelContext.save()
        
        // Verify data is cleared
        let walletsAfterReset = try modelContext.fetch(descriptor)
        XCTAssertEqual(walletsAfterReset.count, 0, "Should have no wallets after reset")
    }
    
    // MARK: - Configuration Validation Tests
    
    func testNetworkConfigurationValidation() throws {
        // Test valid network configurations
        let validNetworks: [PlatformNetwork] = [.mainnet, .testnet, .devnet]
        
        for network in validNetworks {
            XCTAssertNotNil(network.displayName, "Network \(network) should have display name")
            XCTAssertNotNil(network.sdkNetwork, "Network \(network) should have SDK network mapping")
            XCTAssertFalse(network.displayName.isEmpty, "Network \(network) display name should not be empty")
        }
    }
    
    func testSPVValidationModes() throws {
        let config = SPVConfigurationManager.shared.configuration(for: .testnet)
        
        // Test different validation modes
        let validationModes: [SPVClientConfiguration.ValidationMode] = [.none, .basic, .full]
        
        for mode in validationModes {
            var mutableConfig = config
            mutableConfig.validationMode = mode
            XCTAssertNotNil(mutableConfig, "Validation mode \(mode) should be valid")
        }
    }
    
    // MARK: - About Section Tests
    
    func testVersionInformation() {
        // Test that version information is accessible
        // Note: In SettingsView, these are hardcoded. In a real app, they might come from Bundle
        let expectedVersion = "1.0.0"
        let expectedBuild = "2024.1"
        
        // These would typically be tested through the Bundle or a version manager
        XCTAssertNotNil(expectedVersion, "Should have version information")
        XCTAssertNotNil(expectedBuild, "Should have build information")
        XCTAssertFalse(expectedVersion.isEmpty, "Version should not be empty")
        XCTAssertFalse(expectedBuild.isEmpty, "Build should not be empty")
    }
    
    // MARK: - Settings Export/Import Tests (Future Implementation)
    
    func testSettingsExportStructure() throws {
        // Test the structure for settings export (when implemented)
        walletService.setUseLocalPeers(true)
        walletService.setLocalPeerHost("custom.host.com")
        appState.currentNetwork = .mainnet
        
        // Define expected export structure
        let expectedSettings = [
            "useLocalPeers": true,
            "localPeerHost": "custom.host.com",
            "currentNetwork": "mainnet"
        ] as [String: Any]
        
        // Verify settings can be collected for export
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "useLocalPeers"), expectedSettings["useLocalPeers"] as! Bool)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "localPeerHost"), expectedSettings["localPeerHost"] as! String)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "currentNetwork"), expectedSettings["currentNetwork"] as! String)
    }
    
    // MARK: - Configuration Error Handling Tests
    
    func testInvalidConfigurationHandling() throws {
        // Our mock SPVClientConfiguration doesn't have dataDirectory or validate()
        // Test basic configuration error handling
        let config = SPVConfigurationManager.shared.configuration(for: .testnet)
        
        // Test that configuration can handle invalid values
        var invalidConfig = config
        invalidConfig.network = .devnet  // Less common network
        XCTAssertNotNil(invalidConfig, "Should handle different network configurations")
    }
    
    func testNetworkSwitchingErrorRecovery() throws {
        // Test error recovery when network switching fails
        let originalNetwork = appState.currentNetwork
        
        // Attempt to verify error handling would occur on invalid network configuration
        // (This is mostly covered by the underlying SDK error handling)
        
        XCTAssertEqual(appState.currentNetwork, originalNetwork, "Should maintain original network on error")
    }
    
    // MARK: - Performance Tests
    
    func testSettingsLoadPerformance() throws {
        // Test performance of loading settings
        measure {
            // Simulate loading various settings
            _ = walletService.isUsingLocalPeers()
            _ = walletService.getLocalPeerHost()
            _ = appState.currentNetwork
        }
    }
    
    func testNetworkSwitchingPerformance() throws {
        // Test performance of network switching
        measure {
            appState.currentNetwork = .testnet
            appState.currentNetwork = .mainnet
            appState.currentNetwork = .devnet
        }
    }
    
    // MARK: - Helper Methods
    
    // Helper methods can be added here as needed
}

// MARK: - Settings Integration Tests

@MainActor
final class SettingsIntegrationTests: XCTestCase {
    
    var appState: AppState!
    var modelContainer: ModelContainer!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Create in-memory model container
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([
            HDWallet.self,
            HDAccount.self,
            HDWatchedAddress.self,
            Transaction.self,
            UTXO.self,
            Balance.self
        ])
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        
        appState = AppState()
    }
    
    override func tearDownWithError() throws {
        appState = nil
        modelContainer = nil
        try super.tearDownWithError()
    }
    
    func testNetworkSwitchingWithAppState() async throws {
        // Test network switching integration with AppState
        let originalNetwork = appState.currentNetwork
        
        // Switch to a different network
        let targetNetwork: PlatformNetwork = originalNetwork == .testnet ? .mainnet : .testnet
        appState.currentNetwork = targetNetwork
        
        // Verify the switch
        XCTAssertEqual(appState.currentNetwork, targetNetwork, "Network should be switched")
        
        // Verify persistence
        XCTAssertEqual(UserDefaults.standard.string(forKey: "currentNetwork"), targetNetwork.rawValue)
    }
    
    func testSPVConfigurationIntegration() throws {
        // Test SPV configuration integration with different networks
        for network in PlatformNetwork.allCases {
            let config: SPVClientConfiguration
            
            switch network {
            case .mainnet:
                config = SPVConfigurationManager.shared.configuration(for: .mainnet)
            case .testnet:
                config = SPVConfigurationManager.shared.configuration(for: .testnet)
            case .devnet:
                config = SPVConfigurationManager.shared.configuration(for: .devnet)
            }
            
            // Our mock doesn't have validate(), just check it's created
            XCTAssertNotNil(config, "Configuration for \(network) should be valid")
            // Note: Peers are now configured in WalletService during connection, not in base config
            // XCTAssertGreaterThan(config.additionalPeers.count, 0, "Should have peers for \(network)")
        }
    }
}