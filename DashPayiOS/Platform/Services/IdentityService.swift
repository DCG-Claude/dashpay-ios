import Foundation
import SwiftData
import Combine

/// Service for managing Platform identities with caching, synchronization, and real Platform SDK integration
@MainActor
class IdentityService: ObservableObject {
    private let dataManager: DataManager
    private let platformSDK: PlatformSDKWrapper?
    private let cacheRefreshInterval: TimeInterval = 300 // 5 minutes
    private var refreshTimer: Timer?
    
    // In-memory cache for quick access
    @Published private(set) var cachedIdentities: [String: IdentityModel] = [:]
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var syncErrors: [IdentityServiceError] = []
    
    // Cache management
    private var identityCache: [String: CachedIdentity] = [:]
    private let maxCacheSize = 1000
    private let maxCacheAge: TimeInterval = 3600 // 1 hour
    
    init(dataManager: DataManager, platformSDK: PlatformSDKWrapper?) {
        self.dataManager = dataManager
        self.platformSDK = platformSDK
        
        // Start periodic cache refresh
        startPeriodicRefresh()
        
        // Load cached identities from persistence
        Task {
            await loadCachedIdentities()
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    // MARK: - Public API
    
    /// Fetch a single identity by ID with caching
    func fetchIdentity(id: String) async throws -> IdentityModel? {
        // Check cache first
        if let cached = getCachedIdentity(id: id), !cached.isExpired {
            return cached.identity
        }
        
        // Fetch from Platform SDK
        guard let platformSDK = platformSDK else {
            throw IdentityServiceError.platformSDKNotAvailable
        }
        
        do {
            let dppIdentity = try await platformFetchIdentity(id: id)
            let identityModel = IdentityModel(from: dppIdentity)
            
            // Cache the result
            cacheIdentity(identityModel)
            
            // Save to persistence
            try await persistIdentity(identityModel)
            
            return identityModel
        } catch {
            // Try to get from local persistence as fallback
            if let persistedIdentity = try await getPersistedIdentity(id: id) {
                cacheIdentity(persistedIdentity)
                return persistedIdentity
            }
            
            throw IdentityServiceError.fetchFailed(underlying: error)
        }
    }
    
    /// Fetch multiple identities in batch
    func fetchIdentities(ids: [String]) async throws -> [IdentityModel] {
        guard !ids.isEmpty else { return [] }
        
        var results: [IdentityModel] = []
        var uncachedIds: [String] = []
        
        // Check cache for each ID
        for id in ids {
            if let cached = getCachedIdentity(id: id), !cached.isExpired {
                results.append(cached.identity)
            } else {
                uncachedIds.append(id)
            }
        }
        
        // Fetch uncached identities from Platform SDK
        if !uncachedIds.isEmpty {
            guard let platformSDK = platformSDK else {
                throw IdentityServiceError.platformSDKNotAvailable
            }
            
            do {
                let fetchedIdentities = try await platformFetchIdentities(ids: uncachedIds)
                
                for dppIdentity in fetchedIdentities {
                    let identityModel = IdentityModel(from: dppIdentity)
                    results.append(identityModel)
                    
                    // Cache and persist
                    cacheIdentity(identityModel)
                    try await persistIdentity(identityModel)
                }
            } catch {
                // Try to get missing ones from persistence
                for id in uncachedIds {
                    if let persistedIdentity = try await getPersistedIdentity(id: id) {
                        results.append(persistedIdentity)
                        cacheIdentity(persistedIdentity)
                    }
                }
                
                if results.count < ids.count {
                    throw IdentityServiceError.batchFetchFailed(
                        requested: ids.count,
                        retrieved: results.count,
                        underlying: error
                    )
                }
            }
        }
        
        return results
    }
    
    /// Search for identities by partial ID or alias
    func searchIdentities(query: String, limit: Int = 20) async throws -> [IdentityModel] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 3 else {
            throw IdentityServiceError.invalidSearchQuery("Query must be at least 3 characters")
        }
        
        // Search in cache first
        var results = searchCachedIdentities(query: trimmedQuery, limit: limit)
        
        // Search in persistence
        let persistedResults = try await searchPersistedIdentities(query: trimmedQuery, limit: limit)
        
        // Merge results without duplicates
        for persistedIdentity in persistedResults {
            if !results.contains(where: { $0.id == persistedIdentity.id }) {
                results.append(persistedIdentity)
                cacheIdentity(persistedIdentity)
            }
        }
        
        // If we have Platform SDK available and still need more results, try platform search
        if results.count < limit, platformSDK != nil {
            do {
                let platformResults = try await platformSearchIdentities(query: trimmedQuery, limit: limit - results.count)
                
                for dppIdentity in platformResults {
                    let identityModel = IdentityModel(from: dppIdentity)
                    if !results.contains(where: { $0.id == identityModel.id }) {
                        results.append(identityModel)
                        cacheIdentity(identityModel)
                        try await persistIdentity(identityModel)
                    }
                }
            } catch {
                // Log but don't fail the search
                print("Platform search failed: \(error)")
            }
        }
        
        return Array(results.prefix(limit))
    }
    
    /// Refresh an identity's data from the Platform
    func refreshIdentity(id: String) async throws -> IdentityModel? {
        guard let platformSDK = platformSDK else {
            throw IdentityServiceError.platformSDKNotAvailable
        }
        
        do {
            let dppIdentity = try await platformFetchIdentity(id: id)
            let identityModel = IdentityModel(from: dppIdentity)
            
            // Update cache and persistence
            cacheIdentity(identityModel)
            try await persistIdentity(identityModel)
            
            // Update published cached identities
            cachedIdentities[id] = identityModel
            
            return identityModel
        } catch {
            throw IdentityServiceError.refreshFailed(id: id, underlying: error)
        }
    }
    
    /// Sync all locally stored identities with the Platform
    func syncAllIdentities() async {
        guard !isSyncing else { return }
        
        isSyncing = true
        syncErrors.removeAll()
        
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }
        
        do {
            // Get all locally stored identity IDs
            let persistedIdentities = try dataManager.fetchIdentities()
            let identityIds = persistedIdentities.map { $0.idString }
            
            // Sync in batches to avoid overloading the network
            let batchSize = 10
            for batch in identityIds.chunked(into: batchSize) {
                do {
                    let refreshedIdentities = try await fetchIdentities(ids: Array(batch))
                    
                    // Update cached identities
                    for identity in refreshedIdentities {
                        cachedIdentities[identity.idString] = identity
                    }
                } catch {
                    let syncError = IdentityServiceError.syncBatchFailed(
                        batch: Array(batch),
                        underlying: error
                    )
                    syncErrors.append(syncError)
                    print("Failed to sync batch: \(batch) - \(error)")
                }
                
                // Small delay between batches to be network-friendly
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        } catch {
            let syncError = IdentityServiceError.syncFailed(underlying: error)
            syncErrors.append(syncError)
            print("Failed to sync identities: \(error)")
        }
    }
    
    /// Get all locally cached identities
    func getCachedIdentities() -> [IdentityModel] {
        return Array(cachedIdentities.values)
    }
    
    /// Clear identity cache
    func clearCache() {
        identityCache.removeAll()
        cachedIdentities.removeAll()
    }
    
    /// Get cache statistics
    func getCacheStatistics() -> IdentityCacheStatistics {
        let totalCached = identityCache.count
        let expiredCount = identityCache.values.filter { $0.isExpired }.count
        let activeCount = totalCached - expiredCount
        
        return IdentityCacheStatistics(
            totalCached: totalCached,
            activeCached: activeCount,
            expiredCached: expiredCount,
            lastSyncDate: lastSyncDate,
            isSyncing: isSyncing,
            syncErrorCount: syncErrors.count
        )
    }
    
    // MARK: - Private Methods
    
    private func getCachedIdentity(id: String) -> CachedIdentity? {
        return identityCache[id]
    }
    
    private func cacheIdentity(_ identity: IdentityModel) {
        let cached = CachedIdentity(identity: identity, timestamp: Date())
        identityCache[identity.idString] = cached
        
        // Enforce cache size limit
        if identityCache.count > maxCacheSize {
            cleanupCache()
        }
    }
    
    private func cleanupCache() {
        // Remove expired entries first
        identityCache = identityCache.filter { !$0.value.isExpired }
        
        // If still over limit, remove oldest entries
        if identityCache.count > maxCacheSize {
            let sortedByAge = identityCache.sorted { $0.value.timestamp < $1.value.timestamp }
            let toRemove = sortedByAge.prefix(identityCache.count - maxCacheSize)
            
            for (key, _) in toRemove {
                identityCache.removeValue(forKey: key)
            }
        }
    }
    
    private func searchCachedIdentities(query: String, limit: Int) -> [IdentityModel] {
        let lowercaseQuery = query.lowercased()
        
        return identityCache.values
            .filter { !$0.isExpired }
            .map { $0.identity }
            .filter { identity in
                identity.idString.lowercased().contains(lowercaseQuery) ||
                identity.alias?.lowercased().contains(lowercaseQuery) == true
            }
            .prefix(limit)
            .map { $0 }
    }
    
    private func searchPersistedIdentities(query: String, limit: Int) async throws -> [IdentityModel] {
        // This would use SwiftData predicates to search persisted identities
        // For now, we'll implement a simple search by loading all and filtering
        let allPersisted = try dataManager.fetchIdentities()
        let lowercaseQuery = query.lowercased()
        
        return allPersisted
            .filter { identity in
                identity.idString.lowercased().contains(lowercaseQuery) ||
                identity.alias?.lowercased().contains(lowercaseQuery) == true
            }
            .prefix(limit)
            .map { $0 }
    }
    
    private func persistIdentity(_ identity: IdentityModel) async throws {
        try dataManager.saveIdentity(identity)
    }
    
    private func getPersistedIdentity(id: String) async throws -> IdentityModel? {
        let allIdentities = try dataManager.fetchIdentities()
        return allIdentities.first { $0.idString == id }
    }
    
    private func loadCachedIdentities() async {
        do {
            let persistedIdentities = try dataManager.fetchIdentities()
            
            for identity in persistedIdentities {
                cachedIdentities[identity.idString] = identity
                cacheIdentity(identity)
            }
            
            print("🗂️ Loaded \(persistedIdentities.count) identities into cache")
        } catch {
            print("🔴 Failed to load cached identities: \(error)")
        }
    }
    
    private func startPeriodicRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: cacheRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performPeriodicRefresh()
            }
        }
    }
    
    private func performPeriodicRefresh() async {
        // Only refresh if we have identities and Platform SDK is available
        guard !cachedIdentities.isEmpty, platformSDK != nil else { return }
        
        // Refresh a few identities each time to spread the load
        let identitiesNeedingRefresh = Array(cachedIdentities.keys.prefix(5))
        
        for identityId in identitiesNeedingRefresh {
            try? await refreshIdentity(id: identityId)
        }
    }
}

