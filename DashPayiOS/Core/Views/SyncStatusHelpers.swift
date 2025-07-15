import SwiftUI

// MARK: - SyncStatus enum and extensions

public enum SyncStatus: CaseIterable, Equatable {
    case idle
    case connecting
    case downloadingHeaders
    case downloadingFilters
    case scanning
    case synced
    case error
}

extension SyncStatus {
    var icon: String {
        switch self {
        case .idle:
            return "circle"
        case .connecting:
            if #available(iOS 13.0, *) {
                return "network"
            } else {
                return "wifi"
            }
        case .downloadingHeaders:
            return "arrow.down.circle"
        case .downloadingFilters:
            if #available(iOS 15.0, *) {
                return "line.3.horizontal.decrease.circle"
            } else {
                return "slider.horizontal.below.rectangle"
            }
        case .scanning:
            return "magnifyingglass.circle"
        case .synced:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .idle:
            return .gray
        case .connecting, .downloadingHeaders, .downloadingFilters, .scanning:
            return .blue
        case .synced:
            return .green
        case .error:
            return .red
        }
    }
    
    var description: String {
        switch self {
        case .idle:
            return NSLocalizedString("sync_status_idle", comment: "Sync status when idle")
        case .connecting:
            return NSLocalizedString("sync_status_connecting", comment: "Sync status when connecting")
        case .downloadingHeaders:
            return NSLocalizedString("sync_status_downloading_headers", comment: "Sync status when downloading headers")
        case .downloadingFilters:
            return NSLocalizedString("sync_status_downloading_filters", comment: "Sync status when downloading filters")
        case .scanning:
            return NSLocalizedString("sync_status_scanning", comment: "Sync status when scanning")
        case .synced:
            return NSLocalizedString("sync_status_synced", comment: "Sync status when synced")
        case .error:
            return NSLocalizedString("sync_status_error", comment: "Sync status when error occurred")
        }
    }
    
    var isActive: Bool {
        switch self {
        case .connecting, .downloadingHeaders, .downloadingFilters, .scanning:
            return true
        case .idle, .synced, .error:
            return false
        }
    }
}