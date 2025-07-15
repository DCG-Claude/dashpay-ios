import SwiftUI
import SwiftData
import UIKit

/// Clipboard utility for copying text to the system pasteboard
struct Clipboard {
    /// Copies text to the system clipboard using UIPasteboard
    /// - Parameter string: The text to copy to the clipboard
    static func copy(_ string: String) {
        DispatchQueue.main.async {
            UIPasteboard.general.string = string
        }
    }
}

/// Enhanced document detail view with editing, history, and advanced features
struct EnhancedDocumentDetailView: View {
    let document: DocumentModel
    @EnvironmentObject var appState: AppState
    @StateObject private var documentService: DocumentService
    
    @State private var showEditView = false
    @State private var showRawData = false
    @State private var showDeleteAlert = false
    @State private var showHistoryView = false
    @State private var showShareSheet = false
    @State private var isDeleting = false
    @State private var isCopied = false
    @State private var selectedTab: DetailTab = .overview
    @State private var documentHistory: [DocumentRevision] = []
    @Environment(\.dismiss) private var dismiss
    
    init(document: DocumentModel) {
        self.document = document
        
        // Initialize with placeholder values - will be properly injected
        let dummyContainer = try! ModelContainer.inMemoryContainer()
        let dummyDataManager = DataManager(modelContext: dummyContainer.mainContext)
        let dummyPlatformSDK = try! PlatformSDKWrapper(network: .testnet)
        self._documentService = StateObject(wrappedValue: DocumentService(platformSDK: dummyPlatformSDK, dataManager: dummyDataManager))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Document Header
                DocumentHeaderCard(document: document)
                    .padding(.horizontal)
                    .padding(.top)
                
                // Tab Navigation
                DetailTabNavigation(selectedTab: $selectedTab)
                    .padding(.horizontal)
                
                // Content
                TabView(selection: $selectedTab) {
                    // Overview Tab
                    DocumentOverviewTab(document: document, showRawData: $showRawData)
                        .tag(DetailTab.overview)
                    
                    // Properties Tab
                    DocumentPropertiesTab(document: document)
                        .tag(DetailTab.properties)
                    
                    // History Tab
                    DocumentHistoryTab(document: document, history: documentHistory)
                        .tag(DetailTab.history)
                    
                    // Metadata Tab
                    DocumentMetadataTab(document: document)
                        .tag(DetailTab.metadata)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .navigationTitle("Document Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showEditView = true }) {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Button(action: { showHistoryView = true }) {
                            Label("View History", systemImage: "clock.arrow.circlepath")
                        }
                        
                        Button(action: { copyDocumentId() }) {
                            Label("Copy ID", systemImage: "doc.on.doc")
                        }
                        
                        Button(action: { showShareSheet = true }) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: { showDeleteAlert = true }) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showEditView) {
                EnhancedEditDocumentView(document: document)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showHistoryView) {
                DocumentHistoryView(document: document, history: documentHistory)
            }
            .sheet(isPresented: $showShareSheet) {
                DocumentExportView(document: document)
            }
            .alert("Delete Document", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    deleteDocument()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this document? This action cannot be undone.")
            }
            .toast(isPresented: $isCopied, message: "Document ID copied to clipboard")
            .onAppear {
                setupDocumentService()
                loadDocumentHistory()
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
        print("📄 Setting up DocumentService for detail view")
    }
    
    private func loadDocumentHistory() {
        Task {
            do {
                let history = try await documentService.getDocumentHistory(documentId: document.id)
                await MainActor.run {
                    self.documentHistory = history
                }
            } catch {
                print("Failed to load document history: \(error)")
            }
        }
    }
    
