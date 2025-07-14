import SwiftUI
import SwiftData

struct DocumentDetailView: View {
    let document: DocumentModel
    @EnvironmentObject var appState: AppState
    @State private var showEditView = false
    @State private var showRawData = false
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @State private var isCopied = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Document Header
                    DocumentHeaderSection(document: document)
                    
                    // Document Details
                    DocumentDetailsSection(document: document)
                    
                    // Document Data
                    DocumentDataSection(document: document, showRawData: $showRawData)
                    
                    // History Section
                    DocumentHistorySection(document: document)
                    
                    // Actions
                    DocumentActionsSection(
                        document: document,
                        isCopied: $isCopied,
                        onEdit: { showEditView = true },
                        onDelete: { showDeleteAlert = true }
                    )
                }
                .padding()
            }
            .navigationTitle("Document Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showEditView) {
                EditDocumentView(document: document)
                    .environmentObject(appState)
            }
            .alert("Delete Document", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    deleteDocument()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this document? This action cannot be undone.")
            }
        }
    }
    
    private func deleteDocument() {
        Task {
            await deleteDocumentFromPlatform()
        }
    }
    
    @MainActor
    private func deleteDocumentFromPlatform() async {
        guard let documentService = appState.documentService else {
            appState.showError(message: "Document service not available")
            return
        }
        
        isDeleting = true
        defer { isDeleting = false }
        
        do {
            try await documentService.deleteDocument(document)
            
            // Remove from local state
            appState.documents.removeAll { $0.id == document.id }
            
            appState.showError(message: "Document deleted successfully")
            dismiss()
            
        } catch {
            appState.showError(message: "Failed to delete document: \(error.localizedDescription)")
            print("🔴 Error deleting document: \(error)")
        }
    }
}

// MARK: - Document Header Section

struct DocumentHeaderSection: View {
    let document: DocumentModel
    
