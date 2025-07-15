import Foundation
import Combine
import os.log
import SwiftDashCoreSDK

/// Service responsible for managing watch address functionality
@MainActor
class WatchAddressService: ObservableObject {
    @Published var watchAddressErrors: [WatchAddressError] = []
    @Published var pendingWatchCount: Int = 0
    @Published var watchVerificationStatus: WatchVerificationStatus = .unknown
    
    private let logger = Logger(subsystem: "com.dash.wallet", category: "WatchAddressService")
    private var pendingWatchAddresses: [String: [(address: String, error: Error)]] = [:]
    private var watchVerificationTimer: Timer?
    
    /// Handle failed watch addresses
    func handleFailedWatchAddresses(_ failures: [(address: String, error: Error)], accountId: String) {
        logger.info("⚠️ Handling \(failures.count) failed watch addresses for account \(accountId)")
        
        // Store failed addresses for retry
        pendingWatchAddresses[accountId] = failures
        
        // Update pending watch count
        pendingWatchCount = pendingWatchAddresses.values.reduce(0) { $0 + $1.count }
        
        // Update watch address errors
        watchAddressErrors = failures.map { _, error in
            if let watchError = error as? WatchAddressError {
                return watchError
            } else {
                return WatchAddressError.unknownError(error.localizedDescription)
            }
        }
        
        logger.info("📊 Updated pending watch count: \(self.pendingWatchCount)")
    }
    
    /// Remove pending watch addresses for an account
    func removePendingWatchAddresses(for accountId: String) {
        pendingWatchAddresses.removeValue(forKey: accountId)
        pendingWatchCount = pendingWatchAddresses.values.reduce(0) { $0 + $1.count }
        logger.info("✅ Removed pending watch addresses for account \(accountId)")
    }
    
    /// Update watch verification status
    func updateVerificationStatus(_ status: WatchVerificationStatus) {
        watchVerificationStatus = status
        logger.info("📊 Watch verification status updated: \(String(describing: status))")
    }
    
    /// Start watch verification timer
    func startWatchVerification(verificationHandler: @escaping () async -> Void) {
        logger.info("⏰ Starting watch verification timer")
        watchVerificationTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            Task {
                await verificationHandler()
            }
        }
    }
    
    /// Stop watch verification timer
    func stopWatchVerification() {
        logger.info("⏸️ Stopping watch verification timer")
        watchVerificationTimer?.invalidate()
        watchVerificationTimer = nil
    }
    
    /// Get pending watch addresses for an account
    func getPendingWatchAddresses(for accountId: String) -> [(address: String, error: Error)]? {
        return pendingWatchAddresses[accountId]
    }
    
    /// Reset watch address state
    func reset() {
        logger.info("🔄 Resetting watch address state")
        stopWatchVerification()
        watchAddressErrors.removeAll()
        pendingWatchCount = 0
        watchVerificationStatus = .unknown
        pendingWatchAddresses.removeAll()
    }
}