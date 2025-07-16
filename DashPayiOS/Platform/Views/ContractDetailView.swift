import SwiftUI
import SwiftData

struct ContractDetailView: View {
    let contract: ContractModel
    @EnvironmentObject var appState: AppState
    @State private var showRawSchema = false
    @State private var showCreateDocument = false
    @State private var isRefreshing = false
    @State private var isCopied = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Contract Header
                    ContractHeaderSection(
                        contract: contract,
                        isRefreshing: $isRefreshing,
                        onRefresh: refreshContract
                    )
                    
                    // Contract Details
                    ContractDetailsSection(contract: contract)
                    
                    // Schema Section
                    ContractSchemaSection(contract: contract, showRawSchema: $showRawSchema)
                    
                    // Documents Section
                    ContractDocumentsSection(
                        contract: contract,
                        onCreateDocument: { showCreateDocument = true }
                    )
                    
                    // Actions
                    ContractActionsSection(contract: contract, isCopied: $isCopied)
                }
                .padding()
            }
            .navigationTitle("Contract Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCreateDocument) {
                CreateDocumentView(contract: contract)
                    .environmentObject(appState)
            }
        }
    }
    
    private func refreshContract() {
        Task {
            isRefreshing = true
            defer { isRefreshing = false }
            
            // TODO: Implement contract refresh from Platform SDK
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

// MARK: - Contract Header Section

struct ContractHeaderSection: View {
    let contract: ContractModel
    @Binding var isRefreshing: Bool
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Contract Icon
            Image(systemName: "doc.text.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            // Contract Name
            VStack(spacing: 4) {
                Text(contract.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Data Contract")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
                
                HStack(spacing: 8) {
                    Text("Version \(contract.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Contract Details Section

struct ContractDetailsSection: View {
    let contract: ContractModel
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Contract Information")
            
            VStack(spacing: 0) {
                ContractDetailRow(label: "Contract ID", value: contract.id, isMono: true)
                ContractDetailRow(label: "Owner ID", value: contract.ownerIdString, isMono: true)
                ContractDetailRow(label: "Name", value: contract.name)
                ContractDetailRow(label: "Version", value: "\(contract.version)")
                ContractDetailRow(label: "Document Types", value: "\(contract.documentTypes.count)")
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

// MARK: - Contract Schema Section

struct ContractSchemaSection: View {
    let contract: ContractModel
    @Binding var showRawSchema: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Schema Definition")
            
            VStack(spacing: 0) {
                // Document Types Summary
                ForEach(contract.documentTypes, id: \.self) { docType in
                    HStack {
                        Text(docType)
                            .font(.body)
                        Spacer()
                        Text("Document Type")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    
                    Divider()
                        .padding(.leading, 16)
                }
                
                // Raw Schema Toggle
                HStack {
                    Text("Raw Schema (JSON)")
                        .font(.body)
                    Spacer()
                    Button(showRawSchema ? "Hide" : "Show") {
                        withAnimation {
                            showRawSchema.toggle()
                        }
                    }
                    .font(.body)
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                
                if showRawSchema {
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        Text(contract.formattedSchema)
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

// MARK: - Contract Documents Section

struct ContractDocumentsSection: View {
    let contract: ContractModel
    let onCreateDocument: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Documents")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Button(action: onCreateDocument) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            
            VStack(spacing: 0) {
                if contract.documentTypes.count > 0 {
                    ContractDetailRow(label: "Total Document Types", value: "\(contract.documentTypes.count)")
                    
                    ForEach(contract.documentTypes, id: \.self) { docType in
                        HStack {
                            Text(docType)
                                .font(.body)
                            Spacer()
                            Text("View Documents")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .onTapGesture {
                            // TODO: Navigate to documents of this type
                        }
                        
                        Divider()
                            .padding(.leading, 16)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        
                        Text("No Documents")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Create your first document using this contract")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Create Document") {
                            onCreateDocument()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - Contract Actions Section

struct ContractActionsSection: View {
    let contract: ContractModel
    @Binding var isCopied: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: copyContractId) {
                HStack {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    Text(isCopied ? "Copied!" : "Copy Contract ID")
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(8)
            }
            
            Button(action: exportContract) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Contract")
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.blue)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }
    
    private func copyContractId() {
        Clipboard.copy(contract.id)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
    
    private func exportContract() {
        let contractData = """
        Contract ID: \(contract.id)
        Name: \(contract.name)
        Owner ID: \(contract.ownerIdString)
        Version: \(contract.version)
        Document Types: \(contract.documentTypes.joined(separator: ", "))
        
        Schema:
        \(contract.formattedSchema)
        """
        
        Clipboard.copy(contractData)
    }
}

// MARK: - Create Document View

struct CreateDocumentView: View {
    let contract: ContractModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDocumentType = ""
    @State private var documentData = ""
    @State private var isCreating = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Document Information") {
                    Picker("Document Type", selection: $selectedDocumentType) {
                        ForEach(contract.documentTypes, id: \.self) { docType in
                            Text(docType).tag(docType)
                        }
                    }
                    
                    if !selectedDocumentType.isEmpty {
                        Text("Creating document of type: \(selectedDocumentType)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Document Data (JSON)") {
                    TextField("Enter JSON data", text: $documentData, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(5...10)
                }
                
                Section {
                    Text("Enter the document data as valid JSON. The data must conform to the contract's schema for the selected document type.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if isCreating {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Creating document...")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Create Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createDocument()
                    }
                    .disabled(selectedDocumentType.isEmpty || documentData.isEmpty || isCreating)
                }
            }
        }
        .onAppear {
            if let firstDocType = contract.documentTypes.first {
                selectedDocumentType = firstDocType
            }
        }
    }
    
    private func createDocument() {
        // Validate JSON
        guard let jsonData = documentData.data(using: .utf8),
              let _ = try? JSONSerialization.jsonObject(with: jsonData) else {
            appState.showError(message: "Invalid JSON data")
            return
        }
        
        // TODO: Implement actual document creation using Platform SDK
        Task {
            isCreating = true
            defer { isCreating = false }
            
            // Simulate document creation
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            await MainActor.run {
                appState.showError(message: "Document created successfully")
                dismiss()
            }
        }
    }
}

// MARK: - ContractDetailRow

struct ContractDetailRow: View {
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
    let contract = ContractModel(
        id: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        name: "Test Contract",
        version: 1,
        ownerId: Data(repeating: 0xAB, count: 32),
        documentTypes: ["note", "profile", "contact"],
        schema: [
            "note": [
                "type": "object",
                "properties": [
                    "title": ["type": "string"],
                    "content": ["type": "string"]
                ]
            ]
        ]
    )
    
    ContractDetailView(contract: contract)
        .environmentObject(AppState())
}