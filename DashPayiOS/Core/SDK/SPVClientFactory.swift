import Foundation
import Combine
import SwiftDashCoreSDK

/// Factory for creating SPV client instances
public class SPVClientFactory {
    public enum ClientType {
        case real
        case mock
        case auto // Automatically choose based on FFI availability
    }
    
    /// Create an SPV client instance
    /// - Parameters:
    ///   - configuration: SPV client configuration
    ///   - type: The type of client to create
    /// - Returns: An SPV client instance (either real or mock)
    public static func createClient(
        configuration: SPVClientConfiguration,
        type: ClientType = .auto
    ) -> SPVClient {
        // Always return real SPVClient for now
        // TODO: Re-enable mock client when protocol issues are resolved
        switch type {
        case .real, .mock, .auto:
            if type == .mock {
                print("⚠️ SPVClientFactory: Mock client requested but not available, using real client")
            }
            print("🚀 SPVClientFactory: Creating real SPVClient")
            return SPVClient(configuration: configuration)
        }
    }
    
    /// Create a client with default configuration
    public static func createDefaultClient(type: ClientType = .auto) -> SPVClient {
        let config = SPVClientConfiguration.testnet()
        return createClient(configuration: config, type: type)
    }
}

// TODO: Protocol abstraction temporarily disabled due to compiler issues
// Will revisit when SDK protocol conformance is resolved

/// Environment configuration for SPV
public struct SPVEnvironment {
    public static var useMockClient: Bool {
        #if DEBUG
        // Check for test environment or specific flag - only available in debug builds
        return ProcessInfo.processInfo.environment["USE_MOCK_SPV"] == "1"
        #else
        // Never use mock client in production builds
        return false
        #endif
    }
    
    public static var ffiTimeout: TimeInterval {
        #if DEBUG
        return 2.0 // Shorter timeout in debug
        #else
        return 5.0 // Longer timeout in release
        #endif
    }
}