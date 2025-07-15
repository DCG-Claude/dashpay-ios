import SwiftUI
import SwiftData

/// Enhanced contract detail view with comprehensive schema display and metadata
struct EnhancedContractDetailView: View {
    let contract: ContractModel
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = ContractDetailTab.overview
    @State private var showRawSchema = false
    @State private var showCreateDocument = false
    @State private var showContractHistory = false
    @State private var isRefreshing = false
    @State private var isCopied = false
    @State private var contractHistory: ContractHistoryResult?
    @State private var validationResult: ContractValidationResult?
    @Environment(\.dismiss) private var dismiss
    
    private var contractService: ContractService? {
        guard let platformSDK = appState.platformSDK,
              let dataManager = appState.dataManager else { return nil }
        return ContractService(platformSDK: platformSDK, dataManager: dataManager)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Contract Header
                ContractHeaderSection(
                    contract: contract,
                    isRefreshing: $isRefreshing,
                    onRefresh: refreshContract
                )
                
                // Tab Selector
                ContractTabSelector(selectedTab: $selectedTab)
                
                // Tab Content
                TabView(selection: $selectedTab) {
                    OverviewTabView()
                        .tag(ContractDetailTab.overview)
                    
                    SchemaTabView()
                        .tag(ContractDetailTab.schema)
                    
                    DocumentsTabView()
                        .tag(ContractDetailTab.documents)
                    
                    MetadataTabView()
                        .tag(ContractDetailTab.metadata)
                    
                    ActionsTabView()
                        .tag(ContractDetailTab.actions)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Contract Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showContractHistory = true }) {
                            Label("View History", systemImage: "clock")
                        }
                        Button(action: validateContract) {
                            Label("Validate Contract", systemImage: "checkmark.shield")
                        }
                        Button(action: exportContract) {
                            Label("Export Contract", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showCreateDocument) {
                CreateDocumentView(contract: contract)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showContractHistory) {
                ContractHistoryView(contract: contract)
                    .environmentObject(appState)
            }
            .onAppear {
                validateContract()
            }
        }
    }
    
    // MARK: - Tab Views
    
    @ViewBuilder
    private func OverviewTabView() -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Basic Information
                ContractBasicInfoSection(contract: contract)
                
                // Validation Results
                if let validation = validationResult {
                    ContractValidationSection(validation: validation)
                }
                
                // Quick Stats
                ContractStatsSection(contract: contract)
                
                // Description
                if let description = contract.description, !description.isEmpty {
                    ContractDescriptionSection(description: description)
                }
                
                // Keywords
                if !contract.keywords.isEmpty {
                    ContractKeywordsSection(keywords: contract.keywords)
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func SchemaTabView() -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Document Types Overview
                DocumentTypesOverviewSection(contract: contract)
                
                // Detailed Schema for each document type
                ForEach(contract.documentTypes, id: \.self) { docType in
                    DocumentTypeSchemaSection(
                        contract: contract,
                        documentType: docType
                    )
                }
                
                // Raw Schema Toggle
                RawSchemaSection(
                    contract: contract,
                    showRawSchema: $showRawSchema
                )
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func DocumentsTabView() -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Documents Summary
                DocumentsSummarySection(contract: contract)
                
                // Document Types
                ForEach(contract.documentTypes, id: \.self) { docType in
                    DocumentTypeActionsSection(
                        contract: contract,
                        documentType: docType,
                        onCreateDocument: { showCreateDocument = true }
                    )
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func MetadataTabView() -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Contract Metadata
                ContractMetadataSection(contract: contract)
                
                // DPP Information
                if let dppContract = contract.dppDataContract {
                    DPPContractInfoSection(dppContract: dppContract)
                }
                
                // Token Information
                if !contract.tokens.isEmpty {
                    ContractTokensSection(tokens: contract.tokens)
                }
                
                // Technical Details
                ContractTechnicalSection(contract: contract)
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func ActionsTabView() -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Primary Actions
                ContractPrimaryActionsSection(
                    contract: contract,
                    isCopied: $isCopied,
                    onCreateDocument: { showCreateDocument = true }
                )
                
                // Developer Actions
                ContractDeveloperActionsSection(contract: contract)
                
                // Management Actions
                ContractManagementActionsSection(contract: contract)
            }
            .padding()
        }
    }
    
    // MARK: - Helper Methods
    
    private func refreshContract() {
        Task {
            isRefreshing = true
            defer { isRefreshing = false }
            
            guard let contractService = contractService else { return }
            
            do {
                let refreshed = try await contractService.fetchContract(id: contract.id)
                // Update the contract in app state
                if let index = appState.contracts.firstIndex(where: { $0.id == contract.id }) {
                    await MainActor.run {
                        appState.contracts[index] = refreshed
                    }
                }
                
                // Update validation
                await validateContract()
                
            } catch {
                await MainActor.run {
                    appState.showError(message: "Failed to refresh contract: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func validateContract() {
        Task {
            guard let contractService = contractService else { return }
            
            do {
                let validation = try contractService.validateContract(contract)
                await MainActor.run {
                    validationResult = validation
                }
            } catch {
                print("Failed to validate contract: \(error)")
            }
        }
    }
    
    private func exportContract() {
        let contractData = """
        Contract ID: \(contract.id)
        Name: \(contract.name)
        Version: \(contract.version)
        Owner ID: \(contract.ownerIdString)
        Document Types: \(contract.documentTypes.joined(separator: ", "))
        
        Description: \(contract.description ?? "No description")
        Keywords: \(contract.keywords.joined(separator: ", "))
        
        Schema:
        \(contract.formattedSchema)
        """
        
        Clipboard.copy(contractData)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

// MARK: - Supporting Sections

struct ContractTabSelector: View {
    @Binding var selectedTab: ContractDetailTab
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(ContractDetailTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        VStack(spacing: 4) {
                            Text(tab.title)
                                .font(.subheadline)
                                .fontWeight(selectedTab == tab ? .semibold : .regular)
                            
                            Rectangle()
                                .frame(height: 2)
                                .foregroundColor(selectedTab == tab ? .blue : .clear)
                        }
                    }
                    .foregroundColor(selectedTab == tab ? .blue : .secondary)
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

struct ContractBasicInfoSection: View {
    let contract: ContractModel
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Basic Information")
            
            VStack(spacing: 0) {
                DetailRow(label: "Contract ID", value: contract.id)
                DetailRow(label: "Name", value: contract.name)
                DetailRow(label: "Version", value: "\(contract.version)")
                DetailRow(label: "Owner ID", value: contract.ownerIdString)
                DetailRow(label: "Document Types", value: "\(contract.documentTypes.count)")
            }
        }
    }
}

struct ContractValidationSection: View {
    let validation: ContractValidationResult
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Validation Status")
            
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: validation.isValid ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundColor(validation.isValid ? .green : .red)
                    
                    Text(validation.isValid ? "Contract is valid" : "Contract has issues")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(validation.isValid ? .green : .red)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                if !validation.issues.isEmpty {
                    ForEach(validation.issues.indices, id: \.self) { index in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            
                            Text(validation.issues[index].localizedDescription)
                                .font(.caption)
                                .foregroundColor(.red)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
                
                if !validation.warnings.isEmpty {
                    ForEach(validation.warnings.indices, id: \.self) { index in
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                                .font(.caption)
                            
                            Text(validation.warnings[index].localizedDescription)
                                .font(.caption)
                                .foregroundColor(.orange)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
            }
            .background(Color(.systemGray6))
        }
    }
}

struct ContractStatsSection: View {
    let contract: ContractModel
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Statistics")
            
            HStack(spacing: 16) {
                StatCard(
                    title: "Document Types",
                    value: "\(contract.documentTypes.count)",
                    icon: "doc.text",
                    color: .blue
                )
                
                StatCard(
                    title: "Tokens",
                    value: "\(contract.tokens.count)",
                    icon: "bitcoinsign.circle",
                    color: .orange
                )
                
                StatCard(
                    title: "Schema Properties",
                    value: "\(getTotalProperties())",
                    icon: "list.bullet",
                    color: .green
                )
            }
            .padding(16)
            .background(Color(.systemGray6))
        }
    }
    
    private func getTotalProperties() -> Int {
        var total = 0
        for (_, schemaObj) in contract.schema {
            if let schema = schemaObj as? [String: Any],
               let properties = schema["properties"] as? [String: Any] {
                total += properties.count
            }
        }
        return total
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct ContractDescriptionSection: View {
    let description: String
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Description")
            
            VStack(alignment: .leading, spacing: 8) {
                Text(description)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
        }
    }
}

struct ContractKeywordsSection: View {
    let keywords: [String]
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Keywords")
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(keywords, id: \.self) { keyword in
                    Text(keyword)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                }
            }
            .padding(16)
            .background(Color(.systemGray6))
        }
    }
}

// MARK: - Supporting Types

enum ContractDetailTab: String, CaseIterable {
    case overview = "overview"
    case schema = "schema"
    case documents = "documents"
    case metadata = "metadata"
    case actions = "actions"
    
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .schema: return "Schema"
        case .documents: return "Documents"
        case .metadata: return "Metadata"
        case .actions: return "Actions"
        }
    }
}

