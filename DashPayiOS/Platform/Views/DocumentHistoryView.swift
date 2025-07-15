import SwiftUI

/// Document history and revision tracking view
struct DocumentHistoryView: View {
    let document: DocumentModel
    let history: [DocumentRevision]
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRevision: DocumentRevision?
    @State private var showingRevisionDetail = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                DocumentHistoryHeader(document: document)
                    .padding()
                    .background(Color(.systemGray6))
                
                // History Content
                if history.isEmpty {
                    EmptyHistoryView()
                } else {
                    HistoryTimelineView(
                        document: document,
                        history: history,
                        onRevisionSelect: { revision in
                            selectedRevision = revision
                            showingRevisionDetail = true
                        }
                    )
                }
                
                Spacer()
            }
            .navigationTitle("Document History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingRevisionDetail) {
                if let revision = selectedRevision {
                    RevisionDetailView(revision: revision, document: document)
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct DocumentHistoryHeader: View {
    let document: DocumentModel
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: documentIcon)
                    .font(.title2)
                    .foregroundColor(documentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.documentType.capitalized)
                        .font(.headline)
                    
                    Text(document.id)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Current")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Rev. \(document.revision)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(documentColor)
                }
            }
            
            // History Stats
            HStack {
                HistoryStatCard(title: "Total Revisions", value: "\(document.revision + 1)")
                HistoryStatCard(title: "Created", value: formatDate(document.createdAt))
                HistoryStatCard(title: "Last Updated", value: formatDate(document.updatedAt))
            }
        }
    }
    
    private var documentIcon: String {
        switch document.documentType.lowercased() {
        case "profile":
            return "person.crop.circle"
        case "domain":
            return "globe"
        case "note":
            return "note.text"
        case "contact":
            return "person.crop.rectangle.stack"
        default:
            return "doc.text"
        }
    }
    
    private var documentColor: Color {
        switch document.documentType.lowercased() {
        case "profile":
            return .blue
        case "domain":
            return .green
        case "note":
            return .orange
        case "contact":
            return .purple
        default:
            return .primary
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct HistoryStatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No History Available")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Document history will appear here when the document is updated through the Platform.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 12) {
                HistoryFeatureCard(
                    icon: "doc.text.magnifyingglass",
                    title: "Revision Tracking",
                    description: "Track every change made to the document"
                )
                
                HistoryFeatureCard(
                    icon: "clock.badge.checkmark",
                    title: "Timestamp History",
                    description: "See when each revision was created"
                )
                
                HistoryFeatureCard(
                    icon: "person.circle",
                    title: "Owner Changes",
                    description: "Track document ownership transfers"
                )
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct HistoryFeatureCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct HistoryTimelineView: View {
    let document: DocumentModel
    let history: [DocumentRevision]
    let onRevisionSelect: (DocumentRevision) -> Void
    
    private var timelineItems: [TimelineItem] {
        var items: [TimelineItem] = []
        
        // Add current revision
        items.append(TimelineItem(
            revision: document.revision,
            date: document.updatedAt ?? document.createdAt ?? Date(),
            isCurrent: true,
            data: document.data,
            ownerId: document.ownerId
        ))
        
        // Add historical revisions
        for historyRevision in history.sorted(by: { $0.revision > $1.revision }) {
            items.append(TimelineItem(
                revision: historyRevision.revision,
                date: historyRevision.createdAt,
                isCurrent: false,
                data: historyRevision.data,
                ownerId: historyRevision.ownerId
            ))
        }
        
        return items.sorted { $0.revision > $1.revision }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(timelineItems.enumerated()), id: \.offset) { index, item in
                    TimelineItemView(
                        item: item,
                        isLast: index == timelineItems.count - 1,
                        onTap: {
                            if !item.isCurrent,
                               let historyRevision = history.first(where: { $0.revision == item.revision }) {
                                onRevisionSelect(historyRevision)
                            }
                        }
                    )
                }
            }
            .padding()
        }
    }
}

struct TimelineItem {
    let revision: Revision
    let date: Date
    let isCurrent: Bool
    let data: [String: Any]
    let ownerId: Data
}

