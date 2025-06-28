import SwiftUI

/// Comprehensive document creation wizard with contract schema validation
struct DocumentCreationWizardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var documentService: DocumentService
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentStep: WizardStep = .selectContract
    @State private var selectedContract: ContractModel?
    @State private var selectedDocumentType: String = ""
    @State private var selectedOwner: IdentityModel?
    @State private var documentData: [String: Any] = [:]
    @State private var isCreating = false
    @State private var validationErrors: [String] = []
    @State private var showValidationAlert = false
    
    private let steps: [WizardStep] = [.selectContract, .selectType, .selectOwner, .enterData, .review]
    
    init() {
        // Initialize with placeholder values - will be properly injected
        let dummyDataManager = DataManager(modelContext: ModelContext(ModelContainer.preview()))
        let dummyPlatformSDK = try! PlatformSDKWrapper(network: .testnet)
        self._documentService = StateObject(wrappedValue: DocumentService(platformSDK: dummyPlatformSDK, dataManager: dummyDataManager))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress Indicator
                WizardProgressView(currentStep: currentStep, steps: steps)
                    .padding()
                
                // Step Content
                switch currentStep {
                case .selectContract:
                    ContractSelectionStep(selectedContract: $selectedContract)
                case .selectType:
                    DocumentTypeSelectionStep(
                        contract: selectedContract,
                        selectedType: $selectedDocumentType
                    )
                case .selectOwner:
                    OwnerSelectionStep(selectedOwner: $selectedOwner)
                case .enterData:
                    DataEntryStep(
                        contract: selectedContract,
                        documentType: selectedDocumentType,
                        documentData: $documentData
                    )
                case .review:
                    ReviewStep(
                        contract: selectedContract,
                        documentType: selectedDocumentType,
                        owner: selectedOwner,
                        documentData: documentData
                    )
                }
                
                Spacer()
                
                // Navigation Buttons
                WizardNavigationButtons(
                    currentStep: currentStep,
                    canProceed: canProceedToNextStep,
                    isCreating: isCreating,
                    onPrevious: { moveToPreviousStep() },
                    onNext: { moveToNextStep() },
                    onCancel: { dismiss() },
                    onCreate: { createDocument() }
                )
                .padding()
            }
            .navigationTitle("Create Document")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Validation Error", isPresented: $showValidationAlert) {
                Button("OK") { }
            } message: {
                Text(validationErrors.joined(separator: "\n"))
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
        
        // In a real implementation, we would recreate the service with proper dependencies
        print("📄 Setting up DocumentService for creation wizard")
    }
    
    private var canProceedToNextStep: Bool {
        switch currentStep {
        case .selectContract:
            return selectedContract != nil
        case .selectType:
            return !selectedDocumentType.isEmpty
        case .selectOwner:
            return selectedOwner != nil
        case .enterData:
            return validateDocumentData()
        case .review:
            return true
        }
    }
    
    private func validateDocumentData() -> Bool {
        validationErrors.removeAll()
        
        guard let contract = selectedContract else {
            validationErrors.append("No contract selected")
            return false
        }
        
        // Get document schema
        guard let documentSchema = contract.schema[selectedDocumentType] as? [String: Any] else {
            validationErrors.append("Document type schema not found")
            return false
        }
        
        // Validate required properties
        if let properties = documentSchema["properties"] as? [String: Any] {
            let required = documentSchema["required"] as? [String] ?? []
            
            for requiredProperty in required {
                if documentData[requiredProperty] == nil || 
                   (documentData[requiredProperty] as? String)?.isEmpty == true {
                    validationErrors.append("Required property '\(requiredProperty)' is missing")
                }
            }
        }
        
        return validationErrors.isEmpty
    }
    
    private func moveToPreviousStep() {
        guard let currentIndex = steps.firstIndex(of: currentStep),
              currentIndex > 0 else { return }
        
        withAnimation {
            currentStep = steps[currentIndex - 1]
        }
    }
    
    private func moveToNextStep() {
        guard canProceedToNextStep else {
            if !validationErrors.isEmpty {
                showValidationAlert = true
            }
            return
        }
        
        guard let currentIndex = steps.firstIndex(of: currentStep),
              currentIndex < steps.count - 1 else { return }
        
        withAnimation {
            currentStep = steps[currentIndex + 1]
        }
    }
    
    private func createDocument() {
        guard let contract = selectedContract,
              let owner = selectedOwner else {
            return
        }
        
        Task {
            isCreating = true
            defer { isCreating = false }
            
            do {
                let document = try await documentService.createDocument(
                    contractId: contract.id,
                    documentType: selectedDocumentType,
                    ownerId: owner.idString,
                    data: documentData
                )
                
                await MainActor.run {
                    appState.addDocument(document)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    appState.showError(message: "Failed to create document: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Wizard Steps

enum WizardStep: String, CaseIterable {
    case selectContract = "contract"
    case selectType = "type"
    case selectOwner = "owner"
    case enterData = "data"
    case review = "review"
    
    var title: String {
        switch self {
        case .selectContract:
            return "Select Contract"
        case .selectType:
            return "Document Type"
        case .selectOwner:
            return "Select Owner"
        case .enterData:
            return "Enter Data"
        case .review:
            return "Review"
        }
    }
    
    var stepNumber: Int {
        return WizardStep.allCases.firstIndex(of: self)! + 1
    }
}

// MARK: - Step Views

struct WizardProgressView: View {
    let currentStep: WizardStep
    let steps: [WizardStep]
    
    var body: some View {
        VStack(spacing: 12) {
            // Progress Bar
            HStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Rectangle()
                        .fill(index <= currentStepIndex ? Color.blue : Color(.systemGray4))
                        .frame(height: 4)
                        .cornerRadius(2)
                }
            }
            
            // Step Info
            HStack {
                Text("Step \(currentStep.stepNumber) of \(steps.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(currentStep.title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
        }
    }
    
    private var currentStepIndex: Int {
        return steps.firstIndex(of: currentStep) ?? 0
    }
}

struct ContractSelectionStep: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedContract: ContractModel?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.below.ecg")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("Choose a Data Contract")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Select the data contract that defines the document type you want to create.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top)
                
                // Contract List
                LazyVStack(spacing: 12) {
                    ForEach(appState.contracts) { contract in
                        ContractSelectionCard(
                            contract: contract,
                            isSelected: selectedContract?.id == contract.id,
                            onSelect: { selectedContract = contract }
                        )
                    }
                }
                
                // Empty State
                if appState.contracts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        
                        Text("No Contracts Available")
                            .font(.headline)
                        
                        Text("You need to have data contracts available to create documents. Browse and add contracts first.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .padding()
        }
    }
}

struct ContractSelectionCard: View {
    let contract: ContractModel
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contract.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(contract.id)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                    }
                }
                
                if let description = contract.description {
                    Text(description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Document Types
                HStack {
                    Text("Document Types:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(contract.documentTypes.count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    Text("v\(contract.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DocumentTypeSelectionStep: View {
    let contract: ContractModel?
    @Binding var selectedType: String
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    
                    Text("Choose Document Type")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if let contract = contract {
                        Text("Select a document type from the \(contract.name) contract.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.top)
                
                // Document Types
                if let contract = contract {
                    LazyVStack(spacing: 12) {
                        ForEach(contract.documentTypes, id: \.self) { documentType in
                            DocumentTypeCard(
                                documentType: documentType,
                                contract: contract,
                                isSelected: selectedType == documentType,
                                onSelect: { selectedType = documentType }
                            )
                        }
                    }
                } else {
                    Text("No contract selected")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}

struct DocumentTypeCard: View {
    let documentType: String
    let contract: ContractModel
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: documentTypeIcon)
                        .font(.title2)
                        .foregroundColor(documentTypeColor)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(documentType.capitalized)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(documentTypeDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                    }
                }
                
                // Schema Preview
                if let schema = getDocumentSchema() {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Properties:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let properties = schema["properties"] as? [String: Any] {
                            let required = schema["required"] as? [String] ?? []
                            
                            FlowLayout {
                                ForEach(Array(properties.keys.prefix(5)), id: \.self) { property in
                                    PropertyChip(
                                        property: property,
                                        isRequired: required.contains(property)
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .background(isSelected ? Color.green.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var documentTypeIcon: String {
        switch documentType.lowercased() {
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
    
    private var documentTypeColor: Color {
        switch documentType.lowercased() {
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
    
    private var documentTypeDescription: String {
        switch documentType.lowercased() {
        case "profile":
            return "User profile information"
        case "domain":
            return "Domain name registration"
        case "note":
            return "Text note or document"
        case "contact":
            return "Contact information"
        case "message":
            return "Message or communication"
        case "file":
            return "File or data storage"
        default:
            return "Custom document type"
        }
    }
    
    private func getDocumentSchema() -> [String: Any]? {
        return contract.schema[documentType] as? [String: Any]
    }
}

struct PropertyChip: View {
    let property: String
    let isRequired: Bool
    
    var body: some View {
        Text(property)
            .font(.caption)
            .foregroundColor(isRequired ? .white : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isRequired ? Color.red : Color(.systemGray5))
            .cornerRadius(8)
    }
}

struct FlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews)
        return result.bounds
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX,
                                     y: bounds.minY + result.frames[index].minY),
                         proposal: ProposedViewSize(result.frames[index].size))
        }
    }
    
    struct FlowResult {
        var bounds = CGSize.zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + 8
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                x += size.width + 8
                lineHeight = max(lineHeight, size.height)
            }
            
            bounds = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

struct OwnerSelectionStep: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedOwner: IdentityModel?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 50))
                        .foregroundColor(.purple)
                    
                    Text("Select Document Owner")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Choose which identity will own this document.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top)
                
                // Identity List
                LazyVStack(spacing: 12) {
                    ForEach(appState.identities) { identity in
                        IdentitySelectionCard(
                            identity: identity,
                            isSelected: selectedOwner?.id == identity.id,
                            onSelect: { selectedOwner = identity }
                        )
                    }
                }
                
                // Empty State
                if appState.identities.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.3")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        
                        Text("No Identities Available")
                            .font(.headline)
                        
                        Text("You need to have identities available to own documents. Create an identity first.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .padding()
        }
    }
}

struct IdentitySelectionCard: View {
    let identity: IdentityModel
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Identity Avatar
                Circle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [.blue, .purple]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text((identity.alias ?? identity.idString.prefix(2)).prefix(2).uppercased())
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    )
                
                // Identity Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(identity.alias ?? "Unnamed Identity")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(identity.idString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Text("Balance: \(identity.balance) credits")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.purple)
                        .font(.title2)
                }
            }
            .padding()
            .background(isSelected ? Color.purple.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DataEntryStep: View {
    let contract: ContractModel?
    let documentType: String
    @Binding var documentData: [String: Any]
    
    private var documentSchema: [String: Any]? {
        contract?.schema[documentType] as? [String: Any]
    }
    
    private var properties: [String: Any] {
        documentSchema?["properties"] as? [String: Any] ?? [:]
    }
    
    private var requiredProperties: [String] {
        documentSchema?["required"] as? [String] ?? []
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Enter Document Data")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Fill in the required properties for your \(documentType) document.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top)
                
                // Data Entry Form
                if !properties.isEmpty {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(properties.keys.sorted()), id: \.self) { propertyKey in
                            if let propertySchema = properties[propertyKey] as? [String: Any] {
                                PropertyInputField(
                                    propertyKey: propertyKey,
                                    propertySchema: propertySchema,
                                    isRequired: requiredProperties.contains(propertyKey),
                                    value: Binding(
                                        get: { documentData[propertyKey] },
                                        set: { documentData[propertyKey] = $0 }
                                    )
                                )
                            }
                        }
                    }
                } else {
                    Text("No properties defined for this document type")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .padding()
        }
    }
}

struct PropertyInputField: View {
    let propertyKey: String
    let propertySchema: [String: Any]
    let isRequired: Bool
    @Binding var value: Any?
    
    private var propertyType: String {
        propertySchema["type"] as? String ?? "string"
    }
    
    private var propertyTitle: String {
        propertySchema["title"] as? String ?? propertyKey.capitalized
    }
    
    private var propertyDescription: String? {
        propertySchema["description"] as? String
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Property Header
            HStack {
                Text(propertyTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                
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
            
            // Property Description
            if let description = propertyDescription {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Input Field
            switch propertyType {
            case "string":
                StringInputField(value: Binding(
                    get: { value as? String ?? "" },
                    set: { value = $0.isEmpty ? nil : $0 }
                ))
            case "integer":
                IntegerInputField(value: Binding(
                    get: { value as? Int ?? 0 },
                    set: { value = $0 }
                ))
            case "number":
                NumberInputField(value: Binding(
                    get: { value as? Double ?? 0.0 },
                    set: { value = $0 }
                ))
            case "boolean":
                BooleanInputField(value: Binding(
                    get: { value as? Bool ?? false },
                    set: { value = $0 }
                ))
            default:
                StringInputField(value: Binding(
                    get: { "\(value ?? "")" },
                    set: { value = $0.isEmpty ? nil : $0 }
                ))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct StringInputField: View {
    @Binding var value: String
    
    var body: some View {
        TextField("Enter text", text: $value)
            .textFieldStyle(RoundedBorderTextFieldStyle())
    }
}

struct IntegerInputField: View {
    @Binding var value: Int
    
    var body: some View {
        TextField("Enter number", value: $value, format: .number)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .keyboardType(.numberPad)
    }
}

struct NumberInputField: View {
    @Binding var value: Double
    
    var body: some View {
        TextField("Enter number", value: $value, format: .number)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .keyboardType(.decimalPad)
    }
}

struct BooleanInputField: View {
    @Binding var value: Bool
    
    var body: some View {
        Toggle("", isOn: $value)
            .labelsHidden()
    }
}

struct ReviewStep: View {
    let contract: ContractModel?
    let documentType: String
    let owner: IdentityModel?
    let documentData: [String: Any]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    
                    Text("Review Document")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Review your document details before creating it on Dash Platform.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top)
                
                // Review Sections
                VStack(spacing: 16) {
                    // Contract Info
                    ReviewSection(title: "Contract") {
                        if let contract = contract {
                            ReviewRow(label: "Name", value: contract.name)
                            ReviewRow(label: "ID", value: contract.id, isMono: true)
                            ReviewRow(label: "Version", value: "v\(contract.version)")
                        }
                    }
                    
                    // Document Info
                    ReviewSection(title: "Document") {
                        ReviewRow(label: "Type", value: documentType.capitalized)
                        if let owner = owner {
                            ReviewRow(label: "Owner", value: owner.alias ?? "Unnamed Identity")
                            ReviewRow(label: "Owner ID", value: owner.idString, isMono: true)
                        }
                    }
                    
                    // Document Data
                    ReviewSection(title: "Data (\(documentData.count) properties)") {
                        ForEach(Array(documentData.keys.sorted()), id: \.self) { key in
                            if let value = documentData[key] {
                                ReviewRow(label: key.capitalized, value: "\(value)")
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct ReviewSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.systemGray5))
            
            VStack(spacing: 0) {
                content
            }
            .background(Color(.systemGray6))
        }
        .cornerRadius(12)
    }
}

struct ReviewRow: View {
    let label: String
    let value: String
    let isMono: Bool
    
    init(label: String, value: String, isMono: Bool = false) {
        self.label = label
        self.value = value
        self.isMono = isMono
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(isMono ? .system(.body, design: .monospaced) : .body)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        
        if value != Array(documentData.keys.sorted()).last {
            Divider()
                .padding(.leading)
        }
    }
    
    private var documentData: [String: Any] {
        // This is a workaround since we can't access the parent's documentData
        // In a real implementation, this would be passed down properly
        return [:]
    }
}

struct WizardNavigationButtons: View {
    let currentStep: WizardStep
    let canProceed: Bool
    let isCreating: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onCancel: () -> Void
    let onCreate: () -> Void
    
    var body: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .foregroundColor(.red)
            
            if currentStep != .selectContract {
                Button("Previous", action: onPrevious)
                    .foregroundColor(.blue)
            }
            
            Spacer()
            
            if currentStep == .review {
                Button(action: onCreate) {
                    HStack {
                        if isCreating {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isCreating ? "Creating..." : "Create Document")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(canProceed && !isCreating ? Color.green : Color.gray)
                    .cornerRadius(8)
                }
                .disabled(!canProceed || isCreating)
            } else {
                Button("Next", action: onNext)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(canProceed ? Color.blue : Color.gray)
                    .cornerRadius(8)
                    .disabled(!canProceed)
            }
        }
    }
}

#Preview {
    DocumentCreationWizardView()
        .environmentObject(AppState())
}