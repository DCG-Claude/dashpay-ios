import SwiftUI
import SwiftData

/// Enhanced documents view with search, filtering, and advanced features
struct EnhancedDocumentsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var documentService: DocumentService
    
    @State private var showingCreateDocument = false
    @State private var showingDocumentWizard = false
    @State private var selectedDocument: DocumentModel?
    @State private var searchText = ""
    @State private var selectedContractFilter: String = "All Contracts"
    @State private var selectedTypeFilter: String = "All Types"
    @State private var sortOrder: DocumentSortOrder = .createdDateDesc
    @State private var showingFilters = false
    @State private var showingBatchActions = false
    @State private var selectedDocuments: Set<String> = []
    @State private var isMultiSelectMode = false
    
    private var filteredDocuments: [DocumentModel] {
        var documents = appState.documents
        
        // Apply text search
        if !searchText.isEmpty {
            documents = documents.filter { document in
                document.documentType.localizedCaseInsensitiveContains(searchText) ||
                document.id.localizedCaseInsensitiveContains(searchText) ||
                document.data.values.compactMap { "\($0)" }.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply contract filter
        if selectedContractFilter != "All Contracts" {
            documents = documents.filter { $0.contractId == selectedContractFilter }
        }
        
        // Apply type filter
        if selectedTypeFilter != "All Types" {
            documents = documents.filter { $0.documentType == selectedTypeFilter }
        }
        
        // Apply sorting
        switch sortOrder {
        case .createdDateDesc:
            documents.sort { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
        case .createdDateAsc:
            documents.sort { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }
        case .updatedDateDesc:
            documents.sort { ($0.updatedAt ?? Date.distantPast) > ($1.updatedAt ?? Date.distantPast) }
        case .updatedDateAsc:
            documents.sort { ($0.updatedAt ?? Date.distantPast) < ($1.updatedAt ?? Date.distantPast) }
        case .documentType:
            documents.sort { $0.documentType < $1.documentType }
        case .revision:
            documents.sort { $0.revision > $1.revision }
        }
        
        return documents
    }
    
    private var availableContracts: [String] {
        let contracts = Array(Set(appState.documents.map { $0.contractId })).sorted()
        return ["All Contracts"] + contracts
    }
    
    private var availableTypes: [String] {
        let types = Array(Set(appState.documents.map { $0.documentType })).sorted()
        return ["All Types"] + types
    }
    
    init() {
        // Initialize with placeholder values - will be properly injected
        let dummyContainer = try! ModelContainer.inMemoryContainer()
        let dummyDataManager = DataManager(modelContext: dummyContainer.mainContext)
        let dummyPlatformSDK = try! PlatformSDKWrapper(network: .testnet)
        self._documentService = StateObject(wrappedValue: DocumentService(platformSDK: dummyPlatformSDK, dataManager: dummyDataManager))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and Filter Header
                DocumentsHeaderView(
                    searchText: $searchText,
                    showingFilters: $showingFilters,
                    isMultiSelectMode: $isMultiSelectMode,
                    selectedCount: selectedDocuments.count,
                    totalCount: filteredDocuments.count,
                    onShowBatchActions: { showingBatchActions = true },
                    onCreateDocument: { showingDocumentWizard = true }
                )
                
                // Filter Panel
                if showingFilters {
                    DocumentsFilterView(
                        selectedContractFilter: $selectedContractFilter,
                        selectedTypeFilter: $selectedTypeFilter,
                        sortOrder: $sortOrder,
                        availableContracts: availableContracts,
                        availableTypes: availableTypes
                    )
                    .transition(.opacity)
                }
                
                // Documents List
                if filteredDocuments.isEmpty {
                    DocumentsEmptyStateView(
                        searchText: searchText,
                        hasFilters: selectedContractFilter != "All Contracts" || selectedTypeFilter != "All Types",
                        onCreateDocument: { showingDocumentWizard = true },
                        onClearFilters: { clearFilters() }
                    )
                } else {
                    List {
                        ForEach(filteredDocuments) { document in
                            EnhancedDocumentRow(
                                document: document,
                                isSelected: selectedDocuments.contains(document.id),
                                isMultiSelectMode: isMultiSelectMode,
                                onTap: {
                                    if isMultiSelectMode {
                                        toggleSelection(document.id)
                                    } else {
                                        selectedDocument = document
                                    }
                                },
                                onToggleSelection: { toggleSelection(document.id) }
                            )
                        }
                        .onDelete { indexSet in
                            deleteDocuments(at: indexSet)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
                
                Spacer()
            }
            .navigationTitle("Documents")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingDocumentWizard) {
                DocumentCreationWizardView()
                    .environmentObject(appState)
            }
            .sheet(item: $selectedDocument) { document in
                EnhancedDocumentDetailView(document: document)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingBatchActions) {
                DocumentBatchActionsView(
                    selectedDocuments: Array(selectedDocuments),
                    documents: filteredDocuments,
                    onDismiss: {
                        showingBatchActions = false
                        clearSelection()
                    }
                )
                .environmentObject(appState)
            }
            .onAppear {
                setupDocumentService()
                if appState.documents.isEmpty {
                    loadSampleDocuments()
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupDocumentService() {
        guard let platformSDK = appState.platformSDK,
              let dataManager = appState.dataManager else {
            return
        }
        
        // In a real implementation, we would recreate the service with proper dependencies
        // For now, just log that we need to set it up
        print("📄 Setting up DocumentService with real dependencies")
    }
    
    private func loadSampleDocuments() {
        // Add sample documents for demonstration
        appState.documents = [
            DocumentModel(
                id: "doc1_profile",
                contractId: "dashpay-contract",
                documentType: "profile",
                ownerId: Data(hexString: "1111111111111111111111111111111111111111111111111111111111111111")!,
                data: [
                    "displayName": "Alice",
                    "publicMessage": "Hello from Alice!",
                    "avatarUrl": "https://example.com/alice.jpg"
                ],
                createdAt: Date().addingTimeInterval(-86400 * 7), // 7 days ago
                updatedAt: Date().addingTimeInterval(-86400 * 2)  // 2 days ago
            ),
            DocumentModel(
                id: "doc2_domain",
                contractId: "dpns-contract",
                documentType: "domain",
                ownerId: Data(hexString: "2222222222222222222222222222222222222222222222222222222222222222")!,
                data: [
                    "label": "bob",
                    "normalizedLabel": "bob",
                    "normalizedParentDomainName": "dash",
                    "records": [
                        "dashUniqueIdentityId": "2222222222222222222222222222222222222222222222222222222222222222"
                    ]
                ],
                createdAt: Date().addingTimeInterval(-86400 * 5), // 5 days ago
                updatedAt: Date().addingTimeInterval(-86400 * 1)  // 1 day ago
            ),
            DocumentModel(
                id: "doc3_note",
                contractId: "note-taking-contract",
                documentType: "note",
                ownerId: Data(hexString: "3333333333333333333333333333333333333333333333333333333333333333")!,
                data: [
                    "title": "Meeting Notes",
                    "content": "Discussed the new document features for DashPay iOS app. Need to implement CRUD operations.",
                    "tags": ["meeting", "development", "dashpay"],
                    "isPublic": false
                ],
                createdAt: Date().addingTimeInterval(-86400 * 3), // 3 days ago
                updatedAt: Date().addingTimeInterval(-3600 * 6)   // 6 hours ago
            ),
            DocumentModel(
                id: "doc4_contact",
                contractId: "contacts-contract",
                documentType: "contact",
                ownerId: Data(hexString: "1111111111111111111111111111111111111111111111111111111111111111")!,
                data: [
                    "name": "Charlie Developer",
                    "email": "charlie@example.com",
                    "phone": "+1-555-0123",
                    "company": "Dash Core Group",
                    "notes": "Expert in Platform development"
                ],
                createdAt: Date().addingTimeInterval(-86400 * 10), // 10 days ago
                updatedAt: Date().addingTimeInterval(-86400 * 4)   // 4 days ago
            )
        ]
    }
    
    private func toggleSelection(_ documentId: String) {
        if selectedDocuments.contains(documentId) {
            selectedDocuments.remove(documentId)
        } else {
            selectedDocuments.insert(documentId)
        }
    }
    
    private func clearSelection() {
        selectedDocuments.removeAll()
        isMultiSelectMode = false
    }
    
    private func clearFilters() {
        selectedContractFilter = "All Contracts"
        selectedTypeFilter = "All Types"
        searchText = ""
    }
    
    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets {
            if index < filteredDocuments.count {
                let document = filteredDocuments[index]
                
                Task {
                    do {
                        try await documentService.deleteDocument(document)
                        await MainActor.run {
                            appState.documents.removeAll { $0.id == document.id }
                        }
                    } catch {
                        await MainActor.run {
                            appState.showError(message: "Failed to delete document: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct DocumentsHeaderView: View {
    @Binding var searchText: String
    @Binding var showingFilters: Bool
    @Binding var isMultiSelectMode: Bool
    let selectedCount: Int
    let totalCount: Int
    let onShowBatchActions: () -> Void
    let onCreateDocument: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search documents...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            // Action Bar
            HStack {
                // Selection Info
                if isMultiSelectMode {
                    Text("\(selectedCount) of \(totalCount) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if selectedCount > 0 {
                        Button("Actions", action: onShowBatchActions)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                } else {
                    Text("\(totalCount) documents")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 16) {
                    Button(action: { showingFilters.toggle() }) {
                        Image(systemName: showingFilters ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease.circle")
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: { isMultiSelectMode.toggle() }) {
                        Image(systemName: isMultiSelectMode ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: onCreateDocument) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

struct DocumentsFilterView: View {
    @Binding var selectedContractFilter: String
    @Binding var selectedTypeFilter: String
    @Binding var sortOrder: DocumentSortOrder
    let availableContracts: [String]
    let availableTypes: [String]
    
    var body: some View {
        VStack(spacing: 12) {
            // Contract Filter
            HStack {
                Text("Contract:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Contract", selection: $selectedContractFilter) {
                    ForEach(availableContracts, id: \.self) { contract in
                        Text(contractDisplayName(contract)).tag(contract)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                
                Spacer()
            }
            
            // Type Filter
            HStack {
                Text("Type:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Type", selection: $selectedTypeFilter) {
                    ForEach(availableTypes, id: \.self) { type in
                        Text(type.capitalized).tag(type)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                
                Spacer()
            }
            
            // Sort Order
            HStack {
                Text("Sort:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Sort", selection: $sortOrder) {
                    ForEach(DocumentSortOrder.allCases, id: \.self) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
    }
    
    private func contractDisplayName(_ contractId: String) -> String {
        switch contractId {
        case "All Contracts":
            return "All Contracts"
        case "dashpay-contract":
            return "DashPay"
        case "dpns-contract":
            return "DPNS"
        case "note-taking-contract":
            return "Notes"
        case "contacts-contract":
            return "Contacts"
        default:
            return contractId.prefix(12) + "..."
        }
    }
}

struct DocumentsEmptyStateView: View {
    let searchText: String
    let hasFilters: Bool
    let onCreateDocument: () -> Void
    let onClearFilters: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: searchText.isEmpty ? "doc.text" : "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(emptyStateTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(emptyStateMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 12) {
                if hasFilters || !searchText.isEmpty {
                    Button("Clear Filters", action: onClearFilters)
                        .foregroundColor(.blue)
                }
                
                Button(action: onCreateDocument) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Create Document")
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    private var emptyStateTitle: String {
        if !searchText.isEmpty {
            return "No Results Found"
        } else if hasFilters {
            return "No Documents Match Filters"
        } else {
            return "No Documents"
        }
    }
    
    private var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "Try adjusting your search terms or clear filters to see more results."
        } else if hasFilters {
            return "No documents match your current filter settings. Try adjusting the filters or create a new document."
        } else {
            return "Create documents to see them here. Documents can store any structured data on Dash Platform."
        }
    }
}

struct EnhancedDocumentRow: View {
    let document: DocumentModel
    let isSelected: Bool
    let isMultiSelectMode: Bool
    let onTap: () -> Void
    let onToggleSelection: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Selection Circle
                if isMultiSelectMode {
                    Button(action: onToggleSelection) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .blue : .secondary)
                            .font(.title3)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Document Icon
                Image(systemName: documentIcon(for: document.documentType))
                    .font(.title2)
                    .foregroundColor(documentColor(for: document.documentType))
                    .frame(width: 32)
                
                // Document Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(document.documentType.capitalized)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("Rev. \(document.revision)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .cornerRadius(4)
                    }
                    
                    // Document Summary
                    Text(documentSummary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    // Metadata
                    HStack {
                        Text(contractDisplayName)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .cornerRadius(4)
                        
                        Spacer()
                        
                        if let updatedAt = document.updatedAt {
                            Text(formatRelativeDate(updatedAt))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Chevron
                if !isMultiSelectMode {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
    
    private var documentSummary: String {
        let data = document.data
        
        switch document.documentType {
        case "profile":
            if let displayName = data["displayName"] as? String,
               let message = data["publicMessage"] as? String {
                return "\(displayName): \(message)"
            }
        case "domain":
            if let label = data["label"] as? String {
                return "\(label).dash"
            }
        case "note":
            if let title = data["title"] as? String,
               let content = data["content"] as? String {
                return "\(title): \(content.prefix(50))..."
            }
        case "contact":
            if let name = data["name"] as? String,
               let company = data["company"] as? String {
                return "\(name) - \(company)"
            }
        default:
            break
        }
        
        // Fallback to first few data values
        let values = data.values.compactMap { "\($0)" }.prefix(2)
        return values.joined(separator: ", ")
    }
    
    private var contractDisplayName: String {
        switch document.contractId {
        case "dashpay-contract":
            return "DashPay"
        case "dpns-contract":
            return "DPNS"
        case "note-taking-contract":
            return "Notes"
        case "contacts-contract":
            return "Contacts"
        default:
            return String(document.contractId.prefix(8))
        }
    }
    
    private func documentIcon(for type: String) -> String {
        switch type.lowercased() {
        case "profile":
            return "person.crop.circle.fill"
        case "domain":
            return "globe"
        case "note":
            return "note.text"
        case "contact":
            return "person.crop.rectangle.stack.fill"
        case "message":
            return "message.fill"
        case "file":
            return "doc.fill"
        default:
            return "doc.text.fill"
        }
    }
    
    private func documentColor(for type: String) -> Color {
        switch type.lowercased() {
        case "profile":
            return .blue
        case "domain":
            return .green
        case "note":
            return .orange
        case "contact":
            return .purple
        case "message":
            return .pink
        case "file":
            return .gray
        default:
            return .primary
        }
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Sort Order Enum

enum DocumentSortOrder: String, CaseIterable {
    case createdDateDesc = "created_desc"
    case createdDateAsc = "created_asc"
    case updatedDateDesc = "updated_desc"
    case updatedDateAsc = "updated_asc"
    case documentType = "type"
    case revision = "revision"
    
    var displayName: String {
        switch self {
        case .createdDateDesc:
            return "Created (Newest)"
        case .createdDateAsc:
            return "Created (Oldest)"
        case .updatedDateDesc:
            return "Updated (Newest)"
        case .updatedDateAsc:
            return "Updated (Oldest)"
        case .documentType:
            return "Type"
        case .revision:
            return "Revision"
        }
    }
}

#Preview {
    EnhancedDocumentsView()
        .environmentObject(AppState())
}