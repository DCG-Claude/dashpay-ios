import Foundation

/// Network configuration constants for Dash networks
/// Note: Peer discovery and connection management is now handled automatically by rust-dashcore SPV client
struct NetworkConstants {
    
    // MARK: - Connection Settings
    
    /// Default connection timeout in seconds
    static let connectionTimeout: TimeInterval = 30.0
}
