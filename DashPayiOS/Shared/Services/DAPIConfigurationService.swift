import Foundation
import Network

/// Service responsible for fetching and managing DAPI endpoint configurations
actor DAPIConfigurationService {
    
    // MARK: - Configuration Sources
    
    /// Configuration source types
    enum ConfigurationSource {
        case remote(URL)
        case plist(String)
        case environment(String)
    }
    
    /// Default configuration sources by network
    private static let defaultConfigurationSources: [PlatformNetwork: ConfigurationSource] = [
        .testnet: .remote(URL(string: "https://config.dash.org/testnet/dapi-endpoints.json")!),
        .mainnet: .remote(URL(string: "https://config.dash.org/mainnet/dapi-endpoints.json")!),
        .devnet: .environment("DAPI_ENDPOINTS_DEVNET")
    ]
    
    // MARK: - Properties
    
    private let network: PlatformNetwork
    private let configurationSource: ConfigurationSource
    private var cachedEndpoints: [String] = []
    private var lastFetchTime: Date?
    private let cacheTimeout: TimeInterval = 300 // 5 minutes
    private let urlSession: URLSession
    
    // MARK: - Initialization
    
    init(network: PlatformNetwork, configurationSource: ConfigurationSource? = nil) {
        self.network = network
        self.configurationSource = configurationSource ?? Self.defaultConfigurationSources[network] ?? .environment("DAPI_ENDPOINTS")
        
        // Configure URL session with timeout
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10.0
        configuration.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: configuration)
    }
    
    // MARK: - Public Methods
    
    /// Fetch DAPI endpoints for the configured network
    func fetchDAPIEndpoints() async throws -> [String] {
        // Check cache first
        if let cachedEndpoints = getCachedEndpoints() {
            print("📋 Using cached DAPI endpoints: \(cachedEndpoints.count) endpoints")
            return cachedEndpoints
        }
        
        print("🔄 Fetching DAPI endpoints from source...")
        
        let endpoints = try await fetchFromSource()
        
        // Cache the result
        cachedEndpoints = endpoints
        lastFetchTime = Date()
        
        print("✅ Fetched \(endpoints.count) DAPI endpoints")
        return endpoints
    }
    
    /// Clear cached endpoints and force refresh
    func refreshEndpoints() async throws -> [String] {
        cachedEndpoints = []
        lastFetchTime = nil
        return try await fetchDAPIEndpoints()
    }
    
    // MARK: - Private Methods
    
    private func getCachedEndpoints() -> [String]? {
        guard !cachedEndpoints.isEmpty,
              let lastFetch = lastFetchTime,
              Date().timeIntervalSince(lastFetch) < cacheTimeout else {
            return nil
        }
        return cachedEndpoints
    }
    
    private func fetchFromSource() async throws -> [String] {
        switch configurationSource {
        case .remote(let url):
            return try await fetchFromRemoteURL(url)
        case .plist(let filename):
            return try fetchFromPlist(filename)
        case .environment(let envVar):
            return try fetchFromEnvironment(envVar)
        }
    }
    
    private func fetchFromRemoteURL(_ url: URL) async throws -> [String] {
        print("🌐 Fetching DAPI endpoints from remote URL: \(url)")
        
        let (data, response) = try await urlSession.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DAPIConfigurationError.remoteConfigurationUnavailable
        }
        
        // Parse JSON response
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let config = jsonObject as? [String: Any],
              let endpoints = config["endpoints"] as? [String] else {
            throw DAPIConfigurationError.invalidConfigurationFormat
        }
        
        // Validate endpoints
        let validEndpoints = endpoints.compactMap { endpoint -> String? in
            guard URL(string: endpoint) != nil else {
                print("⚠️ Invalid endpoint URL: \(endpoint)")
                return nil
            }
            return endpoint
        }
        
        guard !validEndpoints.isEmpty else {
            throw DAPIConfigurationError.noValidEndpoints
        }
        
        return validEndpoints
    }
    
    private func fetchFromPlist(_ filename: String) throws -> [String] {
        print("📄 Fetching DAPI endpoints from plist: \(filename)")
        
        guard let path = Bundle.main.path(forResource: filename, ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let endpoints = plist["DAPIEndpoints"] as? [String] else {
            throw DAPIConfigurationError.plistConfigurationNotFound
        }
        
        return endpoints
    }
    
    private func fetchFromEnvironment(_ envVar: String) throws -> [String] {
        print("🔧 Fetching DAPI endpoints from environment variable: \(envVar)")
        
        guard let envValue = ProcessInfo.processInfo.environment[envVar] else {
            throw DAPIConfigurationError.environmentVariableNotSet
        }
        
        // Parse comma-separated endpoints
        let endpoints = envValue.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard !endpoints.isEmpty else {
            throw DAPIConfigurationError.noValidEndpoints
        }
        
        return endpoints
    }
    
    // MARK: - Fallback Configuration
    
    /// Get fallback endpoints for emergency use
    func getFallbackEndpoints() -> [String] {
        switch network {
        case .testnet:
            return [
                "https://seed-1.testnet.networks.dash.org:1443",
                "https://seed-2.testnet.networks.dash.org:1443",
                "https://seed-3.testnet.networks.dash.org:1443"
            ]
        case .mainnet:
            return [
                "https://dapi.dash.org:443",
                "https://seed-1.evonet.networks.dash.org:1443"
            ]
        case .devnet:
            return [
                "http://127.0.0.1:3000",
                "http://127.0.0.1:3001"
            ]
        }
    }
}

// MARK: - Error Types

enum DAPIConfigurationError: LocalizedError {
    case remoteConfigurationUnavailable
    case invalidConfigurationFormat
    case noValidEndpoints
    case plistConfigurationNotFound
    case environmentVariableNotSet
    case networkUnavailable
    
    var errorDescription: String? {
        switch self {
        case .remoteConfigurationUnavailable:
            return "Remote DAPI configuration is unavailable"
        case .invalidConfigurationFormat:
            return "Invalid DAPI configuration format"
        case .noValidEndpoints:
            return "No valid DAPI endpoints found"
        case .plistConfigurationNotFound:
            return "DAPI configuration plist not found"
        case .environmentVariableNotSet:
            return "DAPI endpoints environment variable not set"
        case .networkUnavailable:
            return "Network is unavailable for DAPI configuration"
        }
    }
}