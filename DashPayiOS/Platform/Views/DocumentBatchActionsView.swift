import SwiftUI
import SwiftData

/// Batch operations view for multiple document actions
struct DocumentBatchActionsView: View {
    let selectedDocuments: [String]
    let documents: [DocumentModel]
    let onDismiss: () -> Void
    
    @EnvironmentObject var appState: AppState
    @StateObject private var documentService: DocumentService
    @State private var showingDeleteAlert = false
    @State private var showingExportSheet = false
    @State private var showingBulkEditSheet = false
    @State private var isProcessing = false
    @State private var operationProgress: Double = 0.0
    @State private var currentOperation: String = ""
    
    private var selectedDocumentModels: [DocumentModel] {
        documents.filter { selectedDocuments.contains($0.id) }
    }
    
    init(selectedDocuments: [String], documents: [DocumentModel], onDismiss: @escaping () -> Void) {
        self.selectedDocuments = selectedDocuments
        self.documents = documents
        self.onDismiss = onDismiss
        
        // Initialize with placeholder values - will be properly injected
        let dummyDataManager = DataManager(modelContext: ModelContext(try! ModelContainer.inMemoryContainer()))
        let dummyPlatformSDK = try! PlatformSDKWrapper(network: .testnet)
        self._documentService = StateObject(wrappedValue: DocumentService(platformSDK: dummyPlatformSDK, dataManager: dummyDataManager))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Batch Operations")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("\(selectedDocuments.count) documents selected")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    // Progress Bar (when processing)
                    if isProcessing {
                        VStack(spacing: 8) {
                            ProgressView(value: operationProgress, total: 1.0)
                                .progressViewStyle(LinearProgressViewStyle())
                            
                            Text(currentOperation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                
                // Selected Documents Preview
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(selectedDocumentModels.prefix(5)) { document in
                            BatchDocumentRow(document: document)
                        }
                        
                        if selectedDocumentModels.count > 5 {
                            Text("... and \(selectedDocumentModels.count - 5) more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                    .padding()
                }
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    BatchActionButton(
                        title: "Bulk Edit Properties",
                        icon: "pencil.circle",
                        color: .blue,
                        isEnabled: !isProcessing
                    ) {
                        showingBulkEditSheet = true
                    }
                    
                    BatchActionButton(
                        title: "Export Documents",
                        icon: "square.and.arrow.up.circle",
                        color: .green,
                        isEnabled: !isProcessing
                    ) {
                        showingExportSheet = true
                    }
                    
                    BatchActionButton(
                        title: "Refresh from Platform",
                        icon: "arrow.clockwise.circle",
                        color: .orange,
                        isEnabled: !isProcessing
                    ) {
                        refreshDocuments()
                    }
                    
                    BatchActionButton(
                        title: "Delete Documents",
                        icon: "trash.circle",
                        color: .red,
                        isEnabled: !isProcessing
                    ) {
                        showingDeleteAlert = true
                    }
                }
                .padding()
            }
            .navigationTitle("Batch Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done", action: onDismiss)
                }
            }
            .alert("Delete Documents", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    deleteDocuments()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete \(selectedDocuments.count) documents? This action cannot be undone.")
            }
            .sheet(isPresented: $showingExportSheet) {
                BatchExportView(documents: selectedDocumentModels)
            }
            .sheet(isPresented: $showingBulkEditSheet) {
                BulkEditView(documents: selectedDocumentModels) { updatedDocuments in
                    updateDocuments(updatedDocuments)
                }
            }
            .onAppear {
                setupDocumentService()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupDocumentService() {
        guard let platformSDK = appState.platformSDK,
              let dataManager = appState.dataManager else {
            return
        }
        
        print("📄 Setting up DocumentService for batch operations")
    }
    
    private func refreshDocuments() {
        Task {
            isProcessing = true
            currentOperation = "Refreshing documents from Platform..."
            operationProgress = 0.0
            
            defer {
                isProcessing = false
                currentOperation = ""
                operationProgress = 0.0
            }
            
            let totalDocuments = selectedDocumentModels.count
            
            for (index, document) in selectedDocumentModels.enumerated() {
                currentOperation = "Refreshing \(document.documentType) document..."
                operationProgress = Double(index) / Double(totalDocuments)
                
                do {
                    let refreshedDocument = try await documentService.fetchDocument(
                        contractId: document.contractId,
                        documentType: document.documentType,
                        documentId: document.id,
                        forceRefresh: true
                    )
                    
                    await MainActor.run {
                        // Update the document in the app state
                        if let index = appState.documents.firstIndex(where: { $0.id == document.id }) {
                            appState.documents[index] = refreshedDocument
                        }
                    }
                } catch {
                    print("Failed to refresh document \(document.id): \(error)")
                }
                
                // Small delay to show progress
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            operationProgress = 1.0
            currentOperation = "Refresh completed"
            
            // Auto-dismiss after a short delay
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await MainActor.run {
                onDismiss()
            }
        }
    }
    
    private func deleteDocuments() {
        Task {
            isProcessing = true
            currentOperation = "Deleting documents..."
            operationProgress = 0.0
            
            defer {
                isProcessing = false
                currentOperation = ""
                operationProgress = 0.0
            }
            
            let totalDocuments = selectedDocumentModels.count
            var deletedCount = 0
            
            for (index, document) in selectedDocumentModels.enumerated() {
                currentOperation = "Deleting \(document.documentType) document..."
                operationProgress = Double(index) / Double(totalDocuments)
                
                do {
                    try await documentService.deleteDocument(document)
                    deletedCount += 1
                    
                    await MainActor.run {
                        appState.documents.removeAll { $0.id == document.id }
                    }
                } catch {
                    print("Failed to delete document \(document.id): \(error)")
                }
                
                // Small delay to show progress
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            operationProgress = 1.0
            currentOperation = "Deleted \(deletedCount) documents"
            
            // Auto-dismiss after a short delay
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await MainActor.run {
                onDismiss()
            }
        }
    }
    
    private func updateDocuments(_ updates: [(document: DocumentModel, newData: [String: Any])]) {
        Task {
            isProcessing = true
            currentOperation = "Updating documents..."
            operationProgress = 0.0
            
            defer {
                isProcessing = false
                currentOperation = ""
                operationProgress = 0.0
            }
            
            let totalUpdates = updates.count
            var updatedCount = 0
            
            for (index, update) in updates.enumerated() {
                currentOperation = "Updating \(update.document.documentType) document..."
                operationProgress = Double(index) / Double(totalUpdates)
                
                do {
                    let updatedDocument = try await documentService.updateDocument(
                        update.document,
                        newData: update.newData
                    )
                    updatedCount += 1
                    
                    await MainActor.run {
                        if let docIndex = appState.documents.firstIndex(where: { $0.id == update.document.id }) {
                            appState.documents[docIndex] = updatedDocument
                        }
                    }
                } catch {
                    print("Failed to update document \(update.document.id): \(error)")
                }
                
                // Small delay to show progress
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            operationProgress = 1.0
            currentOperation = "Updated \(updatedCount) documents"
            
            // Auto-dismiss after a short delay
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await MainActor.run {
                onDismiss()
            }
        }
    }
}

// MARK: - Supporting Views

struct BatchDocumentRow: View {
    let document: DocumentModel
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: documentIcon(for: document.documentType))
                .font(.title3)
                .foregroundColor(documentColor(for: document.documentType))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(document.documentType.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(document.id.prefix(16) + "...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text("Rev. \(document.revision)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(.systemGray5))
                .cornerRadius(4)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func documentIcon(for type: String) -> String {
        switch type.lowercased() {
        case "profile":
            return "person.crop.circle"
        case "domain":
            return "globe"
        case "note":
            return "note.text"
        case "contact":
            return "person.crop.rectangle.stack"
        case "message":
            return "message"
        case "file":
            return "doc"
        default:
            return "doc.text"
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
}

struct BatchActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .foregroundColor(isEnabled ? color : .secondary)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .disabled(!isEnabled)
    }
}

struct BatchExportView: View {
    let documents: [DocumentModel]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .json
    @State private var includeMetadata = true
    @State private var isExporting = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    
                    Text("Export Documents")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Export \(documents.count) selected documents")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Export Options
                VStack(spacing: 16) {
                    // Format Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Export Format")
                            .font(.headline)
                        
                        Picker("Format", selection: $selectedFormat) {
                            ForEach(ExportFormat.allCases, id: \.self) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    // Options
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Options")
                            .font(.headline)
                        
                        Toggle("Include Metadata", isOn: $includeMetadata)
                    }
                    
                    // Format Description
                    Text(selectedFormat.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .padding()
                
                Spacer()
                
                // Export Button
                Button(action: exportDocuments) {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isExporting ? "Exporting..." : "Export Documents")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(12)
                }
                .disabled(isExporting)
                .padding()
            }
            .navigationTitle("Export")
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
    
    private func exportDocuments() {
        isExporting = true
        
        // Simulate export process
        Task {
            defer { isExporting = false }
            
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            let exportData = generateExportData()
            Clipboard.copy(exportData)
            
            await MainActor.run {
                dismiss()
            }
        }
    }
    
    private func generateExportData() -> String {
        switch selectedFormat {
        case .json:
            return generateJSONExport()
        case .csv:
            return generateCSVExport()
        case .txt:
            return generateTextExport()
        }
    }
    
    private func generateJSONExport() -> String {
        var exportData: [[String: Any]] = []
        
        for document in documents {
            var docData: [String: Any] = document.data
            
            if includeMetadata {
                docData["_id"] = document.id
                docData["_contractId"] = document.contractId
                docData["_documentType"] = document.documentType
                docData["_ownerId"] = document.ownerIdString
                docData["_revision"] = document.revision
                docData["_createdAt"] = document.createdAt?.ISO8601Format()
                docData["_updatedAt"] = document.updatedAt?.ISO8601Format()
            }
            
            exportData.append(docData)
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "Failed to generate JSON export"
        }
        
        return jsonString
    }
    
    private func generateCSVExport() -> String {
        var csv = ""
        
        // Get all unique keys from all documents
        var allKeys: Set<String> = []
        for document in documents {
            allKeys.formUnion(document.data.keys)
        }
        
        if includeMetadata {
            allKeys.insert("_id")
            allKeys.insert("_contractId")
            allKeys.insert("_documentType")
            allKeys.insert("_ownerId")
            allKeys.insert("_revision")
            allKeys.insert("_createdAt")
            allKeys.insert("_updatedAt")
        }
        
        let sortedKeys = allKeys.sorted()
        
        // Header row
        csv += sortedKeys.joined(separator: ",") + "\n"
        
        // Data rows
        for document in documents {
            var row: [String] = []
            
            for key in sortedKeys {
                let value: String
                
                if includeMetadata && key.hasPrefix("_") {
                    switch key {
                    case "_id":
                        value = document.id
                    case "_contractId":
                        value = document.contractId
                    case "_documentType":
                        value = document.documentType
                    case "_ownerId":
                        value = document.ownerIdString
                    case "_revision":
                        value = "\(document.revision)"
                    case "_createdAt":
                        value = document.createdAt?.ISO8601Format() ?? ""
                    case "_updatedAt":
                        value = document.updatedAt?.ISO8601Format() ?? ""
                    default:
                        value = ""
                    }
                } else {
                    value = document.data[key].map { "\($0)" } ?? ""
                }
                
                // Escape commas and quotes in CSV
                let escapedValue = value.replacingOccurrences(of: "\"", with: "\"\"")
                row.append("\"\(escapedValue)\"")
            }
            
            csv += row.joined(separator: ",") + "\n"
        }
        
        return csv
    }
    
    private func generateTextExport() -> String {
        var text = "Document Export\n"
        text += "================\n\n"
        
        for (index, document) in documents.enumerated() {
            text += "Document \(index + 1):\n"
            text += "- Type: \(document.documentType)\n"
            text += "- ID: \(document.id)\n"
            
            if includeMetadata {
                text += "- Contract: \(document.contractId)\n"
                text += "- Owner: \(document.ownerIdString)\n"
                text += "- Revision: \(document.revision)\n"
                if let created = document.createdAt {
                    text += "- Created: \(created)\n"
                }
                if let updated = document.updatedAt {
                    text += "- Updated: \(updated)\n"
                }
            }
            
            text += "- Data:\n"
            for (key, value) in document.data.sorted(by: { $0.key < $1.key }) {
                text += "  \(key): \(value)\n"
            }
            
            text += "\n"
        }
        
        return text
    }
}

enum ExportFormat: String, CaseIterable {
    case json = "json"
    case csv = "csv"
    case txt = "txt"
    
    var displayName: String {
        switch self {
        case .json:
            return "JSON"
        case .csv:
            return "CSV"
        case .txt:
            return "Text"
        }
    }
    
    var description: String {
        switch self {
        case .json:
            return "Export as structured JSON data, preserving all data types and structure."
        case .csv:
            return "Export as comma-separated values, suitable for spreadsheet applications."
        case .txt:
            return "Export as human-readable text format."
        }
    }
}

struct BulkEditView: View {
    let documents: [DocumentModel]
    let onUpdate: ([(document: DocumentModel, newData: [String: Any])]) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: BulkEditMode = .addProperty
    @State private var propertyKey = ""
    @State private var propertyValue = ""
    @State private var selectedProperty = ""
    @State private var newValue = ""
    
    // Get common properties across all documents
    private var commonProperties: [String] {
        guard !documents.isEmpty else { return [] }
        
        var common = Set(documents.first!.data.keys)
        for document in documents.dropFirst() {
            common = common.intersection(Set(document.data.keys))
        }
        
        return Array(common).sorted()
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("Bulk Edit")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Edit \(documents.count) documents at once")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Edit Mode Selection
                Picker("Edit Mode", selection: $editMode) {
                    ForEach(BulkEditMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Edit Form
                VStack(spacing: 16) {
                    switch editMode {
                    case .addProperty:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add Property")
                                .font(.headline)
                            
                            TextField("Property Key", text: $propertyKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            TextField("Property Value", text: $propertyValue)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                    case .updateProperty:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Update Property")
                                .font(.headline)
                            
                            Picker("Property", selection: $selectedProperty) {
                                Text("Select Property").tag("")
                                ForEach(commonProperties, id: \.self) { property in
                                    Text(property).tag(property)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            
                            TextField("New Value", text: $newValue)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                    case .removeProperty:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Remove Property")
                                .font(.headline)
                            
                            Picker("Property", selection: $selectedProperty) {
                                Text("Select Property").tag("")
                                ForEach(commonProperties, id: \.self) { property in
                                    Text(property).tag(property)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                    }
                }
                .padding()
                
                Spacer()
                
                // Apply Button
                Button(action: applyChanges) {
                    Text("Apply to \(documents.count) Documents")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canApply ? Color.blue : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!canApply)
                .padding()
            }
            .navigationTitle("Bulk Edit")
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
    
    private var canApply: Bool {
        switch editMode {
        case .addProperty:
            return !propertyKey.isEmpty && !propertyValue.isEmpty
        case .updateProperty:
            return !selectedProperty.isEmpty && !newValue.isEmpty
        case .removeProperty:
            return !selectedProperty.isEmpty
        }
    }
    
    private func applyChanges() {
        var updates: [(document: DocumentModel, newData: [String: Any])] = []
        
        for document in documents {
            var newData = document.data
            
            switch editMode {
            case .addProperty:
                newData[propertyKey] = propertyValue
            case .updateProperty:
                newData[selectedProperty] = newValue
            case .removeProperty:
                newData.removeValue(forKey: selectedProperty)
            }
            
            updates.append((document: document, newData: newData))
        }
        
        onUpdate(updates)
        dismiss()
    }
}

enum BulkEditMode: String, CaseIterable {
    case addProperty = "add"
    case updateProperty = "update"
    case removeProperty = "remove"
    
    var displayName: String {
        switch self {
        case .addProperty:
            return "Add"
        case .updateProperty:
            return "Update"
        case .removeProperty:
            return "Remove"
        }
    }
}

#Preview {
    let sampleDocuments = [
        DocumentModel(
            id: "doc1",
            contractId: "contract1",
            documentType: "note",
            ownerId: Data(repeating: 0x01, count: 32),
            data: ["title": "Note 1", "content": "Content 1"]
        ),
        DocumentModel(
            id: "doc2",
            contractId: "contract1",
            documentType: "note",
            ownerId: Data(repeating: 0x02, count: 32),
            data: ["title": "Note 2", "content": "Content 2"]
        )
    ]
    
    DocumentBatchActionsView(
        selectedDocuments: ["doc1", "doc2"],
        documents: sampleDocuments,
        onDismiss: {}
    )
    .environmentObject(AppState())
}