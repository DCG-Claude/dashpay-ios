import SwiftUI
import SwiftData

struct IdentitiesView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [IdentityModel] = []
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedIdentity: IdentityModel?
    @State private var showIdentityDetail = false
    @State private var isSyncing = false
    @State private var cacheStats: IdentityCacheStatistics?
    @State private var showCacheStats = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Section
                IdentitySearchSection(
                    searchText: $searchText,
                    isSearching: $isSearching,
                    onSearch: performSearch,
                    onClear: clearSearch
                )
                
                // Results Section
                if searchText.isEmpty {
                    // Show cached identities when not searching
                    CachedIdentitiesSection(
                        identities: appState.identities,
                        onIdentityTap: selectIdentity,
                        onRefresh: refreshCachedIdentities
                    )
                } else {
                    // Show search results
                    SearchResultsSection(
                        searchResults: searchResults,
                        isSearching: isSearching,
                        onIdentityTap: selectIdentity
                    )
                }
            }
            .navigationTitle("Identities")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: syncAllIdentities) {
                            Label("Sync All", systemImage: "arrow.clockwise")
                        }
                        .disabled(isSyncing)
                        
                        Button(action: showCacheStatistics) {
                            Label("Cache Stats", systemImage: "chart.bar")
                        }
                        
                        Button(action: clearCache) {
                            Label("Clear Cache", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showIdentityDetail) {
                if let identity = selectedIdentity {
                    IdentityDetailView(identity: identity)
                        .environmentObject(appState)
                }
            }
            .sheet(isPresented: $showCacheStats) {
                if let stats = cacheStats {
                    IdentityCacheStatsView(stats: stats)
                }
            }
            .onAppear {
                loadCacheStatistics()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearSearch()
            return
        }
        
        Task {
            isSearching = true
            defer { isSearching = false }
            
            guard let identityService = appState.identityService else {
                await showErrorMessage("Identity service not available")
                return
            }
            
            do {
                let results = try await identityService.searchIdentities(query: searchText, limit: 50)
                await MainActor.run {
                    searchResults = results
                }
            } catch {
                await showErrorMessage("Search failed: \(error.localizedDescription)")
                await MainActor.run {
                    searchResults = []
                }
            }
        }
    }
    
    private func clearSearch() {
        searchText = ""
        searchResults = []
        isSearching = false
    }
    
    private func selectIdentity(_ identity: IdentityModel) {
        selectedIdentity = identity
        showIdentityDetail = true
    }
    
    private func refreshCachedIdentities() {
        Task {
            guard let identityService = appState.identityService else { return }
            
            // Get cached identities and refresh a few of them
            let cachedIdentities = identityService.getCachedIdentities()
            let identitiesNeedingRefresh = Array(cachedIdentities.prefix(5))
            
            for identity in identitiesNeedingRefresh {
                do {
                    _ = try await identityService.refreshIdentity(id: identity.idString)
                } catch {
                    print("Failed to refresh identity \(identity.idString): \(error)")
                }
            }
            
            await MainActor.run {
                // Update app state identities
                appState.identities = identityService.getCachedIdentities()
                loadCacheStatistics()
            }
        }
    }
    
    private func syncAllIdentities() {
        Task {
            isSyncing = true
            defer { isSyncing = false }
            
            guard let identityService = appState.identityService else {
                await showErrorMessage("Identity service not available")
                return
            }
            
            await identityService.syncAllIdentities()
            
            await MainActor.run {
                // Update app state identities
                appState.identities = identityService.getCachedIdentities()
                loadCacheStatistics()
            }
        }
    }
    
    private func clearCache() {
        guard let identityService = appState.identityService else { return }
        identityService.clearCache()
        loadCacheStatistics()
    }
    
    private func showCacheStatistics() {
        loadCacheStatistics()
        showCacheStats = true
    }
    
    private func loadCacheStatistics() {
        guard let identityService = appState.identityService else { return }
        cacheStats = identityService.getCacheStatistics()
    }
    
    @MainActor
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Identity Search Section

struct IdentitySearchSection: View {
    @Binding var searchText: String
    @Binding var isSearching: Bool
    let onSearch: () -> Void
    let onClear: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search by ID or alias...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        onSearch()
                    }
                
                if !searchText.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            if !searchText.isEmpty && !isSearching {
                Button(action: onSearch) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Search Platform")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundColor(.blue)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

// MARK: - Cached Identities Section

struct CachedIdentitiesSection: View {
    let identities: [IdentityModel]
    let onIdentityTap: (IdentityModel) -> Void
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Cached Identities (\(identities.count))")
            
            if identities.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("No Identities")
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Text("Search for identities by ID or alias to populate the cache")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(identities, id: \.id) { identity in
                            IdentityRowView(identity: identity, onTap: onIdentityTap)
                        }
                    }
                }
                .refreshable {
                    onRefresh()
                }
            }
        }
    }
}

// MARK: - Search Results Section

struct SearchResultsSection: View {
    let searchResults: [IdentityModel]
    let isSearching: Bool
    let onIdentityTap: (IdentityModel) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Search Results (\(searchResults.count))")
            
            if isSearching {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    Text("Searching Platform...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if searchResults.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No Results")
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Text("No identities found matching your search")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(searchResults, id: \.id) { identity in
                            IdentityRowView(identity: identity, onTap: onIdentityTap)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Identity Row View

struct IdentityRowView: View {
    let identity: IdentityModel
    let onTap: (IdentityModel) -> Void
    
    var body: some View {
        Button(action: { onTap(identity) }) {
            HStack(spacing: 12) {
                // Identity Icon
                Image(systemName: identity.type == .masternode ? "server.rack" : "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(identity.type == .masternode ? .purple : .blue)
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Name/Alias
                    HStack {
                        Text(identity.alias ?? "Identity")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if identity.isLocal {
                            Text("Local")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                        
                        if identity.type != .user {
                            Text(identity.type.rawValue)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(identity.type == .masternode ? Color.purple : Color.orange)
                                .cornerRadius(4)
                        }
                    }
                    
                    // Identity ID (shortened)
                    Text(identity.idString.prefix(16) + "...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontDesign(.monospaced)
                    
                    // Balance
                    HStack {
                        Text("\(identity.balance) credits")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(identity.formattedBalance)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Identity Cache Stats View

struct IdentityCacheStatsView: View {
    let stats: IdentityCacheStatistics
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Overview Cards
                HStack(spacing: 16) {
                    StatCard(title: "Total", value: "\(stats.totalCached)", icon: "person.3.fill", color: .blue)
                    StatCard(title: "Active", value: "\(stats.activeCached)", icon: "checkmark.circle.fill", color: .green)
                    StatCard(title: "Expired", value: "\(stats.expiredCached)", icon: "exclamationmark.circle.fill", color: .orange)
                }
                
                // Sync Information
                VStack(spacing: 16) {
                    GroupBox("Synchronization") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Status:")
                                Spacer()
                                Text(stats.isSyncing ? "Syncing..." : "Idle")
                                    .foregroundColor(stats.isSyncing ? .orange : .green)
                            }
                            
                            if let lastSync = stats.lastSyncDate {
                                HStack {
                                    Text("Last Sync:")
                                    Spacer()
                                    Text(formatDate(lastSync))
                                        .fontDesign(.monospaced)
                                }
                            }
                            
                            if stats.syncErrorCount > 0 {
                                HStack {
                                    Text("Errors:")
                                    Spacer()
                                    Text("\(stats.syncErrorCount)")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Cache Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Stat Card
// Using StatCard from EnhancedContractDetailView.swift

#Preview {
    IdentitiesView()
        .environmentObject(AppState())
}