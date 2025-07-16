import Foundation
import Network

/// Service responsible for checking DAPI endpoint health and providing fallback logic
actor DAPIHealthChecker {
    
    // MARK: - Health Check Result
    
    struct HealthCheckResult {
        let endpoint: String
        let isHealthy: Bool
        let responseTime: TimeInterval
        let error: Error?
        
        init(endpoint: String, isHealthy: Bool, responseTime: TimeInterval, error: Error? = nil) {
            self.endpoint = endpoint
            self.isHealthy = isHealthy
            self.responseTime = responseTime
            self.error = error
        }
    }
    
    // MARK: - Properties
    
    private let network: PlatformNetwork
    private let urlSession: URLSession
    private let healthCheckTimeout: TimeInterval = 5.0
    private let maxConcurrentChecks: Int = 5
    private var endpointHealthCache: [String: HealthCheckResult] = [:]
    private var lastHealthCheck: Date?
    private let healthCacheTimeout: TimeInterval = 60.0 // 1 minute
    
    // MARK: - Initialization
    
    init(network: PlatformNetwork) {
        self.network = network
        
        // Configure URL session with short timeout for health checks
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = healthCheckTimeout
        configuration.timeoutIntervalForResource = healthCheckTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.urlSession = URLSession(configuration: configuration)
    }
    
    // MARK: - Public Methods
    
    /// Check health of all provided endpoints and return healthy ones sorted by response time
    func getHealthyEndpoints(from endpoints: [String]) async -> [String] {
        print("🏥 Checking health of \(endpoints.count) DAPI endpoints...")
        
        // Check if we have cached results
        if let cachedResults = getCachedHealthResults(for: endpoints) {
            print("📋 Using cached health results")
            return cachedResults
        }
        
        // Perform health checks
        let results = await performHealthChecks(endpoints: endpoints)
        
        // Cache results
        updateHealthCache(with: results)
        
        // Filter healthy endpoints and sort by response time
        let healthyEndpoints = results
            .filter { $0.isHealthy }
            .sorted { $0.responseTime < $1.responseTime }
            .map { $0.endpoint }
        
        print("✅ Found \(healthyEndpoints.count) healthy endpoints out of \(endpoints.count)")
        
        return healthyEndpoints
    }
    
    /// Check health of a single endpoint
    func checkEndpointHealth(_ endpoint: String) async -> HealthCheckResult {
        print("🔍 Checking health of endpoint: \(endpoint)")
        
        let startTime = Date()
        
        do {
            let isHealthy = try await performSingleHealthCheck(endpoint)
            let responseTime = Date().timeIntervalSince(startTime)
            
            return HealthCheckResult(
                endpoint: endpoint,
                isHealthy: isHealthy,
                responseTime: responseTime
            )
        } catch {
            let responseTime = Date().timeIntervalSince(startTime)
            
            return HealthCheckResult(
                endpoint: endpoint,
                isHealthy: false,
                responseTime: responseTime,
                error: error
            )
        }
    }
    
    /// Get the best available endpoint with fallback logic
    func getBestEndpoint(from endpoints: [String], fallbackEndpoints: [String] = []) async -> String? {
        print("🎯 Finding best available endpoint...")
        
        // First try the provided endpoints
        let healthyEndpoints = await getHealthyEndpoints(from: endpoints)
        if let bestEndpoint = healthyEndpoints.first {
            print("✅ Best endpoint found: \(bestEndpoint)")
            return bestEndpoint
        }
        
        // If no healthy endpoints found, try fallback
        if !fallbackEndpoints.isEmpty {
            print("🔄 No healthy endpoints found, trying fallback endpoints...")
            let healthyFallbacks = await getHealthyEndpoints(from: fallbackEndpoints)
            if let fallbackEndpoint = healthyFallbacks.first {
                print("✅ Fallback endpoint found: \(fallbackEndpoint)")
                return fallbackEndpoint
            }
        }
        
        print("❌ No healthy endpoints available")
        return nil
    }
    
    /// Clear health cache and force refresh
    func clearHealthCache() {
        endpointHealthCache.removeAll()
        lastHealthCheck = nil
        print("🧹 Health cache cleared")
    }
    
    // MARK: - Private Methods
    
    private func getCachedHealthResults(for endpoints: [String]) -> [String]? {
        guard let lastCheck = lastHealthCheck,
              Date().timeIntervalSince(lastCheck) < healthCacheTimeout else {
            return nil
        }
        
        // Check if we have cached results for all endpoints
        let cachedHealthyEndpoints = endpoints.compactMap { endpoint -> (String, TimeInterval)? in
            guard let cached = endpointHealthCache[endpoint],
                  cached.isHealthy else {
                return nil
            }
            return (endpoint, cached.responseTime)
        }
        
        // Only return cached results if we have at least some healthy endpoints
        guard !cachedHealthyEndpoints.isEmpty else {
            return nil
        }
        
        return cachedHealthyEndpoints
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }
    
    private func performHealthChecks(endpoints: [String]) async -> [HealthCheckResult] {
        // Limit concurrent checks to avoid overwhelming the system
        let semaphore = AsyncSemaphore(value: maxConcurrentChecks)
        
        return await withTaskGroup(of: HealthCheckResult.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    await semaphore.wait()
                    let result = await self.checkEndpointHealth(endpoint)
                    await semaphore.signal()
                    return result
                }
            }
            
            var results: [HealthCheckResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }
    
    private func performSingleHealthCheck(_ endpoint: String) async throws -> Bool {
        guard let url = URL(string: endpoint) else {
            throw DAPIHealthError.invalidEndpointURL
        }
        
        // Create a simple GET request to check if the endpoint is responding
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DashPay-iOS-HealthCheck/1.0", forHTTPHeaderField: "User-Agent")
        
        let (_, response) = try await urlSession.data(for: request)
        
        // Check if we got a valid HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DAPIHealthError.invalidResponse
        }
        
        // Consider 2xx, 3xx, 4xx as healthy (server is responding)
        // Only 5xx or connection errors are considered unhealthy
        let isHealthy = httpResponse.statusCode < 500
        
        if isHealthy {
            print("✅ Endpoint \(endpoint) is healthy (status: \(httpResponse.statusCode))")
        } else {
            print("❌ Endpoint \(endpoint) is unhealthy (status: \(httpResponse.statusCode))")
        }
        
        return isHealthy
    }
    
    private func updateHealthCache(with results: [HealthCheckResult]) {
        for result in results {
            endpointHealthCache[result.endpoint] = result
        }
        lastHealthCheck = Date()
    }
}

// MARK: - Error Types

enum DAPIHealthError: LocalizedError {
    case invalidEndpointURL
    case invalidResponse
    case connectionTimeout
    case serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidEndpointURL:
            return "Invalid endpoint URL"
        case .invalidResponse:
            return "Invalid response from endpoint"
        case .connectionTimeout:
            return "Connection timeout"
        case .serverError(let code):
            return "Server error with status code: \(code)"
        }
    }
}

