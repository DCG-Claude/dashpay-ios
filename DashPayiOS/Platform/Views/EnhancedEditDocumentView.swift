import SwiftUI
import SwiftData

/// Enhanced document editing view with schema validation and property management
struct EnhancedEditDocumentView: View {
    let document: DocumentModel
    @EnvironmentObject var appState: AppState
    @StateObject private var documentService: DocumentService
    @Environment(\.dismiss) private var dismiss
    
    @State private var editedData: [String: Any]
    @State private var editMode: EditMode = .properties
    @State private var rawJsonText: String
    @State private var isUpdating = false
    @State private var validationErrors: [String] = []
    @State private var showValidationAlert = false
    @State private var hasUnsavedChanges = false
    @State private var showDiscardAlert = false
    
    private var contract: ContractModel? {
        appState.contracts.first { $0.id == document.contractId }
    }
    
    private var documentSchema: [String: Any]? {
        contract?.schema[document.documentType] as? [String: Any]
    }
    
    private var properties: [String: Any] {
        documentSchema?["properties"] as? [String: Any] ?? [:]
    }
    
    private var requiredProperties: [String] {
        documentSchema?["required"] as? [String] ?? []
    }
    
    init(document: DocumentModel) {
        self.document = document
        self._editedData = State(initialValue: document.data)
        self._rawJsonText = State(initialValue: document.formattedData)
        
        // Initialize with placeholder values - will be properly injected
        let dummyContainer = try! ModelContainer.inMemoryContainer()
        let dummyDataManager = DataManager(modelContext: dummyContainer.mainContext)
        let dummyPlatformSDK = try! PlatformSDKWrapper(network: .testnet)
        self._documentService = StateObject(wrappedValue: DocumentService(platformSDK: dummyPlatformSDK, dataManager: dummyDataManager))
    }
    
    var body: some View {
        NavigationView {
            content
        }
    }
    
    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
                // Document Info Header
                DocumentEditHeader(document: document, contract: contract)
                    .padding()
                    .background(Color(.systemGray6))
                
                // Edit Mode Selector
                Picker("Edit Mode", selection: $editMode) {
                    ForEach(EditMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Content based on edit mode
                switch editMode {
                case .properties:
                    PropertyEditView(
                        editedData: $editedData,
                        properties: properties,
                        requiredProperties: requiredProperties,
                        hasUnsavedChanges: $hasUnsavedChanges
                    )
                case .json:
                    JsonEditView(
                        rawJsonText: $rawJsonText,
                        hasUnsavedChanges: $hasUnsavedChanges
                    )
                case .schema:
                    SchemaViewTab(
                        documentSchema: documentSchema,
                        documentType: document.documentType
                    )
                }
                
                Spacer()
                
                // Save/Cancel Buttons
                VStack(spacing: 12) {
                    if !validationErrors.isEmpty {
                        ValidationErrorView(errors: validationErrors)
                    }
                    
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            if hasUnsavedChanges {
                                showDiscardAlert = true
                            } else {
                                dismiss()
                            }
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        
                        Button(action: saveDocument) {
                            HStack {
                                if isUpdating {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                Text(isUpdating ? "Saving..." : "Save Document")
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canSave ? Color.blue : Color.gray)
                            .cornerRadius(8)
                        }
                        .disabled(!canSave || isUpdating)
                    }
                }
                .padding()
            }
            .navigationTitle("Edit Document")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Validation Errors", isPresented: $showValidationAlert) {
                Button("OK") { }
            } message: {
                Text(validationErrors.joined(separator: "\n"))
            }
            .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) {
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard them?")
            }
            .onChange(of: rawJsonText) { _, _ in
                if editMode == .json {
                    updateDataFromJson()
                }
            }
            .onAppear {
                setupDocumentService()
            }
        }
    
    // MARK: - Computed Properties
    
    private var canSave: Bool {
        hasUnsavedChanges && validationErrors.isEmpty && !isUpdating
    }
    
    // MARK: - Helper Methods
    
    private func setupDocumentService() {
        guard let platformSDK = appState.platformSDK,
              let dataManager = appState.dataManager else {
            return
        }
        
        print("📄 Setting up DocumentService for editing")
    }
    
    private func validateData() {
        validationErrors.removeAll()
        
        // Check if data has changed
        hasUnsavedChanges = !NSDictionary(dictionary: editedData).isEqual(to: document.data)
        
        guard let contract = contract else {
            if hasUnsavedChanges {
                validationErrors.append("Contract not found for validation")
            }
            return
        }
        
        guard let documentSchema = documentSchema else {
            if hasUnsavedChanges {
                validationErrors.append("Document schema not found")
            }
            return
        }
        
        // Validate required properties
        for requiredProperty in requiredProperties {
            if editedData[requiredProperty] == nil ||
               (editedData[requiredProperty] as? String)?.isEmpty == true {
                validationErrors.append("Required property '\(requiredProperty)' is missing")
            }
        }
        
        // Validate property types
        for (key, value) in editedData {
            guard let propertySchema = properties[key] as? [String: Any] else {
                validationErrors.append("Unknown property '\(key)'")
                continue
            }
            
            if let error = validatePropertyValue(value, against: propertySchema, property: key) {
                validationErrors.append(error)
            }
        }
    }
    
    private func validatePropertyValue(
        _ value: Any,
        against schema: [String: Any],
        property: String
    ) -> String? {
        guard let type = schema["type"] as? String else { return nil }
        
        switch type {
        case "string":
            guard value is String else {
                return "Property '\(property)' should be a string"
            }
        case "integer":
            guard value is Int || value is Int64 else {
                return "Property '\(property)' should be an integer"
            }
        case "number":
            guard value is Double || value is Float || value is Int else {
                return "Property '\(property)' should be a number"
            }
        case "boolean":
            guard value is Bool else {
                return "Property '\(property)' should be a boolean"
            }
        case "array":
            guard value is [Any] else {
                return "Property '\(property)' should be an array"
            }
        case "object":
            guard value is [String: Any] else {
                return "Property '\(property)' should be an object"
            }
        default:
            break
        }
        
        return nil
    }
    
    private func updateDataFromJson() {
        guard let jsonData = rawJsonText.data(using: .utf8),
              let parsedData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            validationErrors = ["Invalid JSON format"]
            return
        }
        
        editedData = parsedData
        hasUnsavedChanges = true
    }
    
    private func saveDocument() {
        let dataToSave: [String: Any]
        
        if editMode == .json {
            // Parse JSON data
            guard let jsonData = rawJsonText.data(using: .utf8),
                  let parsedData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                validationErrors = ["Invalid JSON format"]
                showValidationAlert = true
                return
            }
            dataToSave = parsedData
        } else {
            dataToSave = editedData
        }
        
        Task {
            isUpdating = true
            defer { isUpdating = false }
            
            do {
                let updatedDocument = try await documentService.updateDocument(
                    document,
                    newData: dataToSave
                )
                
                await MainActor.run {
                    // Update the document in app state
                    if let index = appState.documents.firstIndex(where: { $0.id == document.id }) {
                        appState.documents[index] = updatedDocument
                    }
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    validationErrors = ["Failed to save document: \(error.localizedDescription)"]
                    showValidationAlert = true
                }
            }
        }
    }
}