struct TimelineItemView: View {
    let item: TimelineItem
    let isLast: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline Indicator
            VStack(spacing: 0) {
                Circle()
                    .fill(item.isCurrent ? Color.blue : Color(.systemGray4))
                    .frame(width: 12, height: 12)
                
                if !isLast {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(height: isLast ? 12 : nil)
            
            // Revision Content
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 12) {
                    // Revision Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Revision \(item.revision)")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                if item.isCurrent {
                                    Text("CURRENT")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue)
                                        .cornerRadius(4)
                                }
                            }
                            
                            Text(formatDate(item.date))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if !item.isCurrent {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Data Preview
                    RevisionDataPreview(data: item.data)
                    
                    // Owner Info
                    HStack {
                        Text("Owner:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(item.ownerId.toHexString().prefix(16) + "...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(item.isCurrent)
        }
        .padding(.bottom, isLast ? 0 : 16)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct RevisionDataPreview: View {
    let data: [String: Any]
    
    private let maxPreviewItems = 3
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Data (\(data.count) properties)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(data.keys.sorted().prefix(maxPreviewItems)), id: \.self) { key in
                    if let value = data[key] {
                        HStack {
                            Text(key)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .frame(width: 80, alignment: .leading)
                            
                            Text(formatValue(value))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                
                if data.count > maxPreviewItems {
                    Text("... and \(data.count - maxPreviewItems) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
    }
    
    private func formatValue(_ value: Any) -> String {
        switch value {
        case let stringValue as String:
            return stringValue.count > 30 ? String(stringValue.prefix(30)) + "..." : stringValue
        case let arrayValue as [Any]:
            return "[\(arrayValue.count) items]"
        case let dictValue as [String: Any]:
            return "{\(dictValue.count) properties}"
        default:
            return "\(value)"
        }
    }
}

// MARK: - Revision Detail View

struct RevisionDetailView: View {
    let revision: DocumentRevision
    let document: DocumentModel
    
    @Environment(\.dismiss) private var dismiss
    @State private var showRawData = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Revision Header
                    RevisionDetailHeader(revision: revision, document: document)
                    
                    // Revision Data
                    VStack(spacing: 0) {
                        SectionHeader(title: "Revision Data")
                        
                        VStack(spacing: 0) {
                            ForEach(Array(revision.data.keys.sorted()), id: \.self) { key in
                                if let value = revision.data[key] {
                                    DetailRow(label: key.capitalized, value: formatValue(value))
                                }
                            }
                            
                            Divider()
                                .padding(.leading, 16)
                            
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
                                    Text(revision.formattedData)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(height: 200)
                                .background(Color(.systemGray5))
                            }
                        }
                    }
                    
                    // Comparison with Current
                    if revision.revision != document.revision {
                        ComparisonWithCurrentView(revision: revision, document: document)
                    }
                }
                .padding()
            }
            .navigationTitle("Revision \(revision.revision)")
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
    
    private func formatValue(_ value: Any) -> String {
        switch value {
        case let stringValue as String:
            return stringValue
        case let arrayValue as [Any]:
            return "[\(arrayValue.count) items]"
        case let dictValue as [String: Any]:
            return "{\(dictValue.count) properties}"
        default:
            return "\(value)"
        }
    }
}

struct RevisionDetailHeader: View {
    let revision: DocumentRevision
    let document: DocumentModel
    
    var body: some View {
        VStack(spacing: 16) {
            // Revision Info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Revision \(revision.revision)")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Document: \(document.documentType.capitalized)")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Properties")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(revision.data.count)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
            
            // Metadata
            VStack(spacing: 0) {
                DetailRow(label: "Created", value: formatDate(revision.createdAt))
                DetailRow(label: "Owner ID", value: revision.ownerId.toHexString())
                DetailRow(label: "Document ID", value: revision.documentId)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct ComparisonWithCurrentView: View {
    let revision: DocumentRevision
    let document: DocumentModel
    
    private var changedProperties: [String] {
        var changed: [String] = []
        
        // Find properties that changed
        for key in Set(revision.data.keys).union(Set(document.data.keys)) {
            let revisionValue = revision.data[key]
            let currentValue = document.data[key]
            
            if !areValuesEqual(revisionValue, currentValue) {
                changed.append(key)
            }
        }
        
        return changed.sorted()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Changes Since This Revision")
            
            if changedProperties.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    
                    Text("No Changes")
                        .font(.headline)
                    
                    Text("This revision is identical to the current version.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
            } else {
                VStack(spacing: 0) {
                    ForEach(changedProperties, id: \.self) { property in
                        ComparisonRow(
                            property: property,
                            oldValue: revision.data[property],
                            newValue: document.data[property]
                        )
                    }
                }
            }
        }
    }
    
    private func areValuesEqual(_ value1: Any?, _ value2: Any?) -> Bool {
        switch (value1, value2) {
        case (nil, nil):
            return true
        case (let v1?, let v2?):
            // Type-aware equality checks for complex types
            if let nsObj1 = v1 as? NSObject, let nsObj2 = v2 as? NSObject {
                return nsObj1.isEqual(nsObj2)
            } else if let dict1 = v1 as? NSDictionary, let dict2 = v2 as? NSDictionary {
                return dict1.isEqual(to: dict2 as? [AnyHashable: Any] ?? [:])
            } else if let array1 = v1 as? NSArray, let array2 = v2 as? NSArray {
                return array1.isEqual(to: array2 as? [Any] ?? [])
            } else if let dict1 = v1 as? [String: Any], let dict2 = v2 as? [String: Any] {
                return NSDictionary(dictionary: dict1).isEqual(to: dict2)
            } else if let array1 = v1 as? [Any], let array2 = v2 as? [Any] {
                return NSArray(array: array1).isEqual(to: array2)
            } else {
                // Fallback to string comparison for primitive types
                return "\(v1)" == "\(v2)"
            }
        default:
            return false
        }
    }
}

struct ComparisonRow: View {
    let property: String
    let oldValue: Any?
    let newValue: Any?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(property.capitalized)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            
            HStack(alignment: .top, spacing: 12) {
                // Old Value
                VStack(alignment: .leading, spacing: 4) {
                    Text("This Revision")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(formatValue(oldValue))
                        .font(.body)
                        .foregroundColor(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // New Value
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(formatValue(newValue))
                        .font(.body)
                        .foregroundColor(.green)
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color(.systemGray6))
    }
    
    private func formatValue(_ value: Any?) -> String {
        guard let value = value else { return "(removed)" }
        
        switch value {
        case let stringValue as String:
            return stringValue.isEmpty ? "(empty)" : stringValue
        case let arrayValue as [Any]:
            return "[\(arrayValue.count) items]"
        case let dictValue as [String: Any]:
            return "{\(dictValue.count) properties}"
        default:
            return "\(value)"
        }
    }
}

struct DocumentExportView: View {
    let document: DocumentModel
    
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
                    
                    Text("Export Document")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(document.documentType.capitalized)
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
                Button(action: exportDocument) {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isExporting ? "Exporting..." : "Export Document")
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
    
    private func exportDocument() {
        isExporting = true
        
        Task {
            defer { isExporting = false }
            
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            let exportData = generateExportData()
            Clipboard.copy(exportData)
            
            await MainActor.run {
                dismiss()
            }
        }
    }
    
    private func generateExportData() -> String {
        var exportData: [String: Any] = document.data
        
        if includeMetadata {
            exportData["_id"] = document.id
            exportData["_contractId"] = document.contractId
            exportData["_documentType"] = document.documentType
            exportData["_ownerId"] = document.ownerIdString
            exportData["_revision"] = document.revision
            exportData["_createdAt"] = document.createdAt?.ISO8601Format()
            exportData["_updatedAt"] = document.updatedAt?.ISO8601Format()
        }
        
        switch selectedFormat {
        case .json:
            guard let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return "Failed to generate JSON export"
            }
            return jsonString
            
        case .csv:
            var csv = ""
            let keys = Array(exportData.keys).sorted()
            
            // Header
            csv += keys.joined(separator: ",") + "\n"
            
            // Data
            let values = keys.map { key in
                let value = exportData[key].map { "\($0)" } ?? ""
                return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            csv += values.joined(separator: ",")
            
            return csv
            
        case .txt:
            var text = "Document Export\n"
            text += "================\n\n"
            text += "Type: \(document.documentType)\n"
            text += "ID: \(document.id)\n\n"
            
            if includeMetadata {
                text += "Metadata:\n"
                text += "- Contract: \(document.contractId)\n"
                text += "- Owner: \(document.ownerIdString)\n"
                text += "- Revision: \(document.revision)\n"
                if let created = document.createdAt {
                    text += "- Created: \(created)\n"
                }
                if let updated = document.updatedAt {
                    text += "- Updated: \(updated)\n"
                }
                text += "\n"
            }
            
            text += "Data:\n"
            for (key, value) in document.data.sorted(by: { $0.key < $1.key }) {
                text += "\(key): \(value)\n"
            }
            
            return text
        }
    }
}

#Preview {
    let document = DocumentModel(
        id: "test-doc",
        contractId: "test-contract",
        documentType: "note",
        ownerId: Data(repeating: 0x01, count: 32),
        data: [
            "title": "Test Note",
            "content": "This is a test note"
        ]
    )
    
    let history = [
        DocumentRevision(
            id: "rev1",
            documentId: "test-doc",
            revision: 1,
            data: ["title": "Test Note", "content": "Original content"],
            createdAt: Date().addingTimeInterval(-86400),
            ownerId: Data(repeating: 0x01, count: 32)
        )
    ]
    
    DocumentHistoryView(document: document, history: history)
}