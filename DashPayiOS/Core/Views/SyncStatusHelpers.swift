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
            return "network"
        case .downloadingHeaders:
            return "arrow.down.circle"
        case .downloadingFilters:
            return "line.3.horizontal.decrease.circle"
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
            return "Idle"
        case .connecting:
            return "Connecting"
        case .downloadingHeaders:
            return "Downloading Headers"
        case .downloadingFilters:
            return "Downloading Filters"
        case .scanning:
            return "Scanning"
        case .synced:
            return "Synced"
        case .error:
            return "Error"
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