// MARK: - Edit Modes

enum EditMode: String, CaseIterable {
    case properties = "properties"
    case json = "json"
    case schema = "schema"
    
    var displayName: String {
        switch self {
        case .properties:
            return "Properties"
        case .json:
            return "JSON"
        case .schema:
            return "Schema"
        }
    }
}

// MARK: - Supporting Views

struct DocumentEditHeader: View {
    let document: DocumentModel
    let contract: ContractModel?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: documentIcon)
                    .font(.title2)
                    .foregroundColor(documentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.documentType.capitalized)
                        .font(.headline)
                    
                    Text(contract?.name ?? "Unknown Contract")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Revision")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(document.revision)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(documentColor)
                }
            }
            
            HStack {
                Text("ID: \(document.id)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
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
}

struct PropertyEditView: View {
    @Binding var editedData: [String: Any]
    let properties: [String: Any]
    let requiredProperties: [String]
    @Binding var hasUnsavedChanges: Bool
    
    @State private var showingAddProperty = false
    @State private var newPropertyKey = ""
    @State private var newPropertyValue = ""
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Existing Properties
                ForEach(Array(editedData.keys.sorted()), id: \.self) { key in
                    PropertyEditField(
                        key: key,
                        value: Binding(
                            get: { editedData[key] },
                            set: { 
                                editedData[key] = $0
                                hasUnsavedChanges = true
                            }
                        ),
                        isRequired: requiredProperties.contains(key),
                        propertySchema: properties[key] as? [String: Any],
                        onRemove: {
                            if !requiredProperties.contains(key) {
                                editedData.removeValue(forKey: key)
                                hasUnsavedChanges = true
                            }
                        }
                    )
                }
                
                // Add Property Button
                Button(action: { showingAddProperty = true }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add Property")
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingAddProperty) {
            AddPropertyView(
                newPropertyKey: $newPropertyKey,
                newPropertyValue: $newPropertyValue,
                existingKeys: Array(editedData.keys),
                onAdd: { key, value in
                    editedData[key] = value
                    hasUnsavedChanges = true
                    newPropertyKey = ""
                    newPropertyValue = ""
                    showingAddProperty = false
                }
            )
        }
    }
}

