# Document CRUD Implementation

This document describes the comprehensive Document CRUD (Create, Read, Update, Delete) implementation for the DashPay iOS app, providing feature parity with Platform example apps.

## Overview

The document CRUD system provides a complete solution for managing documents on Dash Platform, including:

- **Full CRUD Operations**: Create, read, update, and delete documents
- **Schema Validation**: Validate documents against contract schemas
- **Advanced UI Components**: Enhanced views for document management
- **Batch Operations**: Perform actions on multiple documents
- **History Tracking**: View document revision history
- **Export/Import**: Export documents in multiple formats
- **Search & Filtering**: Advanced document discovery

## Architecture

### Core Components

#### 1. DocumentService (`DocumentService.swift`)

The main service class that handles all document operations:

```swift
@MainActor
class DocumentService: ObservableObject {
    // CRUD Operations
    func createDocument(contractId: String, documentType: String, ownerId: String, data: [String: Any]) async throws -> DocumentModel
    func fetchDocument(contractId: String, documentType: String, documentId: String, forceRefresh: Bool) async throws -> DocumentModel
    func updateDocument(_ document: DocumentModel, newData: [String: Any]) async throws -> DocumentModel
    func deleteDocument(_ document: DocumentModel) async throws
    
    // Query Operations
    func searchDocuments(contractId: String, documentType: String?, query: DocumentQuery) async throws -> [DocumentModel]
    func getDocumentsByOwner(ownerId: String, contractId: String?, documentType: String?) async throws -> [DocumentModel]
    func getDocumentsByType(contractId: String, documentType: String, limit: Int) async throws -> [DocumentModel]
    
    // Batch Operations
    func createDocumentsBatch(requests: [DocumentCreateRequest]) async throws -> [DocumentModel]
    func updateDocumentsBatch(updates: [(document: DocumentModel, newData: [String: Any])]) async throws -> [DocumentModel]
    
    // History Operations
    func getDocumentHistory(documentId: String) async throws -> [DocumentRevision]
    func getDocumentRevision(documentId: String, revision: Revision) async throws -> DocumentModel?
}
```

**Key Features:**
- **Schema Validation**: Validates document data against contract schemas
- **Error Handling**: Comprehensive error mapping and reporting
- **Caching**: Local persistence integration for offline access
- **Batch Processing**: Efficient handling of multiple documents
- **History Tracking**: Document revision management

#### 2. Enhanced UI Components

##### EnhancedDocumentsView (`EnhancedDocumentsView.swift`)

The main documents list view with advanced features:

- **Search**: Real-time text search across document content
- **Filtering**: Filter by contract, document type, and other criteria
- **Sorting**: Multiple sort options (date, type, revision)
- **Multi-select**: Batch selection for operations
- **Empty States**: Helpful guidance when no documents exist

##### EnhancedDocumentDetailView (`EnhancedDocumentDetailView.swift`)

Comprehensive document detail view with tabs:

- **Overview**: Key information and quick actions
- **Properties**: Structured display of document data
- **History**: Revision timeline and changes
- **Metadata**: Technical details and timestamps

##### DocumentCreationWizardView (`DocumentCreationWizardView.swift`)

Step-by-step document creation with validation:

1. **Contract Selection**: Choose from available contracts
2. **Document Type**: Select type from contract schema
3. **Owner Selection**: Choose document owner identity
4. **Data Entry**: Form-based input with validation
5. **Review**: Final verification before creation

**Features:**
- **Schema-driven Forms**: Dynamic form generation from contract schemas
- **Real-time Validation**: Immediate feedback on data entry
- **Progress Tracking**: Visual progress through wizard steps
- **Error Handling**: Clear validation error messages

##### EnhancedEditDocumentView (`EnhancedEditDocumentView.swift`)

Advanced document editing with multiple modes:

- **Properties Mode**: Form-based editing with validation
- **JSON Mode**: Raw JSON editing with syntax highlighting
- **Schema Mode**: View contract schema and constraints