// MARK: - Supporting Types

struct CachedIdentity {
    let identity: IdentityModel
    let timestamp: Date
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > 3600 // 1 hour
    }
}

struct IdentityCacheStatistics {
    let totalCached: Int
    let activeCached: Int
    let expiredCached: Int
    let lastSyncDate: Date?
    let isSyncing: Bool
    let syncErrorCount: Int
}

enum IdentityServiceError: LocalizedError {
    case platformSDKNotAvailable
    case fetchFailed(underlying: Error)
    case batchFetchFailed(requested: Int, retrieved: Int, underlying: Error)
    case refreshFailed(id: String, underlying: Error)
    case syncFailed(underlying: Error)
    case syncBatchFailed(batch: [String], underlying: Error)
    case invalidSearchQuery(String)
    case persistenceFailed(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .platformSDKNotAvailable:
            return "Platform SDK is not available"
        case .fetchFailed(let error):
            return "Failed to fetch identity: \(error.localizedDescription)"
        case .batchFetchFailed(let requested, let retrieved, let error):
            return "Batch fetch failed: got \(retrieved)/\(requested) identities - \(error.localizedDescription)"
        case .refreshFailed(let id, let error):
            return "Failed to refresh identity \(id): \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        case .syncBatchFailed(let batch, let error):
            return "Sync batch failed for \(batch.count) identities: \(error.localizedDescription)"
        case .invalidSearchQuery(let message):
            return "Invalid search query: \(message)"
        case .persistenceFailed(let error):
            return "Persistence failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Helper Extensions

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Platform SDK Integration Helpers

private extension IdentityService {
    /// Fetch a single identity from the Platform using PlatformSDKWrapper
    func platformFetchIdentity(id: String) async throws -> DPPIdentity {
        guard let platformSDK = platformSDK else {
            throw IdentityServiceError.platformSDKNotAvailable
        }
        
        // Use the existing fetchIdentity method from PlatformSDKWrapper
        let platformIdentity = try await platformSDK.fetchIdentity(id: id)
        
        // Convert Platform Identity to DPPIdentity
        // platformIdentity.id is already Identifier (Data)
        return DPPIdentity(
            id: platformIdentity.id,
            publicKeys: [:], // Would parse from platformIdentity if available
            balance: platformIdentity.balance,
            revision: platformIdentity.revision
        )
    }
    
    /// Fetch multiple identities from the Platform
    func platformFetchIdentities(ids: [String]) async throws -> [DPPIdentity] {
        var results: [DPPIdentity] = []
        
        for id in ids {
            do {
                let identity = try await platformFetchIdentity(id: id)
                results.append(identity)
            } catch {
                // Continue with other identities if one fails
                print("Failed to fetch identity \(id): \(error)")
            }
        }
        
        return results
    }
    
    /// Search for identities on the Platform (placeholder implementation)
    func platformSearchIdentities(query: String, limit: Int) async throws -> [DPPIdentity] {
        // Platform search is not implemented yet in the SDK
        // For now, return empty results
        return []
    }
}