extension ContractValidationWarning: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noDocumentTypes:
            return "Contract has no document types defined"
        case .noSchemaProperties(let docType):
            return "Document type '\(docType)' has no properties defined"
        }
    }
}

// MARK: - Additional Sections (Stubs for now)

struct DocumentTypesOverviewSection: View {
    let contract: ContractModel
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Document Types")
            
            VStack(spacing: 0) {
                ForEach(contract.documentTypes, id: \.self) { docType in
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.blue)
                        
                        Text(docType)
                            .font(.body)
                        
                        Spacer()
                        
                        Text(getPropertyCount(for: docType))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    
                    if docType != contract.documentTypes.last {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
    }
    
    private func getPropertyCount(for docType: String) -> String {
        if let schema = contract.schema[docType] as? [String: Any],
           let properties = schema["properties"] as? [String: Any] {
            return "\(properties.count) properties"
        }
        return "0 properties"
    }
}

struct DocumentTypeSchemaSection: View {
    let contract: ContractModel
    let documentType: String
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "\(documentType) Schema")
            
            if let schema = contract.schema[documentType] as? [String: Any],
               let properties = schema["properties"] as? [String: Any] {
                
                VStack(spacing: 0) {
                    ForEach(Array(properties.keys.sorted()), id: \.self) { propertyName in
                        if let property = properties[propertyName] as? [String: Any] {
                            ContractPropertyRow(name: propertyName, property: property)
                            
                            if propertyName != Array(properties.keys.sorted()).last {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
                .background(Color(.systemGray6))
            } else {
                Text("No schema available")
                    .foregroundColor(.secondary)
                    .padding()
                    .background(Color(.systemGray6))
            }
        }
    }
}

struct ContractPropertyRow: View {
    let name: String
    let property: [String: Any]
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.body)
                    .fontWeight(.medium)
                
                if let type = property["type"] as? String {
                    Text("Type: \(type)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let description = property["description"] as? String {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                if let required = property["required"] as? Bool, required {
                    Text("Required")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(4)
                }
                
                if let format = property["format"] as? String {
                    Text(format)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct RawSchemaSection: View {
    let contract: ContractModel
    @Binding var showRawSchema: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation { showRawSchema.toggle() } }) {
                HStack {
                    Text("Raw Schema (JSON)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: showRawSchema ? "chevron.up" : "chevron.down")
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
            }
            .buttonStyle(PlainButtonStyle())
            
            if showRawSchema {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Text(contract.formattedSchema)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
                .background(Color(.systemGray6))
            }
        }
    }
}

// Additional stub sections that would be fully implemented
struct DocumentsSummarySection: View {
    let contract: ContractModel
    var body: some View { EmptyView() }
}

struct DocumentTypeActionsSection: View {
    let contract: ContractModel
    let documentType: String
    let onCreateDocument: () -> Void
    var body: some View { EmptyView() }
}

struct ContractMetadataSection: View {
    let contract: ContractModel
    var body: some View { EmptyView() }
}

struct DPPContractInfoSection: View {
    let dppContract: DPPDataContract
    var body: some View { EmptyView() }
}

struct ContractTokensSection: View {
    let tokens: [TokenConfiguration]
    var body: some View { EmptyView() }
}

struct ContractTechnicalSection: View {
    let contract: ContractModel
    var body: some View { EmptyView() }
}

struct ContractPrimaryActionsSection: View {
    let contract: ContractModel
    @Binding var isCopied: Bool
    let onCreateDocument: () -> Void
    var body: some View { EmptyView() }
}

struct ContractDeveloperActionsSection: View {
    let contract: ContractModel
    var body: some View { EmptyView() }
}

struct ContractManagementActionsSection: View {
    let contract: ContractModel
    var body: some View { EmptyView() }
}

struct ContractHistoryView: View {
    let contract: ContractModel
    @EnvironmentObject var appState: AppState
    var body: some View { EmptyView() }
}

#Preview {
    let contract = ContractModel(
        id: "GWRSAVFMjXx8HpQFaNJMqBV7MBgMK4br5UESsB4S31Ec",
        name: "DPNS",
        version: 1,
        ownerId: Data(repeating: 0xAB, count: 32),
        documentTypes: ["domain", "preorder"],
        schema: [
            "domain": [
                "type": "object",
                "properties": [
                    "label": ["type": "string", "description": "Domain label"],
                    "normalizedLabel": ["type": "string"],
                    "records": ["type": "object"]
                ]
            ]
        ],
        keywords: ["dpns", "domain", "name"],
        description: "Dash Platform Name Service for decentralized domain registration"
    )
    
    EnhancedContractDetailView(contract: contract)
        .environmentObject(AppState())
}