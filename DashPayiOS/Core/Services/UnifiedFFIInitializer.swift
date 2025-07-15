import Foundation
import SwiftDashCoreSDK

/// Unified SDK specific errors
enum UnifiedSDKError: LocalizedError {
    case notInitialized
    case registrationFailed(String)
    case initializationFailed(String)
    case invalidConfiguration
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Unified SDK not initialized"
        case .registrationFailed(let error):
            return "Failed to register Core SDK: \(error)"
        case .initializationFailed(let error):
            return "Failed to initialize unified SDK: \(error)"
        case .invalidConfiguration:
            return "Invalid configuration provided"
        }
    }
}

/// Manages unified SDK initialization and Core SDK integration
@MainActor
final class UnifiedSDKInitializer: @unchecked Sendable {
    static let shared = UnifiedSDKInitializer()
    private var dashSDK: DashSDK?
    private var isInitialized = false
    
    private init() {}
    
    deinit {
        // Cleanup will be handled when MainActor releases the instance
        if isInitialized {
            dashSDK = nil
            print("🧹 Unified SDK cleaned up in deinit")
        }
    }
    
    /// Initialize the unified SDK with configuration
    func initialize(network: DashNetwork = .testnet) async throws {
        guard !isInitialized else { 
            return
        }
        
        do {
            // Create SDK configuration using the configuration manager
            let config = try SPVConfigurationManager.shared.configuration(for: .testnet)
            
            // Create SDK instance - DashSDK handles FFI initialization internally
            self.dashSDK = try DashSDK(configuration: config)
            self.isInitialized = true
            
            print("✅ Unified SDK initialized successfully")
        } catch {
            print("❌ Failed to initialize unified SDK: \(error)")
            throw UnifiedSDKError.initializationFailed(error.localizedDescription)
        }
    }
    
    /// Get the initialized SDK instance
    func getSDK() throws -> DashSDK {
        guard isInitialized, let sdk = dashSDK else {
            throw UnifiedSDKError.notInitialized
        }
        return sdk
    }
    
    /// Connect the SDK to the network
    func connect() async throws {
        let sdk = try getSDK()
        try await sdk.connect()
        print("✅ SDK connected to network successfully")
    }
    
    /// Disconnect from the network
    func disconnect() async throws {
        let sdk = try getSDK()
        try await sdk.disconnect()
        print("🔌 SDK disconnected from network")
    }
    
    /// Cleanup resources and reset initialization state
    func cleanup() {
        if isInitialized {
            // SwiftDashCoreSDK handles cleanup internally
            dashSDK = nil
            isInitialized = false
            print("🧹 Unified SDK cleaned up")
        }
    }
}

// MARK: - Compatibility Alias
/// Alias for backwards compatibility with existing code
typealias UnifiedFFIInitializer = UnifiedSDKInitializer