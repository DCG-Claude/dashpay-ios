import Foundation

// MARK: - Sync Progress Types

public enum SyncStage: CaseIterable, Codable {
    case connecting
    case queryingHeight
    case downloading
    case validating
    case storing
    case complete
    case failed
    
    public var description: String {
        switch self {
        case .connecting: return "Connecting to network"
        case .queryingHeight: return "Querying blockchain height"
        case .downloading: return "Downloading headers"
        case .validating: return "Validating data"
        case .storing: return "Storing data"
        case .complete: return "Sync complete"
        case .failed: return "Sync failed"
        }
    }
    
    public var icon: String {
        switch self {
        case .connecting: return "network"
        case .queryingHeight: return "magnifyingglass"
        case .downloading: return "arrow.down.circle"
        case .validating: return "checkmark.shield"
        case .storing: return "folder.badge.plus"
        case .complete: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
    
    public var isActive: Bool {
        switch self {
        case .connecting, .queryingHeight, .downloading, .validating, .storing: return true
        case .complete, .failed: return false
        }
    }
}

public struct DetailedSyncProgress: Codable, Equatable {
    public let currentHeight: UInt32
    public let totalHeight: UInt32
    public let percentage: Double
    public let headersPerSecond: Double
    public let estimatedSecondsRemaining: UInt32
    public let stage: SyncStage
    public let stageMessage: String
    public let connectedPeers: UInt32
    public let totalHeadersProcessed: UInt64
    public let syncStartTimestamp: Date
    
    public init(
        currentHeight: UInt32,
        totalHeight: UInt32,
        percentage: Double,
        headersPerSecond: Double,
        estimatedSecondsRemaining: UInt32,
        stage: SyncStage,
        stageMessage: String,
        connectedPeers: UInt32,
        totalHeadersProcessed: UInt64,
        syncStartTimestamp: Date
    ) {
        self.currentHeight = currentHeight
        self.totalHeight = totalHeight
        self.percentage = percentage
        self.headersPerSecond = headersPerSecond
        self.estimatedSecondsRemaining = estimatedSecondsRemaining
        self.stage = stage
        self.stageMessage = stageMessage
        self.connectedPeers = connectedPeers
        self.totalHeadersProcessed = totalHeadersProcessed
        self.syncStartTimestamp = syncStartTimestamp
    }
    
    public var formattedPercentage: String {
        return String(format: "%.1f%%", percentage)
    }
    
    public var formattedSpeed: String {
        return String(format: "%.0f headers/sec", headersPerSecond)
    }
    
    public var formattedTimeRemaining: String {
        if estimatedSecondsRemaining == 0 {
            return "Unknown"
        }
        
        let minutes = estimatedSecondsRemaining / 60
        let seconds = estimatedSecondsRemaining % 60
        
        if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}