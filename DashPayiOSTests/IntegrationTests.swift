import XCTest
@testable import DashPay
import SwiftDashCoreSDK

final class IntegrationTests: XCTestCase {
    
    func test_bothSDKsInitialize() async throws {
        // Test Core SDK
        let config = SPVClientConfiguration.testnet()
        let coreSDK = try await Task { @MainActor in
            try DashSDK(configuration: config)
        }.value
        XCTAssertNotNil(coreSDK)
        
        // Test Platform SDK wrapper
        let coreConfig = SPVClientConfiguration.testnet()
        let coreSDK2 = try await Task { @MainActor in
            try DashSDK(configuration: coreConfig)
        }.value
        let platformWrapper = try await Task { @MainActor in
            try PlatformSDKWrapper(network: .testnet, coreSDK: coreSDK2)
        }.value
        XCTAssertNotNil(platformWrapper)
    }
    
    @MainActor
    func test_unifiedAppStateInitializes() async throws {
        let appState = UnifiedAppState()
        await appState.initialize()
        
        await MainActor.run {
            XCTAssertTrue(appState.isInitialized)
            XCTAssertNil(appState.error)
        }
    }
}