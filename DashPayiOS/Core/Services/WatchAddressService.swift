import Foundation
import Combine
import os.log
import SwiftDashCoreSDK

/// Errors that can occur when watching addresses
enum WatchAddressError: Error, LocalizedError, Identifiable {
    case invalidAddress(String)
    case networkError(String)
    case storageFailure(String)
    case unknownError(String)
    
    var id: String {
        switch self {
        case .invalidAddress(let address):
            return "invalid_\(address.hashValue)"
        case .networkError(let message):
            return "network_\(message.hashValue)"
        case .storageFailure(let message):
            return "storage_\(message.hashValue)"
        case .unknownError(let message):
            return "unknown_\(message.hashValue)"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .invalidAddress(let address):
            return "Invalid address: \(address)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .storageFailure(let message):
            return "Storage failure: \(message)"
        case .unknownError(let message):
            return "Unknown error: \(message)"
        }
    }
    
    /// Indicates whether this error is recoverable with a retry
    var isRecoverable: Bool {
        switch self {
        case .invalidAddress:
            return false // Invalid addresses won't become valid on retry
        case .networkError, .storageFailure, .unknownError:
            return true // These might be recoverable
        }
    }
}

/// Service responsible for managing watch address functionality
@MainActor
class WatchAddressService: ObservableObject {
    @Published var watchAddressErrors: [WatchAddressError] = []
    @Published var pendingWatchCount: Int = 0
    @Published var watchVerificationStatus: WatchVerificationStatus = .unknown
    
    /// Configurable timer interval for watch verification (default: 60 seconds)
    var watchVerificationInterval: TimeInterval = 60.0
    
    private let logger = Logger(subsystem: "com.dash.wallet", category: "WatchAddressService")
    private var pendingWatchAddresses: [String: [(address: String, error: Error)]] = [:]
    private var watchVerificationTimer: Timer?
    private var currentVerificationTask: Task<Void, Never>?
    
    /// Deinitializer to ensure proper cleanup of timer and tasks
    deinit {
        watchVerificationTimer?.invalidate()
        currentVerificationTask?.cancel()
    }
    
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
        let interval = self.watchVerificationInterval
        logger.info("⏰ Starting watch verification timer with interval: \(interval)s")
        watchVerificationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Cancel any previous verification task before starting a new one
            Task { @MainActor in
                self.currentVerificationTask?.cancel()
                
                self.currentVerificationTask = Task {
                    await verificationHandler()
                }
            }
        }
    }
    
    /// Stop watch verification timer
    func stopWatchVerification() {
        logger.info("⏸️ Stopping watch verification timer")
        watchVerificationTimer?.invalidate()
        watchVerificationTimer = nil
        currentVerificationTask?.cancel()
        currentVerificationTask = nil
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