import Foundation
import Network

/// Network configuration constants for Dash networks
enum NetworkConstants {
    
    // MARK: - Testnet Configuration
    
    /// DNS seed addresses for testnet peer discovery
    static let testnetDNSSeeds = [
        "testnet-seed.dash.org",
        "testnet.dnsseed.dash.org",
        "seed.testnet.networks.dash.org"
    ]
    
    /// Fallback testnet peer addresses for initial connection when DNS seeds fail
    static let fallbackTestnetPeers = [
        "54.149.33.167:19999",
        "35.90.252.3:19999", 
        "18.237.170.32:19999",
        "34.220.243.24:19999",
        "34.214.48.68:19999"
    ]
    
    /// Testnet port for peer connections
    static let testnetPort = 19999
    
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
    
    // MARK: - Peer Discovery
    
    /// Discovers testnet peers using DNS seeds with fallback to hardcoded peers
    /// Returns an array of peer addresses in "host:port" format
    static func discoverTestnetPeers() async -> [String] {
        // Try DNS seed discovery first
        let discoveredPeers = await resolveDNSSeeds(testnetDNSSeeds, port: testnetPort)
        
        if !discoveredPeers.isEmpty {
            // Limit to reasonable number and shuffle for load distribution
            let shuffledPeers = Array(discoveredPeers.shuffled().prefix(8))
            print("📡 Discovered \(shuffledPeers.count) testnet peers via DNS seeds")
            return shuffledPeers
        } else {
            // Fallback to hardcoded peers if DNS discovery fails
            print("⚠️ DNS seed discovery failed, using fallback testnet peers")
            return fallbackTestnetPeers
        }
    }
    
    /// Resolves DNS seeds to IP addresses
    private static func resolveDNSSeeds(_ seeds: [String], port: Int) async -> [String] {
        var resolvedPeers: [String] = []
        
        await withTaskGroup(of: [String].self) { group in
            for seed in seeds {
                group.addTask {
                    await resolveDNSSeed(seed, port: port)
                }
            }
            
            for await seedPeers in group {
                resolvedPeers.append(contentsOf: seedPeers)
            }
        }
        
        // Remove duplicates and return
        return Array(Set(resolvedPeers))
    }
    
    /// Resolves a single DNS seed to IP addresses
    private static func resolveDNSSeed(_ seed: String, port: Int) async -> [String] {
        return await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(seed)
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = false
            
            let connection = NWConnection(host: host, port: NWEndpoint.Port(integerLiteral: UInt16(port)), using: parameters)
            
            // Use a timeout for DNS resolution
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                connection.cancel()
                continuation.resume(returning: [])
            }
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let resolvedHost, _) = connection.endpoint {
                        let peerAddress = "\(resolvedHost):\(port)"
                        connection.cancel()
                        continuation.resume(returning: [peerAddress])
                    } else {
                        connection.cancel()
                        continuation.resume(returning: [])
                    }
                case .failed(_), .cancelled:
                    continuation.resume(returning: [])
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
        }
    }
}