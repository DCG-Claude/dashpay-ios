import Foundation
import DashSDKFFI

/// Comprehensive document service for Platform document CRUD operations
@MainActor
class DocumentService: ObservableObject {
    private let platformSDK: PlatformSDKWrapper
    private let dataManager: DataManager
    
    @Published var isLoading = false
    @Published var error: DocumentServiceError?
    
    init(platformSDK: PlatformSDKWrapper, dataManager: DataManager) {
        self.platformSDK = platformSDK
        self.dataManager = dataManager
    }
    
    // MARK: - Document CRUD Operations
    
    /// Create a new document with validation
    func createDocument(
        contractId: String,
        documentType: String,
        ownerId: String,
        data: [String: Any],
        entropy: Data? = nil
    ) async throws -> DocumentModel {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Step 1: Validate contract exists and get schema
            let contract = try await validateContract(contractId: contractId)
            
            // Step 2: Validate document type exists in contract
            try validateDocumentType(documentType, in: contract)
            
            // Step 3: Validate document data against schema
            try await validateDocumentData(data, against: contract, documentType: documentType)
            
            // Step 4: Create document using Platform SDK
            let platformDocument = try await platformSDK.createDocument(
                contractId: contractId,
                ownerId: ownerId,
                documentType: documentType,
                data: data
            )
            
            // Step 5: Convert to DocumentModel and save locally
            let documentModel = DocumentModel(
                id: platformDocument.id,
                contractId: platformDocument.contractId,
                documentType: platformDocument.documentType,
                ownerId: Data(hexString: platformDocument.ownerId) ?? Data(),
                data: platformDocument.dataDict,
                createdAt: Date(),
                updatedAt: Date(),
                dppDocument: nil,
                revision: Revision(platformDocument.revision)
            )
            
            // Step 6: Save to local persistence
            try dataManager.saveDocument(documentModel)
            
            print("✅ Document created successfully: \(documentModel.id)")
            return documentModel
            
        } catch {
            let serviceError = mapError(error)
            self.error = serviceError
            print("🔴 Document creation failed: \(serviceError.localizedDescription)")
            throw serviceError
        }
    }
    
    /// Fetch document by ID
    func fetchDocument(
        contractId: String,
        documentType: String,
        documentId: String,
        forceRefresh: Bool = false
    ) async throws -> DocumentModel {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Try local cache first unless force refresh
            if !forceRefresh {
                if let cachedDocument = try? dataManager.fetchDocument(documentId: documentId) {
                    print("📱 Document found in local cache: \(documentId)")
                    return cachedDocument
                }
            }
            
            // Fetch from Platform
            let platformDocument = try await platformSDK.fetchDocument(
                contractId: contractId,
                documentType: documentType,
                documentId: documentId
            )
            
            // Convert to DocumentModel
            let documentModel = DocumentModel(
                id: platformDocument.id,
                contractId: platformDocument.contractId,
                documentType: platformDocument.documentType,
                ownerId: Data(hexString: platformDocument.ownerId) ?? Data(),
                data: platformDocument.dataDict,
                createdAt: Date(),
                updatedAt: Date(),
                dppDocument: nil,
                revision: Revision(platformDocument.revision)
            )
            
            // Cache locally
            try dataManager.saveDocument(documentModel)
            
            print("✅ Document fetched from Platform: \(documentId)")
            return documentModel
            
        } catch {
            let serviceError = mapError(error)
            self.error = serviceError
            throw serviceError
        }
    }
    
    /// Update existing document
    func updateDocument(
        _ document: DocumentModel,
        newData: [String: Any]
    ) async throws -> DocumentModel {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Step 1: Validate contract and document type
            let contract = try await validateContract(contractId: document.contractId)
            try validateDocumentType(document.documentType, in: contract)
            
            // Step 2: Validate new data against schema
            try await validateDocumentData(newData, against: contract, documentType: document.documentType)
            
            // Step 3: Create Platform Document from our model
            let platformDocument = Document(
                id: document.id,
                contractId: document.contractId,
                ownerId: document.ownerIdString,
                documentType: document.documentType,
                revision: UInt64(document.revision),
                data: try JSONSerialization.data(withJSONObject: document.data)
            )
            
            // Step 4: Update using Platform SDK
            let updatedPlatformDocument = try await platformSDK.updateDocument(
                platformDocument,
                newData: newData
            )
            
            // Step 5: Convert back to DocumentModel
            let updatedDocumentModel = DocumentModel(
                id: updatedPlatformDocument.id,
                contractId: updatedPlatformDocument.contractId,
                documentType: updatedPlatformDocument.documentType,
                ownerId: Data(hexString: updatedPlatformDocument.ownerId) ?? document.ownerId,
                data: newData,
                createdAt: document.createdAt,
                updatedAt: Date(),
                dppDocument: nil,
                revision: Revision(updatedPlatformDocument.revision)
            )
            
            // Step 6: Update local persistence
            try dataManager.saveDocument(updatedDocumentModel)
            
            print("✅ Document updated successfully: \(updatedDocumentModel.id)")
            return updatedDocumentModel
            
        } catch {
            let serviceError = mapError(error)
            self.error = serviceError
            throw serviceError
        }
    }
    
    /// Delete document
    func deleteDocument(_ document: DocumentModel) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Step 1: Create Platform Document from our model
            let platformDocument = Document(
                id: document.id,
                contractId: document.contractId,
                ownerId: document.ownerIdString,
                documentType: document.documentType,
                revision: UInt64(document.revision),
                data: try JSONSerialization.data(withJSONObject: document.data)
            )
            
            // Step 2: Delete using Platform SDK
            try await platformSDK.deleteDocument(platformDocument)
            
            // Step 3: Mark as deleted in local persistence
            try dataManager.markDocumentAsDeleted(documentId: document.id)
            
            print("✅ Document deleted successfully: \(document.id)")
            
        } catch {
            let serviceError = mapError(error)
            self.error = serviceError
            throw serviceError
        }
    }
    
    // MARK: - Document Query Operations
    
    /// Search documents with filters
    func searchDocuments(
        contractId: String,
        documentType: String? = nil,
        query: DocumentQuery
    ) async throws -> [DocumentModel] {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Build query parameters
            var queryParams: [String: Any] = [:]
            
            // Add type filter if specified
            if let documentType = documentType {
                queryParams["documentType"] = documentType
            }
            
            // Add property filters
            for filter in query.propertyFilters {
                queryParams[filter.property] = filter.value
            }
            
            // Add sorting
            if let sortBy = query.sortBy {
                queryParams["orderBy"] = [
                    [sortBy, query.sortOrder == .ascending ? "asc" : "desc"]
                ]
            }
            
            // Add pagination
            queryParams["limit"] = query.limit
            queryParams["startAt"] = query.offset
            
            // Search using Platform SDK
            let platformDocuments = try await platformSDK.searchDocuments(
                contractId: contractId,
                documentType: documentType ?? "",
                query: queryParams
            )
            
            // Convert to DocumentModels
            let documentModels = platformDocuments.map { platformDoc in
                DocumentModel(
                    id: platformDoc.id,
                    contractId: platformDoc.contractId,
                    documentType: platformDoc.documentType,
                    ownerId: Data(hexString: platformDoc.ownerId) ?? Data(),
                    data: platformDoc.dataDict,
                    createdAt: Date(),
                    updatedAt: Date(),
                    dppDocument: nil,
                    revision: Revision(platformDoc.revision)
                )
            }
            
            // Cache results locally
            for document in documentModels {
                try? dataManager.saveDocument(document)
            }
            
            print("✅ Found \(documentModels.count) documents matching query")
            return documentModels
            
        } catch {
            let serviceError = mapError(error)
            self.error = serviceError
            throw serviceError
        }
    }
    
    /// Get documents by owner
    func getDocumentsByOwner(
        ownerId: String,
        contractId: String? = nil,
        documentType: String? = nil
    ) async throws -> [DocumentModel] {
        let query = DocumentQuery()
            .addPropertyFilter(property: "$ownerId", value: ownerId)
            .limit(100)
        
        let contractToSearch = contractId ?? ""
        return try await searchDocuments(
            contractId: contractToSearch,
            documentType: documentType,
            query: query
        )
    }
    
    /// Get documents by contract and type
    func getDocumentsByType(
        contractId: String,
        documentType: String,
        limit: Int = 50
    ) async throws -> [DocumentModel] {
        let query = DocumentQuery()
            .limit(limit)
            .sortBy("$createdAt", order: .descending)
        
        return try await searchDocuments(
            contractId: contractId,
            documentType: documentType,
            query: query
        )
    }
    
    // MARK: - Batch Operations
    
    /// Create multiple documents in batch
    func createDocumentsBatch(
        requests: [DocumentCreateRequest]
    ) async throws -> [DocumentModel] {
        var createdDocuments: [DocumentModel] = []
        var errors: [Error] = []
        
        for request in requests {
            do {
                let document = try await createDocument(
                    contractId: request.contractId,
                    documentType: request.documentType,
                    ownerId: request.ownerId,
                    data: request.data,
                    entropy: request.entropy
                )
                createdDocuments.append(document)
            } catch {
                errors.append(error)
                print("🔴 Failed to create document in batch: \(error)")
            }
        }
        
        if !errors.isEmpty && createdDocuments.isEmpty {
            throw DocumentServiceError.batchOperationFailed(errors: errors)
        }
        
        print("✅ Batch created \(createdDocuments.count) documents (\(errors.count) failures)")
        return createdDocuments
    }
    
    /// Update multiple documents in batch
    func updateDocumentsBatch(
        updates: [(document: DocumentModel, newData: [String: Any])]
    ) async throws -> [DocumentModel] {
        var updatedDocuments: [DocumentModel] = []
        var errors: [Error] = []
        
        for (document, newData) in updates {
            do {
                let updatedDocument = try await updateDocument(document, newData: newData)
                updatedDocuments.append(updatedDocument)
            } catch {
                errors.append(error)
                print("🔴 Failed to update document in batch: \(error)")
            }
        }
        
        if !errors.isEmpty && updatedDocuments.isEmpty {
            throw DocumentServiceError.batchOperationFailed(errors: errors)
        }
        
        print("✅ Batch updated \(updatedDocuments.count) documents (\(errors.count) failures)")
        return updatedDocuments
    }
    
    // MARK: - Document History
    
    /// Get document revision history
    func getDocumentHistory(documentId: String) async throws -> [DocumentRevision] {
        // Try to get from local cache first
        let revisions = try dataManager.fetchDocumentRevisions(documentId: documentId)
        
        if !revisions.isEmpty {
            return revisions
        }
        
        // In a full implementation, this would fetch from Platform
        // For now, return empty array
        return []
    }
    
    /// Get specific document revision
    func getDocumentRevision(
        documentId: String,
        revision: Revision
    ) async throws -> DocumentModel? {
        return try dataManager.fetchDocumentRevision(documentId: documentId, revision: revision)
    }
    
    // MARK: - Validation Helpers
    
    private func validateContract(contractId: String) async throws -> ContractModel {
        guard let contract = try? dataManager.fetchContract(contractId: contractId) else {
            throw DocumentServiceError.contractNotFound(contractId)
        }
        return contract
    }
    
    private func validateDocumentType(_ documentType: String, in contract: ContractModel) throws {
        guard contract.documentTypes.contains(documentType) else {
            throw DocumentServiceError.invalidDocumentType(documentType, contract.id)
        }
    }
    
    private func validateDocumentData(
        _ data: [String: Any],
        against contract: ContractModel,
        documentType: String
    ) async throws {
        // Get document schema from contract
        guard let documentSchema = contract.schema[documentType] as? [String: Any] else {
            throw DocumentServiceError.schemaNotFound(documentType, contract.id)
        }
        
        // Validate required properties
        if let properties = documentSchema["properties"] as? [String: Any] {
            let required = documentSchema["required"] as? [String] ?? []
            
            for requiredProperty in required {
                guard data[requiredProperty] != nil else {
                    throw DocumentServiceError.missingRequiredProperty(requiredProperty, documentType)
                }
            }
            
            // Validate property types
            for (key, value) in data {
                guard let propertySchema = properties[key] as? [String: Any] else {
                    throw DocumentServiceError.unknownProperty(key, documentType)
                }
                
                try validatePropertyValue(value, against: propertySchema, property: key)
            }
        }
    }
    
    private func validatePropertyValue(
        _ value: Any,
        against schema: [String: Any],
        property: String
    ) throws {
        guard let type = schema["type"] as? String else { return }
        
        switch type {
        case "string":
            guard value is String else {
                throw DocumentServiceError.invalidPropertyType(property, expected: "string", actual: "\(type(of: value))")
            }
        case "integer":
            guard value is Int || value is Int64 else {
                throw DocumentServiceError.invalidPropertyType(property, expected: "integer", actual: "\(type(of: value))")
            }
        case "number":
            guard value is Double || value is Float || value is Int else {
                throw DocumentServiceError.invalidPropertyType(property, expected: "number", actual: "\(type(of: value))")
            }
        case "boolean":
            guard value is Bool else {
                throw DocumentServiceError.invalidPropertyType(property, expected: "boolean", actual: "\(type(of: value))")
            }
        case "array":
            guard value is [Any] else {
                throw DocumentServiceError.invalidPropertyType(property, expected: "array", actual: "\(type(of: value))")
            }
        case "object":
            guard value is [String: Any] else {
                throw DocumentServiceError.invalidPropertyType(property, expected: "object", actual: "\(type(of: value))")
            }
        default:
            break
        }
    }
    
    private func mapError(_ error: Error) -> DocumentServiceError {
        if let serviceError = error as? DocumentServiceError {
            return serviceError
        }
        
        if let platformError = error as? PlatformError {
            switch platformError {
            case .documentNotFound:
                return .documentNotFound("Unknown")
            case .documentCreationFailed:
                return .creationFailed(platformError.localizedDescription)
            case .documentUpdateFailed:
                return .updateFailed(platformError.localizedDescription)
            case .dataContractNotFound:
                return .contractNotFound("Unknown")
            default:
                return .platformError(platformError)
            }
        }
        
        return .unknownError(error)
    }
}

