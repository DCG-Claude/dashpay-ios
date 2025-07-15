import SwiftUI

/// Enhanced contract browsing interface with search, filtering, and discovery
struct ContractBrowserView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedCategory = ContractCategory.all
    @State private var showingContractFetch = false
    @State private var showingContractDetail = false
    @State private var selectedContract: ContractModel?
    @State private var isLoading = false
    @State private var isLoadingPopular = false
    @State private var popularContracts: [ContractModel] = []
    @State private var searchResults: [ContractModel] = []
    @State private var showError = false
    @State private var errorMessage = ""
    
    private var contractService: ContractService? {
        guard let platformSDK = appState.platformSDK,
              let dataManager = appState.dataManager else { return nil }
        return ContractService(platformSDK: platformSDK, dataManager: dataManager)
    }
    
    var filteredContracts: [ContractModel] {
        var contracts = searchText.isEmpty ? appState.contracts : searchResults
        
        switch selectedCategory {
        case .all:
            break
        case .system:
            contracts = contracts.filter { isSystemContract($0) }
        case .social:
            contracts = contracts.filter { isSocialContract($0) }
        case .financial:
            contracts = contracts.filter { isFinancialContract($0) }
        case .gaming:
            contracts = contracts.filter { isGamingContract($0) }
        case .data:
            contracts = contracts.filter { isDataContract($0) }
        case .other:
            contracts = contracts.filter { !isSystemContract($0) && !isSocialContract($0) && !isFinancialContract($0) && !isGamingContract($0) && !isDataContract($0) }
        }
        
        return contracts
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and Filters
                SearchAndFiltersSection()
                
                // Main Content
                if isLoading {
                    LoadingSection()
                } else {
                    ContractListSection()
                }
            }
            .navigationTitle("Contract Browser")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingContractFetch = true }) {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .sheet(isPresented: $showingContractFetch) {
                FetchContractView()
                    .environmentObject(appState)
            }
            .sheet(item: $selectedContract) { contract in
                EnhancedContractDetailView(contract: contract)
                    .environmentObject(appState)
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                loadPopularContracts()
            }
        }
    }
    
    // MARK: - Search and Filters Section
    
    @ViewBuilder
    private func SearchAndFiltersSection() -> some View {
        VStack(spacing: 12) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search contracts...", text: $searchText)
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            // Category Filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ContractCategory.allCases, id: \.self) { category in
                        CategoryChip(
                            category: category,
                            isSelected: selectedCategory == category,
                            action: { selectedCategory = category }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    // MARK: - Loading Section
    
    @ViewBuilder
    private func LoadingSection() -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading contracts...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Contract List Section
    
    @ViewBuilder
    private func ContractListSection() -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Popular Contracts Section (when not searching)
                if searchText.isEmpty && !popularContracts.isEmpty {
                    PopularContractsSection()
                }
                
                // All Contracts or Search Results
                ContractsGridSection()
            }
            .padding()
        }
    }
    
    // MARK: - Popular Contracts Section
    
    @ViewBuilder
    private func PopularContractsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Popular Contracts")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isLoadingPopular {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(popularContracts) { contract in
                        PopularContractCard(contract: contract) {
                            selectedContract = contract
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - Contracts Grid Section
    
    @ViewBuilder
    private func ContractsGridSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(searchText.isEmpty ? "All Contracts" : "Search Results")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(filteredContracts.count) contract\(filteredContracts.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if filteredContracts.isEmpty {
                EmptyContractsView()
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                    ForEach(filteredContracts) { contract in
                        ContractGridCard(contract: contract) {
                            selectedContract = contract
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        
        Task {
            await MainActor.run { isLoading = true }
            
            do {
                let query = ContractSearchQuery(
                    contractId: searchText.count > 20 ? searchText : nil,
                    name: searchText,
                    keywords: searchText.components(separatedBy: " ").filter { !$0.isEmpty },
                    limit: 50
                )
                
                let results = try await contractService?.searchContracts(query: query) ?? []
                
                await MainActor.run {
                    searchResults = results
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    showError(message: "Search failed: \(error.localizedDescription)")
                    isLoading = false
                }
            }
        }
    }
    
    private func clearSearch() {
        searchText = ""
        searchResults = []
    }
    
    private func loadPopularContracts() {
        Task {
            await MainActor.run { isLoadingPopular = true }
            
            do {
                let popular = try await contractService?.getPopularContracts(limit: 10) ?? []
                
                await MainActor.run {
                    popularContracts = popular
                    isLoadingPopular = false
                }
            } catch {
                await MainActor.run {
                    print("Failed to load popular contracts: \(error)")
                    isLoadingPopular = false
                }
            }
        }
    }
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
    
    // Contract categorization
    private func isSystemContract(_ contract: ContractModel) -> Bool {
        return contract.keywords.contains { ["dpns", "system", "core", "platform"].contains($0.lowercased()) }
    }
    
    private func isSocialContract(_ contract: ContractModel) -> Bool {
        return contract.keywords.contains { ["dashpay", "social", "profile", "contact", "messaging"].contains($0.lowercased()) }
    }
    
    private func isFinancialContract(_ contract: ContractModel) -> Bool {
        return contract.keywords.contains { ["token", "finance", "payment", "defi", "rewards", "masternode"].contains($0.lowercased()) }
    }
    
    private func isGamingContract(_ contract: ContractModel) -> Bool {
        return contract.keywords.contains { ["gaming", "game", "nft", "collectible"].contains($0.lowercased()) }
    }
    
    private func isDataContract(_ contract: ContractModel) -> Bool {
        return contract.keywords.contains { ["data", "storage", "file", "document"].contains($0.lowercased()) }
    }
}

// MARK: - Supporting Views

struct CategoryChip: View {
    let category: ContractCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(category.displayName)
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

struct PopularContractCard: View {
    let contract: ContractModel
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ContractIcon(contract: contract)
                        .font(.title2)
                    
                    Spacer()
                    
                    Text("v\(contract.version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                }
                
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
                    Text("\(contract.documentTypes.count) types")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !contract.tokens.isEmpty {
                        Image(systemName: "bitcoinsign.circle")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding()
            .frame(width: 200, height: 120)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ContractGridCard: View {
    let contract: ContractModel
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ContractIcon(contract: contract)
                        .font(.title3)
                    
                    Spacer()
                    
                    Text("v\(contract.version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(.systemGray5))
                        .cornerRadius(3)
                }
                
                Text(contract.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(contract.description ?? "Data contract")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                HStack {
                    Text("\(contract.documentTypes.count)")
                        .font(.caption2)
                        .fontWeight(.medium)
                    Text("types")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !contract.tokens.isEmpty {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(12)
            .frame(height: 100)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ContractIcon: View {
    let contract: ContractModel
    
    private var iconName: String {
        if contract.keywords.contains(where: { ["dpns", "domain", "name"].contains($0.lowercased()) }) {
            return "globe"
        } else if contract.keywords.contains(where: { ["dashpay", "social", "profile"].contains($0.lowercased()) }) {
            return "person.2"
        } else if contract.keywords.contains(where: { ["token", "finance", "rewards"].contains($0.lowercased()) }) {
            return "bitcoinsign.circle"
        } else if contract.keywords.contains(where: { ["gaming", "game"].contains($0.lowercased()) }) {
            return "gamecontroller"
        } else if contract.keywords.contains(where: { ["data", "storage"].contains($0.lowercased()) }) {
            return "internaldrive"
        } else {
            return "doc.text"
        }
    }
    
    private var iconColor: Color {
        if contract.keywords.contains(where: { ["dpns", "domain", "name"].contains($0.lowercased()) }) {
            return .blue
        } else if contract.keywords.contains(where: { ["dashpay", "social", "profile"].contains($0.lowercased()) }) {
            return .green
        } else if contract.keywords.contains(where: { ["token", "finance", "rewards"].contains($0.lowercased()) }) {
            return .orange
        } else if contract.keywords.contains(where: { ["gaming", "game"].contains($0.lowercased()) }) {
            return .purple
        } else if contract.keywords.contains(where: { ["data", "storage"].contains($0.lowercased()) }) {
            return .indigo
        } else {
            return .gray
        }
    }
    
    var body: some View {
        Image(systemName: iconName)
            .foregroundColor(iconColor)
    }
}

struct EmptyContractsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Contracts Found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Try adjusting your search or browse popular contracts")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Supporting Types

enum ContractCategory: String, CaseIterable {
    case all = "all"
    case system = "system"
    case social = "social"
    case financial = "financial"
    case gaming = "gaming"
    case data = "data"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .system: return "System"
        case .social: return "Social"
        case .financial: return "Financial"
        case .gaming: return "Gaming"
        case .data: return "Data"
        case .other: return "Other"
        }
    }
}

#Preview {
    let appState = AppState()
    appState.contracts = [
        ContractModel(
            id: "GWRSAVFMjXx8HpQFaNJMqBV7MBgMK4br5UESsB4S31Ec",
            name: "DPNS",
            version: 1,
            ownerId: Data(repeating: 0, count: 32),
            documentTypes: ["domain", "preorder"],
            schema: [:],
            keywords: ["dpns", "domain", "name"],
            description: "Dash Platform Name Service"
        ),
        ContractModel(
            id: "Bwr4jHXb7vtJEKjGgajQzHk7aMXWvNJUAfZXgvFtB5yM",
            name: "DashPay",
            version: 1,
            ownerId: Data(repeating: 0, count: 32),
            documentTypes: ["profile", "contactRequest"],
            schema: [:],
            keywords: ["dashpay", "social", "profile"],
            description: "DashPay social features"
        )
    ]
    
    return ContractBrowserView()
        .environmentObject(appState)
}