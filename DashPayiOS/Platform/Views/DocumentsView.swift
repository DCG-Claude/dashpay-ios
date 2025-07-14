import SwiftUI

struct DocumentsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingCreateDocument = false
    @State private var selectedDocument: DocumentModel?
    @State private var isLoading = false
    @State private var selectedContract: ContractModel?
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading documents...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // Contract Selection Section
                        if !appState.contracts.isEmpty {
                            Section("Contract") {
                                Picker("Select Contract", selection: $selectedContract) {
                                    Text("All Contracts").tag(nil as ContractModel?)
                                    ForEach(appState.contracts) { contract in
                                        Text(contract.name).tag(contract as ContractModel?)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                            }
                        }
                        
                        // Documents Section
                        Section("Documents") {
                            if filteredDocuments.isEmpty {
                                EmptyStateView(
                                    systemImage: "doc.text",
                                    title: "No Documents",
                                    message: selectedContract == nil 
                                        ? "Load documents from Platform or select a contract"
                                        : "No documents found for \(selectedContract!.name)"
                                )
                                .listRowBackground(Color.clear)
                            } else {
                                ForEach(filteredDocuments) { document in
                                    DocumentRow(document: document) {
                                        selectedDocument = document
                                    }
                                }
                                .onDelete { indexSet in
                                    deleteDocuments(at: indexSet)
                                }
                            }
                        }
                    }
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { refreshDocuments() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    
                    Button(action: { showingCreateDocument = true }) {
                        Image(systemName: "plus")
                    }
                    .disabled(selectedContract == nil)
                }
            }
            .sheet(isPresented: $showingCreateDocument) {
                if let contract = selectedContract {
                    DocumentCreationWizardView(contract: contract)
                        .environmentObject(appState)
                } else {
                    ContractSelectionView { contract in
                        selectedContract = contract
                        showingCreateDocument = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showingCreateDocument = true
                        }
                    }
                }
            }
            .sheet(item: $selectedDocument) { document in
                DocumentDetailView(document: document)
                    .environmentObject(appState)
            }
            .onAppear {
                loadDocuments()
            }
            .onChange(of: selectedContract) { _ in
                refreshDocuments()
            }
        }
    }
    
    private var filteredDocuments: [DocumentModel] {
        if let selectedContract = selectedContract {
            return appState.documents.filter { $0.contractId == selectedContract.id }
        }
        return appState.documents
    }
    
    private func loadDocuments() {
        Task {
            await loadDocumentsFromPlatform()
        }
    }
    
    private func refreshDocuments() {
        Task {
            await loadDocumentsFromPlatform()
        }
    }
    
    @MainActor
    private func loadDocumentsFromPlatform() async {
        guard let documentService = appState.documentService else {
            errorMessage = "Document service not available"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            var allDocuments: [DocumentModel] = []
            
            if let selectedContract = selectedContract {
                // Load documents for specific contract
                for documentType in selectedContract.documentTypes {
                    let documents = try await documentService.getDocumentsByType(
                        contractId: selectedContract.id,
                        documentType: documentType,
                        limit: 100
                    )
                    allDocuments.append(contentsOf: documents)
                }
            } else {
                // Load documents from all contracts
                for contract in appState.contracts {
                    for documentType in contract.documentTypes {
                        do {
                            let documents = try await documentService.getDocumentsByType(
                                contractId: contract.id,
                                documentType: documentType,
                                limit: 50
                            )
                            allDocuments.append(contentsOf: documents)
                        } catch {
                            print("⚠️ Failed to load documents for contract \(contract.name): \(error)")
                            // Continue loading from other contracts
                        }
                    }
                }
            }
            
            appState.documents = allDocuments
            
        } catch {
            errorMessage = "Failed to load documents: \(error.localizedDescription)"
            print("🔴 Error loading documents: \(error)")
        }
        
        isLoading = false
    }
    
    private func deleteDocuments(at offsets: IndexSet) {
        let documentsToDelete = offsets.map { filteredDocuments[$0] }
        
        Task {
            await deleteDocumentsFromPlatform(documentsToDelete)
        }
    }
    
    @MainActor
    private func deleteDocumentsFromPlatform(_ documents: [DocumentModel]) async {
        guard let documentService = appState.documentService else {
            appState.showError(message: "Document service not available")
            return
        }
        
        for document in documents {
            do {
                try await documentService.deleteDocument(document)
                // Remove from local state
                appState.documents.removeAll { $0.id == document.id }
                print("✅ Deleted document: \(document.id)")
            } catch {
                appState.showError(message: "Failed to delete document: \(error.localizedDescription)")
                print("🔴 Error deleting document \(document.id): \(error)")
            }
        }
    }
}

struct DocumentRow: View {
    let document: DocumentModel
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(document.documentType)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(document.contractId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 100)
                }
                
                Text("Owner: \(document.ownerIdString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if let createdAt = document.createdAt {
                    Text("Created: \(createdAt, formatter: dateFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}




// MARK: - Contract Selection View

struct ContractSelectionView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onContractSelected: (ContractModel) -> Void
    
    var body: some View {
        NavigationView {
            List {
                if appState.contracts.isEmpty {
                    Text("No contracts available")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(appState.contracts) { contract in
                        Button(action: {
                            onContractSelected(contract)
                            dismiss()
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contract.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Document Types: \(contract.documentTypes.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .navigationTitle("Select Contract")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()