struct PropertyEditField: View {
    let key: String
    @Binding var value: Any?
    let isRequired: Bool
    let propertySchema: [String: Any]?
    let onRemove: () -> Void
    
    @State private var stringValue: String = ""
    @State private var intValue: Int = 0
    @State private var doubleValue: Double = 0.0
    @State private var boolValue: Bool = false
    
    private var propertyType: String {
        propertySchema?["type"] as? String ?? "string"
    }
    
    private var propertyTitle: String {
        propertySchema?["title"] as? String ?? key.capitalized
    }
    
    private var propertyDescription: String? {
        propertySchema?["description"] as? String
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Property Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(propertyTitle)
                            .font(.headline)
                        
                        if isRequired {
                            Text("*")
                                .font(.headline)
                                .foregroundColor(.red)
                        }
                        
                        Spacer()
                        
                        Text(propertyType)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                    
                    if let description = propertyDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !isRequired {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Property Editor
            switch propertyType {
            case "string":
                TextField("Enter text", text: $stringValue)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: stringValue) { _, newValue in
                        value = newValue.isEmpty ? nil : newValue
                    }
            case "integer":
                TextField("Enter number", value: $intValue, format: .number)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numberPad)
                    .onChange(of: intValue) { _, newValue in
                        value = newValue
                    }
            case "number":
                TextField("Enter number", value: $doubleValue, format: .number)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.decimalPad)
                    .onChange(of: doubleValue) { _, newValue in
                        value = newValue
                    }
            case "boolean":
                Toggle("", isOn: $boolValue)
                    .labelsHidden()
                    .onChange(of: boolValue) { _, newValue in
                        value = newValue
                    }
            default:
                TextField("Enter value", text: $stringValue)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: stringValue) { _, newValue in
                        value = newValue.isEmpty ? nil : newValue
                    }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onAppear {
            loadCurrentValue()
        }
    }
    
    private func loadCurrentValue() {
        switch propertyType {
        case "string":
            stringValue = value as? String ?? ""
        case "integer":
            intValue = value as? Int ?? 0
        case "number":
            doubleValue = value as? Double ?? 0.0
        case "boolean":
            boolValue = value as? Bool ?? false
        default:
            stringValue = value.map { "\($0)" } ?? ""
        }
    }
}

struct JsonEditView: View {
    @Binding var rawJsonText: String
    @Binding var hasUnsavedChanges: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // JSON Editor Header
            HStack {
                Text("JSON Editor")
                    .font(.headline)
                
                Spacer()
                
                Button("Format") {
                    formatJson()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .padding(.horizontal)
            
            // JSON Text Editor
            TextEditor(text: $rawJsonText)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .onChange(of: rawJsonText) { _, _ in
                    hasUnsavedChanges = true
                }
            
            // JSON Validation Info
            VStack(alignment: .leading, spacing: 8) {
                Text("JSON Validation")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: isValidJson ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(isValidJson ? .green : .red)
                    
                    Text(isValidJson ? "Valid JSON" : "Invalid JSON")
                        .font(.caption)
                        .foregroundColor(isValidJson ? .green : .red)
                    
                    Spacer()
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
    
    private var isValidJson: Bool {
        guard let data = rawJsonText.data(using: .utf8) else { return false }
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            return true
        } catch {
            return false
        }
    }
    
    private func formatJson() {
        guard let data = rawJsonText.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let formattedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
              let formattedString = String(data: formattedData, encoding: .utf8) else {
            return
        }
        
        rawJsonText = formattedString
    }
}

struct SchemaViewTab: View {
    let documentSchema: [String: Any]?
    let documentType: String
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Schema Header
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                    
                    Text("\(documentType.capitalized) Schema")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Document structure and validation rules")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                if let schema = documentSchema {
                    SchemaPropertiesView(schema: schema)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.questionmark")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        
                        Text("Schema Not Available")
                            .font(.headline)
                        
                        Text("The schema for this document type could not be found.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .padding()
        }
    }
}

struct SchemaPropertiesView: View {
    let schema: [String: Any]
    
    private var properties: [String: Any] {
        schema["properties"] as? [String: Any] ?? [:]
    }
    
