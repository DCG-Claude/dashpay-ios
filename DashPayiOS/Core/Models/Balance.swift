import Foundation
import SwiftData
import SwiftDashCoreSDK

// Local Balance model for DashPayiOS
// This is separate from SwiftDashCoreSDK.Balance to avoid SwiftData conflicts
@Model
final class LocalBalance {
    var confirmed: UInt64
    var pending: UInt64
    var instantLocked: UInt64
    var mempool: UInt64
    var mempoolInstant: UInt64
    var total: UInt64
    var lastUpdated: Date
    
    init(
        confirmed: UInt64 = 0,
        pending: UInt64 = 0,
        instantLocked: UInt64 = 0,
        mempool: UInt64 = 0,
        mempoolInstant: UInt64 = 0,
        total: UInt64 = 0,
        lastUpdated: Date = .now
    ) {
        self.confirmed = confirmed
        self.pending = pending
        self.instantLocked = instantLocked
        self.mempool = mempool
        self.mempoolInstant = mempoolInstant
        self.total = total
        self.lastUpdated = lastUpdated
    }
    
    // Create from SDK Balance - static factory method
    static func from(_ sdkBalance: SwiftDashCoreSDK.Balance) -> LocalBalance {
        return LocalBalance(
            confirmed: sdkBalance.confirmed,
            pending: sdkBalance.pending,
            instantLocked: sdkBalance.instantLocked,
            mempool: sdkBalance.mempool,
            mempoolInstant: sdkBalance.mempoolInstant ?? 0,
            total: sdkBalance.total,
            lastUpdated: sdkBalance.lastUpdated
        )
    }
    
    // Update from SDK Balance
    func update(from sdkBalance: SwiftDashCoreSDK.Balance) {
        self.confirmed = sdkBalance.confirmed
        self.pending = sdkBalance.pending
        self.instantLocked = sdkBalance.instantLocked
        self.mempool = sdkBalance.mempool
        self.mempoolInstant = sdkBalance.mempoolInstant ?? 0
        self.total = sdkBalance.total
        self.lastUpdated = sdkBalance.lastUpdated
    }
    
    // Update from another LocalBalance
    func update(from other: LocalBalance) {
        self.confirmed = other.confirmed
        self.pending = other.pending
        self.instantLocked = other.instantLocked
        self.mempool = other.mempool
        self.mempoolInstant = other.mempoolInstant
        self.total = other.total
        self.lastUpdated = other.lastUpdated
    }
    
    // Computed properties
    var available: UInt64 {
        return confirmed + instantLocked + mempoolInstant
    }
    
    var unconfirmed: UInt64 {
        return pending
    }
}

// MARK: - Formatting Extensions
extension LocalBalance {
    var formattedConfirmed: String {
        return DashFormatting.formatDash(confirmed)
    }
    
    var formattedPending: String {
        return DashFormatting.formatDash(pending)
    }
    
    var formattedInstantLocked: String {
        return DashFormatting.formatDash(instantLocked)
    }
    
    var formattedTotal: String {
        return DashFormatting.formatDash(total)
    }
    
    var formattedMempool: String {
        return DashFormatting.formatDash(mempool)
    }
    
    var formattedMempoolInstant: String {
        return DashFormatting.formatDash(mempoolInstant)
    }
    
    var formattedAvailable: String {
        return DashFormatting.formatDash(available)
    }
}