**Features:**
- **Live Validation**: Real-time schema validation
- **Change Tracking**: Detect and highlight unsaved changes
- **Type Safety**: Property-specific input controls
- **Undo Protection**: Confirm before discarding changes

#### 3. Batch Operations

##### DocumentBatchActionsView (`DocumentBatchActionsView.swift`)

Batch operations for multiple documents:

- **Bulk Edit**: Update properties across multiple documents
- **Export**: Export multiple documents in various formats
- **Delete**: Batch deletion with confirmation
- **Refresh**: Update documents from Platform

**Features:**
- **Progress Tracking**: Visual progress for long operations
- **Error Resilience**: Continue processing despite individual failures
- **Operation Summary**: Report success/failure counts

#### 4. History and Revisions

##### DocumentHistoryView (`DocumentHistoryView.swift`)

Document revision tracking and comparison:

- **Timeline View**: Visual history with revision markers
- **Revision Details**: Full data for any revision
- **Change Comparison**: Diff view between revisions
- **Metadata Tracking**: Timestamps and ownership changes

## Data Models

### Core Models

#### DocumentModel
```swift
struct DocumentModel: Identifiable {
    let id: String
    let contractId: String
    let documentType: String
    let ownerId: Data
    let data: [String: Any]
    let createdAt: Date?
    let updatedAt: Date?
    let dppDocument: DPPDocument?
    let revision: Revision
}
```

#### DocumentRevision
```swift
struct DocumentRevision: Identifiable {
    let id: String
    let documentId: String
    let revision: Revision
    let data: [String: Any]
    let createdAt: Date
    let ownerId: Data
}
```

#### DocumentQuery
```swift
class DocumentQuery {
    var propertyFilters: [PropertyFilter] = []
    var sortBy: String?
    var sortOrder: SortOrder = .ascending
    var limit: Int = 50
    var offset: Int = 0
    
    func addPropertyFilter(property: String, value: Any) -> DocumentQuery
    func sortBy(_ property: String, order: SortOrder) -> DocumentQuery
    func limit(_ limit: Int) -> DocumentQuery
    func offset(_ offset: Int) -> DocumentQuery
}
```

### Supporting Types

#### DocumentCreateRequest
```swift
struct DocumentCreateRequest {
    let contractId: String
    let documentType: String
    let ownerId: String
    let data: [String: Any]
    let entropy: Data?
}
```

#### DocumentServiceError
```swift
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
}
```

## Platform SDK Integration

### FFI Functions Used

The document service integrates with the Platform SDK through these FFI functions:

- `dash_sdk_document_create`: Create new documents
- `dash_sdk_document_fetch`: Retrieve documents by ID
- `dash_sdk_document_search`: Query documents with filters
- `dash_sdk_document_replace_on_platform`: Update existing documents
- `dash_sdk_document_delete`: Delete documents

### Memory Management

All FFI resources are properly managed with automatic cleanup:

```swift
// Example of safe FFI resource management
private func withDocumentHandle<T>(
    _ handle: OpaquePointer,
    execute: (OpaquePointer) throws -> T
) rethrows -> T {
    defer {
        dash_sdk_document_handle_destroy(handle)
    }
    return try execute(handle)
}
```

## Usage Examples

### Creating a Document

```swift
let documentService = appState.documentService!

do {
    let document = try await documentService.createDocument(
        contractId: "dashpay-contract",
        documentType: "profile",
        ownerId: identity.idString,
        data: [
            "displayName": "Alice",
            "publicMessage": "Hello from Alice!",
            "avatarUrl": "https://example.com/alice.jpg"
        ]
    )
    print("Document created: \(document.id)")
} catch {
    print("Failed to create document: \(error)")
}
```

### Querying Documents

```swift
let query = DocumentQuery()
    .addPropertyFilter(property: "displayName", value: "Alice")
    .sortBy("$createdAt", order: .descending)
    .limit(10)

do {
    let documents = try await documentService.searchDocuments(
        contractId: "dashpay-contract",
        documentType: "profile",
        query: query
    )
    print("Found \(documents.count) documents")
} catch {
    print("Query failed: \(error)")
}
```