    private var requiredProperties: [String] {
        schema["required"] as? [String] ?? []
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Schema Overview
            VStack(spacing: 0) {
                SectionHeader(title: "Schema Overview")
                
                VStack(spacing: 0) {
                    DetailRow(label: "Total Properties", value: "\(properties.count)")
                    DetailRow(label: "Required Properties", value: "\(requiredProperties.count)")
                    
                    if let schemaType = schema["type"] as? String {
                        DetailRow(label: "Schema Type", value: schemaType)
                    }
                }
            }
            
            // Properties
            if !properties.isEmpty {
                VStack(spacing: 0) {
                    SectionHeader(title: "Properties")
                    
                    VStack(spacing: 12) {
                        ForEach(Array(properties.keys.sorted()), id: \.self) { propertyKey in
                            if let propertySchema = properties[propertyKey] as? [String: Any] {
                                SchemaPropertyCard(
                                    propertyKey: propertyKey,
                                    propertySchema: propertySchema,
                                    isRequired: requiredProperties.contains(propertyKey)
                                )
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct SchemaPropertyCard: View {
    let propertyKey: String
    let propertySchema: [String: Any]
    let isRequired: Bool
    
    private var propertyType: String {
        propertySchema["type"] as? String ?? "unknown"
    }
    
    private var propertyTitle: String {
        propertySchema["title"] as? String ?? propertyKey.capitalized
    }
    
    private var propertyDescription: String? {
        propertySchema["description"] as? String
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(propertyTitle)
                            .font(.headline)
                        
                        if isRequired {
                            Text("REQUIRED")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text("Key: \(propertyKey)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(propertyType.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(typeColor)
                    .cornerRadius(6)
            }
            
            if let description = propertyDescription {
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            // Additional schema constraints
            if let constraints = getConstraints() {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Constraints:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    ForEach(constraints, id: \.0) { constraint, value in
                        HStack {
                            Text(constraint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(value)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var typeColor: Color {
        switch propertyType.lowercased() {
        case "string":
            return .green
        case "integer":
            return .blue
        case "number":
            return .blue
        case "boolean":
            return .purple
        case "array":
            return .orange
        case "object":
            return .pink
        default:
            return .gray
        }
    }
    
    private func getConstraints() -> [(String, String)]? {
        var constraints: [(String, String)] = []
        
        if let minLength = propertySchema["minLength"] as? Int {
            constraints.append(("Min Length", "\(minLength)"))
        }
        
        if let maxLength = propertySchema["maxLength"] as? Int {
            constraints.append(("Max Length", "\(maxLength)"))
        }
        
        if let minimum = propertySchema["minimum"] as? Double {
            constraints.append(("Minimum", "\(minimum)"))
        }
        
        if let maximum = propertySchema["maximum"] as? Double {
            constraints.append(("Maximum", "\(maximum)"))
        }
        
        if let pattern = propertySchema["pattern"] as? String {
            constraints.append(("Pattern", pattern))
        }
        
        if let format = propertySchema["format"] as? String {
            constraints.append(("Format", format))
        }
        
        return constraints.isEmpty ? nil : constraints
    }
}

struct AddPropertyView: View {
    @Binding var newPropertyKey: String
    @Binding var newPropertyValue: String
    let existingKeys: [String]
    let onAdd: (String, String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: PropertyType = .string
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    
                    Text("Add Property")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .padding(.top)
                
                // Form
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Property Key")
                            .font(.headline)
                        
                        TextField("Enter property key", text: $newPropertyKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Property Type")
                            .font(.headline)
                        
                        Picker("Type", selection: $selectedType) {
                            ForEach(EditPropertyType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Property Value")
                            .font(.headline)
                        
                        TextField("Enter property value", text: $newPropertyValue)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                .padding()
                
                // Validation
                if !validationError.isEmpty {
                    Text(validationError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Buttons
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    Button("Add Property") {
                        onAdd(newPropertyKey, newPropertyValue)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canAdd ? Color.green : Color.gray)
                    .cornerRadius(8)
                    .disabled(!canAdd)
                }
                .padding()
            }
            .navigationTitle("Add Property")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var canAdd: Bool {
        !newPropertyKey.isEmpty && !newPropertyValue.isEmpty && validationError.isEmpty
    }
    
    private var validationError: String {
        if newPropertyKey.isEmpty {
            return ""
        }
        
        if existingKeys.contains(newPropertyKey) {
            return "Property key already exists"
        }
        
        if newPropertyKey.contains(" ") {
            return "Property key cannot contain spaces"
        }
        
        return ""
    }
}

enum EditPropertyType: String, CaseIterable {
    case string = "string"
    case integer = "integer"
    case number = "number"
    case boolean = "boolean"
    
    var displayName: String {
        switch self {
        case .string:
            return "Text"
        case .integer:
            return "Integer"
        case .number:
            return "Number"
        case .boolean:
            return "Boolean"
        }
    }
}

struct ValidationErrorView: View {
    let errors: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                
                Text("Validation Errors")
                    .font(.headline)
                    .foregroundColor(.red)
            }
            
            ForEach(errors, id: \.self) { error in
                Text("• \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
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
            "content": "This is a test note",
            "tags": ["test", "sample"]
        ]
    )
    
    EnhancedEditDocumentView(document: document)
        .environmentObject(AppState())
}