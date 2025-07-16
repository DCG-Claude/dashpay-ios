import XCTest
@testable import DashPay
import SwiftDashCoreSDK

@MainActor
final class UnifiedStateManagerTests: XCTestCase {
    var stateManager: UnifiedStateManager!
    var mockCoreSDK: MockDashSDK!
    var mockPlatformWrapper: PlatformSDKWrapper?
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create mocks
        mockCoreSDK = MockDashSDK()
        
        // Create state manager with mocks
        stateManager = UnifiedStateManager(
            coreSDK: mockCoreSDK,
            platformWrapper: nil
        )
    }
    
    func test_initialState() async throws {
        // Test initial state
        XCTAssertFalse(stateManager.isLoading)
        XCTAssertNil(stateManager.error)
        XCTAssertEqual(stateManager.unifiedBalance.coreBalance, 0)
        XCTAssertEqual(stateManager.unifiedBalance.platformCredits, 0)
        XCTAssertTrue(stateManager.wallets.isEmpty)
        XCTAssertTrue(stateManager.identities.isEmpty)
    }
    
    func test_balanceUpdate() async throws {
        // Test balance update directly
        let testBalance: UInt64 = 100_000_000
        
        // Update balance directly
        stateManager.updateCoreBalance(testBalance)
        
        // Verify balance was updated
        XCTAssertEqual(stateManager.unifiedBalance.coreBalance, testBalance)
        
        // Test platform credits update
        let testCredits: UInt64 = 50_000_000
        stateManager.updatePlatformCredits(testCredits)
        
        XCTAssertEqual(stateManager.unifiedBalance.platformCredits, testCredits)
    }
    
    func test_createIdentityFlow() async throws {
        // Set up test wallet
        stateManager.initializeWithMockWallet()
        
        // Test identity creation flow
        let amount: UInt64 = 100_000_000 // 1 DASH
        let wallet = stateManager.wallets.first!
        
        do {
            // Since we don't have platform wrapper in test, this will fail
            let identity = try await stateManager.createFundedIdentity(
                from: wallet,
                amount: amount
            )
            
            XCTFail("Expected error due to missing platform wrapper")
        } catch {
            // Expected - platform wrapper is nil in test setup
            XCTAssertTrue(error is PlatformError)
        }
    }
    
    func test_errorHandling() async throws {
        // Test error state management
        XCTAssertNil(stateManager.error)
        
        // Trigger an error by trying to create identity without platform wrapper
        stateManager.initializeWithMockWallet()
        let wallet = stateManager.wallets.first!
        
        do {
            _ = try await stateManager.createFundedIdentity(
                from: wallet,
                amount: 100_000_000
            )
        } catch {
            // Error should be set on the state manager
            XCTAssertNotNil(stateManager.error)
        }
    }
}