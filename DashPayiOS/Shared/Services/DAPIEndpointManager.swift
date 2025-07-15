import Foundation

/// Unified service for managing DAPI endpoints with configuration and health checking
actor DAPIEndpointManager {
    
    // MARK: - Properties
    
    private let network: PlatformNetwork
    private let configurationService: DAPIConfigurationService
    private let healthChecker: DAPIHealthChecker
    
    // MARK: - Initialization
    
    init(network: PlatformNetwork, configurationSource: DAPIConfigurationService.ConfigurationSource? = nil) {
        self.network = network
        self.configurationService = DAPIConfigurationService(network: network, configurationSource: configurationSource)
        self.healthChecker = DAPIHealthChecker(network: network)
    }
    
    // MARK: - Public Methods
    
    /// Get healthy DAPI endpoints as a comma-separated string for FFI
    func getHealthyEndpointsString() async -> String {
        let endpoints = await getHealthyEndpoints()
        let endpointString = endpoints.joined(separator: ",")
        
        if endpointString.isEmpty {
            print("⚠️ No healthy endpoints available, using fallback")
            let fallbackEndpoints = await configurationService.getFallbackEndpoints()
            return fallbackEndpoints.joined(separator: ",")
        }
        
        return endpointString
    }
    
    /// Get healthy DAPI endpoints as an array
    func getHealthyEndpoints() async -> [String] {
        do {
            // Fetch endpoints from configuration source
            let configuredEndpoints = try await configurationService.fetchDAPIEndpoints()
            
            // Get fallback endpoints in case none are healthy
            let fallbackEndpoints = await configurationService.getFallbackEndpoints()
            
            // Check health and get best available endpoints
            let healthyEndpoints = await healthChecker.getHealthyEndpoints(from: configuredEndpoints)
            
            if !healthyEndpoints.isEmpty {
                print("✅ Using \(healthyEndpoints.count) healthy configured endpoints")
                return healthyEndpoints
            } else {
                print("⚠️ No healthy configured endpoints, checking fallback endpoints")
                let healthyFallbacks = await healthChecker.getHealthyEndpoints(from: fallbackEndpoints)
                
                if !healthyFallbacks.isEmpty {
                    print("✅ Using \(healthyFallbacks.count) healthy fallback endpoints")
                    return healthyFallbacks
                } else {
                    print("❌ No healthy endpoints available at all, returning fallback for emergency use")
                    return fallbackEndpoints
                }
            }
        } catch {
            print("🔴 Failed to fetch DAPI configuration: \(error)")
            print("📋 Falling back to emergency endpoints")
            
            // In case of configuration failure, use fallback endpoints
            let fallbackEndpoints = await configurationService.getFallbackEndpoints()
            let healthyFallbacks = await healthChecker.getHealthyEndpoints(from: fallbackEndpoints)
            
            return healthyFallbacks.isEmpty ? fallbackEndpoints : healthyFallbacks
        }
    }
    
    /// Get the single best endpoint for critical operations
    func getBestEndpoint() async -> String? {
        let healthyEndpoints = await getHealthyEndpoints()
        return healthyEndpoints.first
    }
    
    /// Refresh endpoint configuration and health status
    func refreshEndpoints() async {
        do {
            _ = try await configurationService.refreshEndpoints()
            await healthChecker.clearHealthCache()
            print("✅ Endpoints refreshed successfully")
        } catch {
            print("🔴 Failed to refresh endpoints: \(error)")
        }
    }
    
    /// Test connectivity to all endpoints and return a status report
    func getConnectivityReport() async -> DAPIConnectivityReport {
        do {
            let configuredEndpoints = try await configurationService.fetchDAPIEndpoints()
            let fallbackEndpoints = await configurationService.getFallbackEndpoints()
            
            let configuredResults = await performHealthChecks(endpoints: configuredEndpoints, category: "Configured")
            let fallbackResults = await performHealthChecks(endpoints: fallbackEndpoints, category: "Fallback")
            
            return DAPIConnectivityReport(
                network: network,
                configuredEndpoints: configuredResults,
                fallbackEndpoints: fallbackResults,
                timestamp: Date()
            )
        } catch {
            print("🔴 Failed to generate connectivity report: \(error)")
            
            // Return minimal report with just fallback endpoints
            let fallbackEndpoints = await configurationService.getFallbackEndpoints()
            let fallbackResults = await performHealthChecks(endpoints: fallbackEndpoints, category: "Fallback")
            
            return DAPIConnectivityReport(
                network: network,
                configuredEndpoints: [],
                fallbackEndpoints: fallbackResults,
                timestamp: Date(),
                configurationError: error
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func performHealthChecks(endpoints: [String], category: String) async -> [DAPIEndpointStatus] {
        print("🔍 Checking health of \(endpoints.count) \(category.lowercased()) endpoints...")
        
        var results: [DAPIEndpointStatus] = []
        
        for endpoint in endpoints {
            let healthResult = await healthChecker.checkEndpointHealth(endpoint)
            
            let status = DAPIEndpointStatus(
                endpoint: endpoint,
                isHealthy: healthResult.isHealthy,
                responseTime: healthResult.responseTime,
                category: category,
                error: healthResult.error
            )
            
            results.append(status)
        }
        
        return results
    }
}

// MARK: - Supporting Types

struct DAPIEndpointStatus {
    let endpoint: String
    let isHealthy: Bool
    let responseTime: TimeInterval
    let category: String
    let error: Error?
    
    var formattedResponseTime: String {
        return String(format: "%.2f ms", responseTime * 1000)
    }
    
    var statusDescription: String {
        if isHealthy {
            return "Healthy (\(formattedResponseTime))"
        } else {
            return "Unhealthy - \(error?.localizedDescription ?? "Unknown error")"
        }
    }
}

struct DAPIConnectivityReport {
    let network: PlatformNetwork
    let configuredEndpoints: [DAPIEndpointStatus]
    let fallbackEndpoints: [DAPIEndpointStatus]
    let timestamp: Date
    let configurationError: Error?
    
    var totalEndpoints: Int {
        return configuredEndpoints.count + fallbackEndpoints.count
    }
    
    var healthyEndpoints: Int {
        return configuredEndpoints.filter { $0.isHealthy }.count + 
               fallbackEndpoints.filter { $0.isHealthy }.count
    }
    
    var hasHealthyEndpoints: Bool {
        return healthyEndpoints > 0
    }
    
    var summary: String {
        if let error = configurationError {
            return "Configuration failed: \(error.localizedDescription). Using fallback endpoints only."
        }
        
        return "Network: \(network), Healthy: \(healthyEndpoints)/\(totalEndpoints) endpoints"
    }
}