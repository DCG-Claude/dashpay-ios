import Foundation
import Combine
import os.log
import SwiftDashSDK
import SwiftDashCoreSDK

/// Service responsible for managing connection state and related functionality
@MainActor
class ConnectionStateService: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var sdk: DashSDK?
    
    private let logger = Logger(subsystem: "com.dash.wallet", category: "ConnectionStateService")
    private var cancellables = Set<AnyCancellable>()
    
    /// Set connection state
    func setConnected(_ connected: Bool) {
        logger.info("🔗 Connection state changed: \(connected)")
        isConnected = connected
    }
    
    /// Set SDK instance
    func setSDK(_ sdk: DashSDK?) {
        logger.info("🔧 SDK instance updated: \(sdk != nil ? "Available" : "Nil")")
        self.sdk = sdk
    }
    
    /// Check if SDK is available and connected
    func isSDKReady() -> Bool {
        return sdk != nil && isConnected
    }
    
    /// Get current SDK instance
    func getCurrentSDK() -> DashSDK? {
        return sdk
    }
    
    /// Reset connection state
    func reset() {
        logger.info("🔄 Resetting connection state")
        isConnected = false
        sdk = nil
    }
}