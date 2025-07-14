import Foundation

/// Network configuration constants for Dash networks
enum NetworkConstants {
    
    // MARK: - Testnet Configuration
    
    /// Fallback testnet peer addresses for initial connection
    static let fallbackTestnetPeers = [
        "54.149.33.167:19999",
        "35.90.252.3:19999", 
        "18.237.170.32:19999",
        "34.220.243.24:19999",
        "34.214.48.68:19999"
    ]
    
    /// Primary testnet peer for basic configuration
    /// This peer is used as a fallback when no other peers are configured
    static let primaryTestnetPeer = "54.149.33.167:19999"
    
    // MARK: - Mainnet Configuration
    
    /// Fallback mainnet peer addresses for initial connection  
    static let fallbackMainnetPeers = [
        "142.93.154.186:9999",
        "8.219.251.8:9999",
        "165.22.30.195:9999",
        "65.109.114.212:9999",
        "188.40.21.248:9999",
        "66.42.58.154:9999"
    ]
    
    // MARK: - Connection Settings
    
    /// Maximum number of peers to connect to
    static let maxPeers: UInt32 = 12
    
    /// Default connection timeout in seconds
    static let connectionTimeout: TimeInterval = 30.0
}