    var body: some View {
        VStack(spacing: 16) {
            // Document Icon
            Image(systemName: documentIcon(for: document.documentType))
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            // Document Title
            VStack(spacing: 4) {
                Text(document.documentType.capitalized)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                
                Text(document.documentType.capitalized)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(8)
                
                Text("Revision \(document.revision)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func documentIcon(for type: String) -> String {
        switch type.lowercased() {
        case "note", "text":
            return "doc.text.fill"
        case "profile", "user":
            return "person.fill"
        case "contact":
            return "person.crop.circle.fill"
        case "message":
            return "message.fill"
        case "file":
            return "doc.fill"
        default:
            return "doc.fill"
        }
    }
}

// MARK: - Document Details Section

struct DocumentDetailsSection: View {
    let document: DocumentModel
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Document Information")
            
            VStack(spacing: 0) {
                DocumentDetailRow(label: "Document ID", value: document.id, isMono: true)
                DocumentDetailRow(label: "Contract ID", value: document.contractId, isMono: true)
                DocumentDetailRow(label: "Owner ID", value: document.ownerIdString, isMono: true)
                DocumentDetailRow(label: "Document Type", value: document.documentType)
                DocumentDetailRow(label: "Revision", value: "\(document.revision)")
                if let created = document.createdAt {
                    DocumentDetailRow(label: "Created", value: formatDate(created))
                }
                if let updated = document.updatedAt {
                    DocumentDetailRow(label: "Last Updated", value: formatDate(updated))
                }
                DocumentDetailRow(label: "Data Properties", value: "\(document.data.count)")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Document Data Section

struct DocumentDataSection: View {
    let document: DocumentModel
    @Binding var showRawData: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Document Data")
            
            VStack(spacing: 0) {
                // Formatted Data Display
                ForEach(Array(document.data.keys.sorted()), id: \.self) { key in
                    if let value = document.data[key] {
                        DocumentDetailRow(label: key.capitalized, value: "\(value)")
                    }
                }
                
                if !document.data.isEmpty {
                    Divider()
                        .padding(.leading, 16)
                }
                
                // Raw Data Toggle
                HStack {
                    Text("Raw Data (JSON)")
                        .font(.body)
                    Spacer()
                    Button(showRawData ? "Hide" : "Show") {
                        withAnimation {
                            showRawData.toggle()
                        }
                    }
                    .font(.body)
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                
                if showRawData {
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        Text(document.formattedData)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                    .background(Color(.systemGray5))
                }
            }
        }
    }
}

// MARK: - Document History Section

struct DocumentHistorySection: View {
    let document: DocumentModel
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Document History")
            
            VStack(spacing: 0) {
                // Current revision
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Revision")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Revision \(document.revision)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Last Updated")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let updated = document.updatedAt {
                            Text(formatRelativeDate(updated))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No updates")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                
                if document.revision > 0 {
                    Divider()
                        .padding(.leading, 16)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Original Document")
                                .font(.body)
                            Text("Revision 0")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Created")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let created = document.createdAt {
                                Text(formatRelativeDate(created))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Unknown")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                }
            }
        }
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Document Actions Section

struct DocumentActionsSection: View {
    let document: DocumentModel
    @Binding var isCopied: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onEdit) {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                
                Button(action: onDelete) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(8)
                }
            }
            
            Button(action: copyDocumentId) {
                HStack {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    Text(isCopied ? "Copied!" : "Copy Document ID")
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.blue)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            Button(action: exportDocument) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Document")
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.blue)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }
    
    private func copyDocumentId() {
        Clipboard.copy(document.id)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
    
    private func exportDocument() {
        let documentData = """
        Document ID: \(document.id)
        Contract ID: \(document.contractId)
        Owner ID: \(document.ownerIdString)
        Document Type: \(document.documentType)
        Revision: \(document.revision)
        Created: \(document.createdAt?.description ?? "Unknown")
        Last Updated: \(document.updatedAt?.description ?? "Not updated")
        
        Data:
        \(document.formattedData)
        """
        
        Clipboard.copy(documentData)
    }
}

// MARK: - Edit Document View

struct EditDocumentView: View {
    let document: DocumentModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var editedData: String
    @State private var isUpdating = false
    
    init(document: DocumentModel) {
        self.document = document
        self._editedData = State(initialValue: document.formattedData)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Document Information") {
                    Text("Document Type: \(document.documentType)")
                        .foregroundColor(.secondary)
                    Text("Current Revision: \(document.revision)")
                        .foregroundColor(.secondary)
                }
                
                Section("Document Data (JSON)") {
                    TextField("Enter JSON data", text: $editedData, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(10...20)
                }
                
                Section {
                    Text("Modify the document data as valid JSON. Saving will create a new revision of the document.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if isUpdating {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Updating document...")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Edit Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        updateDocument()
                    }
                    .disabled(editedData.isEmpty || editedData == document.formattedData || isUpdating)
                }
            }
        }
    }
    
    private func updateDocument() {
        // Validate JSON
        guard let jsonData = editedData.data(using: .utf8),
              let newData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            appState.showError(message: "Invalid JSON data")
            return
        }
        
        Task {
            await updateDocumentOnPlatform(newData: newData)
        }
    }
    
    @MainActor
    private func updateDocumentOnPlatform(newData: [String: Any]) async {
        guard let documentService = appState.documentService else {
            appState.showError(message: "Document service not available")
            return
        }
        
        isUpdating = true
        defer { isUpdating = false }
        
        do {
            let updatedDocument = try await documentService.updateDocument(document, newData: newData)
            
            // Update in local state
            if let index = appState.documents.firstIndex(where: { $0.id == document.id }) {
                appState.documents[index] = updatedDocument
            }
            
            appState.showError(message: "Document updated successfully")
            dismiss()
            
        } catch {
            appState.showError(message: "Failed to update document: \(error.localizedDescription)")
            print("🔴 Error updating document: \(error)")
        }
    }
}

// MARK: - DocumentDetailRow

struct DocumentDetailRow: View {
    let label: String
    let value: String
    let isMono: Bool
    
    init(label: String, value: String, isMono: Bool = false) {
        self.label = label
        self.value = value
        self.isMono = isMono
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(isMono ? .system(.subheadline, design: .monospaced) : .subheadline)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

#Preview {
    let document = DocumentModel(
        id: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        contractId: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        documentType: "note",
        ownerId: Data(repeating: 0xFE, count: 32),
        data: [
            "title": "My Test Note",
            "content": "This is a test note document stored on Dash Platform",
            "tags": ["test", "platform"],
            "created": "2024-01-15T10:30:00Z"
        ],
        createdAt: Date(),
        updatedAt: Date()
    )
    
    DocumentDetailView(document: document)
        .environmentObject(AppState())
}