    private func deleteDocument() {
        Task {
            isDeleting = true
            defer { isDeleting = false }
            
            do {
                try await documentService.deleteDocument(document)
                await MainActor.run {
                    appState.documents.removeAll { $0.id == document.id }
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    appState.showError(message: "Failed to delete document: \(error.localizedDescription)")
                }
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
}

// MARK: - Supporting Views

struct DocumentHeaderCard: View {
    let document: DocumentModel
    
    var body: some View {
        VStack(spacing: 16) {
            // Document Icon and Type
            HStack {
                Image(systemName: documentIcon(for: document.documentType))
                    .font(.system(size: 40))
                    .foregroundColor(documentColor(for: document.documentType))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.documentType.capitalized)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(contractDisplayName)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(documentColor(for: document.documentType))
                        .cornerRadius(8)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Revision")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(document.revision)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(documentColor(for: document.documentType))
                }
            }
            
            // Document Summary
            if !documentSummary.isEmpty {
                Text(documentSummary)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
            return String(document.contractId.prefix(12))
        }
    }
    
    private var documentSummary: String {
        let data = document.data
        
        switch document.documentType {
        case "profile":
            if let displayName = data["displayName"] as? String {
                return "Profile for \(displayName)"
            }
        case "domain":
            if let label = data["label"] as? String {
                return "\(label).dash domain registration"
            }
        case "note":
            if let title = data["title"] as? String {
                return title
            }
        case "contact":
            if let name = data["name"] as? String {
                return "Contact information for \(name)"
            }
        default:
            break
        }
        
        return ""
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
}

struct DetailTabNavigation: View {
    @Binding var selectedTab: DetailTab
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.title3)
                        
                        Text(tab.title)
                            .font(.caption)
                    }
                    .foregroundColor(selectedTab == tab ? .blue : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct DocumentOverviewTab: View {
    let document: DocumentModel
    @Binding var showRawData: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Key Information
                VStack(spacing: 0) {
                    SectionHeader(title: "Overview")
                    
                    VStack(spacing: 0) {
                        DetailRow(label: "Document ID", value: document.id)
                        DetailRow(label: "Owner ID", value: document.ownerIdString)
                        DetailRow(label: "Contract ID", value: document.contractId)
                        
                        if let created = document.createdAt {
                            DetailRow(label: "Created", value: formatDate(created))
                        }
                        
                        if let updated = document.updatedAt {
                            DetailRow(label: "Last Updated", value: formatDate(updated))
                        }
                        
                        DetailRow(label: "Data Properties", value: "\(document.data.count)")
                    }
                }
                
                // Quick Actions
                VStack(spacing: 0) {
                    SectionHeader(title: "Quick Actions")
                    
                    VStack(spacing: 12) {
                        DocumentQuickActionButton(
                            title: "Copy Document ID",
                            icon: "doc.on.doc",
                            action: { Clipboard.copy(document.id) }
                        )
                        
                        DocumentQuickActionButton(
                            title: showRawData ? "Hide Raw Data" : "Show Raw Data",
                            icon: showRawData ? "eye.slash" : "eye",
                            action: { showRawData.toggle() }
                        )
                        
                        DocumentQuickActionButton(
                            title: "Refresh from Platform",
                            icon: "arrow.clockwise",
                            action: { /* Implement refresh */ }
                        )
                    }
                    .padding()
                }
                
                // Raw Data (if shown)
                if showRawData {
                    VStack(spacing: 0) {
                        SectionHeader(title: "Raw Data (JSON)")
                        
                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            Text(document.formattedData)
                                .font(.system(.caption, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                    }
                }
            }
            .padding()
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct DocumentPropertiesTab: View {
    let document: DocumentModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 0) {
                    SectionHeader(title: "Document Properties")
                    
                    if document.data.isEmpty {
                        Text("No properties")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(document.data.keys.sorted()), id: \.self) { key in
                                if let value = document.data[key] {
                                    PropertyRow(key: key, value: value)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct PropertyRow: View {
    let key: String
    let value: Any
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(key.capitalized)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(valueType)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(4)
            }
            
            Text(formattedValue)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private var valueType: String {
        switch value {
        case is String:
            return "String"
        case is Int, is Int64:
            return "Integer"
        case is Double, is Float:
            return "Number"
        case is Bool:
            return "Boolean"
        case is [Any]:
            return "Array"
        case is [String: Any]:
            return "Object"
        default:
            return "Unknown"
        }
    }
    
    private var formattedValue: String {
        switch value {
        case let stringValue as String:
            return stringValue
        case let intValue as Int:
            return "\(intValue)"
        case let int64Value as Int64:
            return "\(int64Value)"
        case let doubleValue as Double:
            return "\(doubleValue)"
        case let floatValue as Float:
            return "\(floatValue)"
        case let boolValue as Bool:
            return boolValue ? "true" : "false"
        case let arrayValue as [Any]:
            return "[\(arrayValue.count) items]"
        case let dictValue as [String: Any]:
            return "{\(dictValue.count) properties}"
        default:
            return "\(value)"
        }
    }
}

struct DocumentHistoryTab: View {
    let document: DocumentModel
    let history: [DocumentRevision]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 0) {
                    SectionHeader(title: "Revision History")
                    
                    if history.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            
                            Text("No revision history available")
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            Text("Revision history will be available when the document is updated through the Platform.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(40)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(history) { revision in
                                RevisionRow(revision: revision)
                            }
                        }
                    }
                }
                
                // Current Revision Info
                VStack(spacing: 0) {
                    SectionHeader(title: "Current Revision")
                    
                    VStack(spacing: 0) {
                        DetailRow(label: "Revision Number", value: "\(document.revision)")
                        
                        if let updated = document.updatedAt {
                            DetailRow(label: "Last Modified", value: formatDate(updated))
                        }
                        
                        if let created = document.createdAt {
                            DetailRow(label: "Created", value: formatDate(created))
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct RevisionRow: View {
    let revision: DocumentRevision
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Revision \(revision.revision)")
                    .font(.headline)
                
                Text(formatDate(revision.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("View") {
                // Implement revision viewing
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct DocumentMetadataTab: View {
    let document: DocumentModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 0) {
                    SectionHeader(title: "Document Metadata")
                    
                    VStack(spacing: 0) {
                        DetailRow(label: "Document Type", value: document.documentType)
                        DetailRow(label: "Revision", value: "\(document.revision)")
                        DetailRow(label: "Contract ID", value: document.contractId)
                        DetailRow(label: "Owner ID", value: document.ownerIdString)
                        DetailRow(label: "Document ID", value: document.id)
                    }
                }
                
                VStack(spacing: 0) {
                    SectionHeader(title: "Timestamps")
                    
                    VStack(spacing: 0) {
                        if let created = document.createdAt {
                            DetailRow(label: "Created At", value: formatFullDate(created))
                        }
                        
                        if let updated = document.updatedAt {
                            DetailRow(label: "Updated At", value: formatFullDate(updated))
                        }
                    }
                }
                
                VStack(spacing: 0) {
                    SectionHeader(title: "Data Statistics")
                    
                    VStack(spacing: 0) {
                        DetailRow(label: "Property Count", value: "\(document.data.count)")
                        DetailRow(label: "Data Size", value: formatDataSize())
                    }
                }
            }
            .padding()
        }
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatDataSize() -> String {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: document.data) else {
            return "Unknown"
        }
        
        let bytes = jsonData.count
        if bytes < 1024 {
            return "\(bytes) bytes"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

struct DocumentQuickActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

// MARK: - Tab Enum

enum DetailTab: String, CaseIterable {
    case overview = "overview"
    case properties = "properties"
    case history = "history"
    case metadata = "metadata"
    
    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .properties:
            return "Properties"
        case .history:
            return "History"
        case .metadata:
            return "Metadata"
        }
    }
    
    var icon: String {
        switch self {
        case .overview:
            return "doc.text"
        case .properties:
            return "list.bullet.rectangle"
        case .history:
            return "clock.arrow.circlepath"
        case .metadata:
            return "info.circle"
        }
    }
}

// MARK: - Toast View Extension

extension View {
    func toast(isPresented: Binding<Bool>, message: String) -> some View {
        self.overlay(
            ToastView(message: message, isPresented: isPresented)
                .animation(.easeInOut, value: isPresented.wrappedValue)
        )
    }
}

struct ToastView: View {
    let message: String
    @Binding var isPresented: Bool
    
    var body: some View {
        if isPresented {
            VStack {
                Spacer()
                
                Text(message)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(8)
                    .padding(.bottom, 50)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            isPresented = false
                        }
                    }
            }
        }
    }
}

#Preview {
    let document = DocumentModel(
        id: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        contractId: "note-taking-contract",
        documentType: "note",
        ownerId: Data(repeating: 0xFE, count: 32),
        data: [
            "title": "My Test Note",
            "content": "This is a test note document stored on Dash Platform",
            "tags": ["test", "platform"],
            "isPublic": false
        ],
        createdAt: Date().addingTimeInterval(-86400),
        updatedAt: Date().addingTimeInterval(-3600)
    )
    
    EnhancedDocumentDetailView(document: document)
        .environmentObject(AppState())
}