### Updating a Document

```swift
do {
    let updatedDocument = try await documentService.updateDocument(
        document,
        newData: [
            "displayName": "Alice Smith",
            "publicMessage": "Updated message from Alice!",
            "avatarUrl": "https://example.com/alice-new.jpg"
        ]
    )
    print("Document updated to revision \(updatedDocument.revision)")
} catch {
    print("Failed to update document: \(error)")
}
```

### Batch Operations

```swift
let requests = [
    DocumentCreateRequest(
        contractId: "note-contract",
        documentType: "note",
        ownerId: identity.idString,
        data: ["title": "Note 1", "content": "First note"]
    ),
    DocumentCreateRequest(
        contractId: "note-contract",
        documentType: "note",
        ownerId: identity.idString,
        data: ["title": "Note 2", "content": "Second note"]
    )
]

do {
    let documents = try await documentService.createDocumentsBatch(requests: requests)
    print("Created \(documents.count) documents")
} catch {
    print("Batch creation failed: \(error)")
}
```

## Schema Validation

The system performs comprehensive schema validation:

### Required Properties
```swift
// Validates that all required properties are present
let required = documentSchema["required"] as? [String] ?? []
for requiredProperty in required {
    guard documentData[requiredProperty] != nil else {
        throw DocumentServiceError.missingRequiredProperty(requiredProperty, documentType)
    }
}
```

### Type Validation
```swift
// Validates property types against schema
private func validatePropertyValue(_ value: Any, against schema: [String: Any], property: String) throws {
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
    // ... more type validations
    }
}
```

## Error Handling

Comprehensive error handling with user-friendly messages:

```swift
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
        // ... more error mappings
        }
    }
    
    return .unknownError(error)
}
```

## Performance Considerations

### Caching Strategy

- **Local Persistence**: Documents cached in SwiftData for offline access
- **Selective Refresh**: Option to force refresh from Platform
- **Background Sync**: Automatic synchronization of document changes

### Memory Management

- **Resource Cleanup**: Automatic FFI resource cleanup
- **Lazy Loading**: Documents loaded on demand
- **Pagination**: Large result sets handled with pagination

### User Experience

- **Progressive Loading**: Show cached results immediately, update with fresh data
- **Error Recovery**: Graceful handling of network failures
- **Background Operations**: Long operations don't block UI

## Testing

### Unit Tests

Test coverage includes:

- **Schema Validation**: Test all validation rules
- **CRUD Operations**: Test all document operations
- **Error Handling**: Test error scenarios
- **Data Conversion**: Test model transformations

### Integration Tests

- **Platform SDK Integration**: Test FFI function calls
- **Persistence Layer**: Test SwiftData integration
- **UI Components**: Test user interactions

## Future Enhancements

### Planned Features

1. **Document Templates**: Pre-defined document structures
2. **Real-time Sync**: Live updates from Platform
3. **Offline Mode**: Full offline document management
4. **Document Sharing**: Share documents between identities
5. **Advanced Queries**: Complex filtering and sorting
6. **Document Encryption**: Client-side encryption support
7. **Collaborative Editing**: Multi-user document editing
8. **Version Control**: Git-like document versioning

### Performance Optimizations

1. **Incremental Sync**: Only sync changed documents
2. **Compression**: Compress large document data
3. **Indexing**: Local search indexing for faster queries
4. **Caching**: Intelligent caching strategies
5. **Background Processing**: Async operations for better UX

## Conclusion

The Document CRUD implementation provides a comprehensive solution for managing documents on Dash Platform, offering:

- **Complete Functionality**: Full CRUD operations with validation
- **Advanced UI**: Intuitive and powerful user interface
- **Platform Integration**: Seamless SDK integration
- **Error Handling**: Robust error management
- **Performance**: Optimized for mobile usage
- **Extensibility**: Designed for future enhancements

This implementation brings the DashPay iOS app to feature parity with other Platform example applications while providing an excellent user experience for document management.