// MARK: - Supporting Types

/// Document service specific errors
enum DocumentServiceError: LocalizedError {
    case contractNotFound(String)
    case invalidDocumentType(String, String)
    case schemaNotFound(String, String)
    case missingRequiredProperty(String, String)
    case unknownProperty(String, String)
    case invalidPropertyType(String, expected: String, actual: String)
    case documentNotFound(String)
    case creationFailed(String)
    case updateFailed(String)
    case deletionFailed(String)
    case queryFailed(String)
    case batchOperationFailed(errors: [Error])
    case platformError(PlatformError)
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .contractNotFound(let id):
            return "Contract not found: \(id)"
        case .invalidDocumentType(let type, let contractId):
            return "Invalid document type '\(type)' for contract \(contractId)"
        case .schemaNotFound(let type, let contractId):
            return "Schema not found for document type '\(type)' in contract \(contractId)"
        case .missingRequiredProperty(let property, let type):
            return "Missing required property '\(property)' for document type '\(type)'"
        case .unknownProperty(let property, let type):
            return "Unknown property '\(property)' for document type '\(type)'"
        case .invalidPropertyType(let property, let expected, let actual):
            return "Invalid type for property '\(property)': expected \(expected), got \(actual)"
        case .documentNotFound(let id):
            return "Document not found: \(id)"
        case .creationFailed(let reason):
            return "Document creation failed: \(reason)"
        case .updateFailed(let reason):
            return "Document update failed: \(reason)"
        case .deletionFailed(let reason):
            return "Document deletion failed: \(reason)"
        case .queryFailed(let reason):
            return "Document query failed: \(reason)"
        case .batchOperationFailed(let errors):
            return "Batch operation failed with \(errors.count) errors"
        case .platformError(let error):
            return "Platform error: \(error.localizedDescription)"
        case .unknownError(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

/// Document query builder
class DocumentQuery {
    var propertyFilters: [PropertyFilter] = []
    var sortBy: String?
    var sortOrder: SortOrder = .ascending
    var limit: Int = 50
    var offset: Int = 0
    
    func addPropertyFilter(property: String, value: Any) -> DocumentQuery {
        propertyFilters.append(PropertyFilter(property: property, value: value))
        return self
    }
    
    func sortBy(_ property: String, order: SortOrder = .ascending) -> DocumentQuery {
        self.sortBy = property
        self.sortOrder = order
        return self
    }
    
    func limit(_ limit: Int) -> DocumentQuery {
        self.limit = limit
        return self
    }
    
    func offset(_ offset: Int) -> DocumentQuery {
        self.offset = offset
        return self
    }
}

struct PropertyFilter {
    let property: String
    let value: Any
}

enum SortOrder {
    case ascending
    case descending
}

/// Document create request
struct DocumentCreateRequest {
    let contractId: String
    let documentType: String
    let ownerId: String
    let data: [String: Any]
    let entropy: Data?
    
    init(contractId: String, documentType: String, ownerId: String, data: [String: Any], entropy: Data? = nil) {
        self.contractId = contractId
        self.documentType = documentType
        self.ownerId = ownerId
        self.data = data
        self.entropy = entropy
    }
}

/// Document revision for history tracking
struct DocumentRevision: Identifiable {
    let id: String
    let documentId: String
    let revision: Revision
    let data: [String: Any]
    let createdAt: Date
    let ownerId: Data
    
    var formattedData: String {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "Invalid data"
        }
        return jsonString
    }
}