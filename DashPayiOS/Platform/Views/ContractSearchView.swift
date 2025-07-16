import SwiftUI

/// Advanced contract search and filtering interface
struct ContractSearchView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var selectedFilters = ContractFilters()
    @State private var searchResults: [ContractModel] = []
    @State private var isSearching = false
    @State private var showFilters = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var searchHistory: [String] = []
    
    private var contractService: ContractService? {
        guard let platformSDK = appState.platformSDK,
              let dataManager = appState.dataManager else { return nil }
        return ContractService(platformSDK: platformSDK, dataManager: dataManager)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Header
                SearchHeaderSection()
                
                // Filters (if shown)
                if showFilters {
                    FiltersSection()
                        .transition(.slide)
                }
                
                // Search Results or Suggestions
                SearchContentSection()
            }
            .navigationTitle("Search Contracts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { withAnimation { showFilters.toggle() } }) {
                        Image(systemName: showFilters ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease.circle")
                    }
                }
            }
            .alert("Search Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                loadSearchHistory()
            }
        }
    }
    
    // MARK: - Search Header Section
    
    @ViewBuilder
    private func SearchHeaderSection() -> some View {
        VStack(spacing: 12) {
            // Main Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search contracts by name, ID, or keyword...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onSubmit {
                        performSearch()
                    }
                
                if !searchText.isEmpty {
                    Button(action: clearSearch) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                
                Button("Search") {
                    performSearch()
                }
                .disabled(searchText.isEmpty || isSearching)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            // Search Type Buttons
            SearchTypeSelector()
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private func SearchTypeSelector() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                SearchTypeButton(
                    title: "By Name",
                    isSelected: selectedFilters.searchType == .name,
                    action: { selectedFilters.searchType = .name }
                )
                
                SearchTypeButton(
                    title: "By ID",
                    isSelected: selectedFilters.searchType == .contractId,
                    action: { selectedFilters.searchType = .contractId }
                )
                
                SearchTypeButton(
                    title: "By Owner",
                    isSelected: selectedFilters.searchType == .ownerId,
                    action: { selectedFilters.searchType = .ownerId }
                )
                
                SearchTypeButton(
                    title: "By Keywords",
                    isSelected: selectedFilters.searchType == .keywords,
                    action: { selectedFilters.searchType = .keywords }
                )
                
                SearchTypeButton(
                    title: "Advanced",
                    isSelected: selectedFilters.searchType == .advanced,
                    action: { 
                        selectedFilters.searchType = .advanced
                        showFilters = true
                    }
                )
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Filters Section
    
    @ViewBuilder
    private func FiltersSection() -> some View {
        VStack(spacing: 16) {
            // Category Filters
            VStack(alignment: .leading, spacing: 8) {
                Text("Categories")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(ContractCategory.allCases, id: \.self) { category in
                        ContractFilterChip(
                            title: category.displayName,
                            isSelected: selectedFilters.categories.contains(category),
                            action: { toggleCategory(category) }
                        )
                    }
                }
            }
            
            // Version Filter
            VStack(alignment: .leading, spacing: 8) {
                Text("Version")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    TextField("Min", value: $selectedFilters.minVersion, format: .number)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: .infinity)
                    
                    Text("to")
                        .foregroundColor(.secondary)
                    
                    TextField("Max", value: $selectedFilters.maxVersion, format: .number)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Document Types Filter
            VStack(alignment: .leading, spacing: 8) {
                Text("Document Types")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextField("Filter by document types (comma separated)", text: $selectedFilters.documentTypes)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            // Has Tokens Filter
            Toggle("Has Tokens", isOn: $selectedFilters.hasTokens)
            
            // Clear Filters Button
            Button("Clear All Filters") {
                selectedFilters = ContractFilters()
            }
            .foregroundColor(.red)
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Search Content Section
    
    @ViewBuilder
    private func SearchContentSection() -> some View {
        if isSearching {
            SearchLoadingView()
        } else if searchText.isEmpty && searchResults.isEmpty {
            SearchSuggestionsView()
        } else if searchResults.isEmpty && !searchText.isEmpty {
            SearchEmptyView()
        } else {
            SearchResultsView()
        }
    }
    
    @ViewBuilder
    private func SearchLoadingView() -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Searching contracts...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func SearchSuggestionsView() -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Search History
                if !searchHistory.isEmpty {
                    SearchHistorySection()
                }
                
                // Popular Searches
                PopularSearchesSection()
                
                // Quick Actions
                QuickActionsSection()
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func SearchResultsView() -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Results Header
                HStack {
                    Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !searchResults.isEmpty {
                        Button("Save Search") {
                            saveSearchToHistory()
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                
                // Results List
                ForEach(searchResults) { contract in
                    ContractSearchResultCard(contract: contract) {
                        // Handle contract selection
                        addContractToAppState(contract)
                        dismiss()
                    }
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func SearchEmptyView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Contracts Found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Try adjusting your search terms or filters")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Search Well-Known Contracts") {
                searchWellKnownContracts()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Supporting Sections
    
    @ViewBuilder
    private func SearchHistorySection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Searches")
                .font(.headline)
                .foregroundColor(.primary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                ForEach(searchHistory.prefix(6), id: \.self) { query in
                    Button(action: { searchFromHistory(query) }) {
                        HStack {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(query)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    @ViewBuilder
    private func PopularSearchesSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular Searches")
                .font(.headline)
                .foregroundColor(.primary)
            
            let popularSearches = ["DPNS", "DashPay", "Masternode", "Token", "Profile"]
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(popularSearches, id: \.self) { query in
                    Button(action: { searchFromSuggestion(query) }) {
                        Text(query)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    @ViewBuilder
    private func QuickActionsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                ContractQuickActionButton(
                    title: "Browse All Contracts",
                    subtitle: "View all available contracts",
                    icon: "doc.text.magnifyingglass",
                    action: { searchWellKnownContracts() }
                )
                
                ContractQuickActionButton(
                    title: "System Contracts",
                    subtitle: "DPNS, DashPay, and core contracts",
                    icon: "gear",
                    action: { searchSystemContracts() }
                )
                
                ContractQuickActionButton(
                    title: "Token Contracts",
                    subtitle: "Contracts with token features",
                    icon: "bitcoinsign.circle",
                    action: { searchTokenContracts() }
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        Task {
            await MainActor.run { isSearching = true }
            
            do {
                let query = buildSearchQuery()
                let results = try await contractService?.searchContracts(query: query) ?? []
                
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
                
                saveSearchToHistory()
                
            } catch {
                await MainActor.run {
                    showErrorMessage("Search failed: \(error.localizedDescription)")
                    isSearching = false
                }
            }
        }
    }
    
    private func buildSearchQuery() -> ContractSearchQuery {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch selectedFilters.searchType {
        case .name:
            return ContractSearchQuery(name: trimmedSearch, limit: 50)
        case .contractId:
            return ContractSearchQuery(contractId: trimmedSearch, limit: 1)
        case .ownerId:
            return ContractSearchQuery(ownerId: trimmedSearch, limit: 50)
        case .keywords:
            let keywords = trimmedSearch.components(separatedBy: .whitespacesAndNewlines)
            return ContractSearchQuery(keywords: keywords, limit: 50)
        case .advanced:
            return ContractSearchQuery(
                contractId: selectedFilters.searchType == .contractId ? trimmedSearch : nil,
                name: selectedFilters.searchType == .name ? trimmedSearch : nil,
                ownerId: selectedFilters.searchType == .ownerId ? trimmedSearch : nil,
                keywords: trimmedSearch.components(separatedBy: .whitespacesAndNewlines),
                limit: 50
            )
        }
    }
    
    private func clearSearch() {
        searchText = ""
        searchResults = []
    }
    
    private func toggleCategory(_ category: ContractCategory) {
        if selectedFilters.categories.contains(category) {
            selectedFilters.categories.remove(category)
        } else {
            selectedFilters.categories.insert(category)
        }
    }
    
    private func searchFromHistory(_ query: String) {
        searchText = query
        performSearch()
    }
    
    private func searchFromSuggestion(_ query: String) {
        searchText = query
        performSearch()
    }
    
    private func searchWellKnownContracts() {
        Task {
            await MainActor.run { isSearching = true }
            
            do {
                let results = try await contractService?.getPopularContracts(limit: 20) ?? []
                
                await MainActor.run {
                    searchResults = results
                    searchText = "Popular contracts"
                    isSearching = false
                }
                
            } catch {
                await MainActor.run {
                    showErrorMessage("Failed to load contracts: \(error.localizedDescription)")
                    isSearching = false
                }
            }
        }
    }
    
    private func searchSystemContracts() {
        selectedFilters.categories.insert(.system)
        searchText = "system"
        performSearch()
    }
    
    private func searchTokenContracts() {
        selectedFilters.hasTokens = true
        searchText = "token"
        performSearch()
    }
    
    private func addContractToAppState(_ contract: ContractModel) {
        appState.addContract(contract)
    }
    
    private func saveSearchToHistory() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !searchHistory.contains(query) else { return }
        
        searchHistory.insert(query, at: 0)
        if searchHistory.count > 10 {
            searchHistory = Array(searchHistory.prefix(10))
        }
        
        UserDefaults.standard.set(searchHistory, forKey: "contractSearchHistory")
    }
    
    private func loadSearchHistory() {
        searchHistory = UserDefaults.standard.stringArray(forKey: "contractSearchHistory") ?? []
    }
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Supporting Views

struct SearchTypeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ContractFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .medium : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ContractQuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ContractSearchResultCard: View {
    let contract: ContractModel
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ContractIcon(contract: contract)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(contract.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Text(contract.description ?? "Data contract")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack {
                        Text("v\(contract.version)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .cornerRadius(4)
                        
                        Text("\(contract.documentTypes.count) types")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if !contract.tokens.isEmpty {
                            Image(systemName: "bitcoinsign.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Supporting Types

struct ContractFilters {
    var searchType: SearchType = .name
    var categories: Set<ContractCategory> = []
    var minVersion: Int? = nil
    var maxVersion: Int? = nil
    var documentTypes: String = ""
    var hasTokens: Bool = false
    
    enum SearchType {
        case name
        case contractId
        case ownerId
        case keywords
        case advanced
    }
}

#Preview {
    ContractSearchView()
        .environmentObject(AppState())
}