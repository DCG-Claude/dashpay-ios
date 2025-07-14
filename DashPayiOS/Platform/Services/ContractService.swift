import Foundation

/// Comprehensive service for managing data contracts on Dash Platform
@MainActor
class ContractService {
    private let platformSDK: PlatformSDKWrapper
    private let dataManager: DataManager
    
    init(platformSDK: PlatformSDKWrapper, dataManager: DataManager) {
        self.platformSDK = platformSDK
        self.dataManager = dataManager
    }
    
    // MARK: - Contract Fetching
    
    /// Fetch a single data contract by ID from the network
    func fetchContract(id: String) async throws -> ContractModel {
        print("📄 Fetching contract: \(id)")
        
        let sdkHandle = await platformSDK.sdkHandle
        
        // Validate contract ID format
        guard isValidContractId(id) else {
            throw ContractError.invalidContractId(id)
        }
        
        return try await FFIHelpers.asyncFFICall(timeout: 30.0) {
            return try await withCheckedThrowingContinuation { continuation in
                Task {
                    do {
                        let result = try await self.performContractFetch(sdkHandle: sdkHandle, contractId: id)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Fetch multiple contracts by their IDs
    func fetchContracts(ids: [String]) async throws -> [ContractModel] {
        print("📄 Fetching \(ids.count) contracts")
        
        let sdkHandle = await platformSDK.sdkHandle
        
        // Validate all contract IDs
        for id in ids {
            guard isValidContractId(id) else {
                throw ContractError.invalidContractId(id)
            }
        }
        
        return try await FFIHelpers.asyncFFICall(timeout: 60.0) {
            return try await withCheckedThrowingContinuation { continuation in
                Task {
                    do {
                        let result = try await self.performContractsBatch(sdkHandle: sdkHandle, contractIds: ids)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Get contract history with pagination
    func fetchContractHistory(
        id: String, 
        limit: UInt = 10, 
        offset: UInt = 0, 
        startAtMs: UInt64? = nil
    ) async throws -> ContractHistoryResult {
        print("📄 Fetching contract history for: \(id)")
        
        let sdkHandle = await platformSDK.sdkHandle
        
        guard isValidContractId(id) else {
            throw ContractError.invalidContractId(id)
        }
        
        return try await FFIHelpers.asyncFFICall(timeout: 30.0) {
            return try await withCheckedThrowingContinuation { continuation in
                Task {
                    do {
                        let result = try await self.performContractHistoryFetch(
                            sdkHandle: sdkHandle,
                            contractId: id,
                            limit: limit,
                            offset: offset,
                            startAtMs: startAtMs ?? 0
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    // MARK: - Contract Discovery
    
    /// Search for contracts using various criteria
    func searchContracts(query: ContractSearchQuery) async throws -> [ContractModel] {
        print("🔍 Searching contracts with query: \(query)")
        
        // For now, implement a combination of approaches:
        // 1. Check cached/known contracts first
        // 2. Try to fetch by exact ID if query looks like a contract ID
        // 3. Search through well-known contracts
        
        var results: [ContractModel] = []
        
        // Check if query is a contract ID
        if isValidContractId(query.contractId ?? "") {
            do {
                let contract = try await fetchContract(id: query.contractId!)
                results.append(contract)
            } catch {
                print("Contract not found for ID: \(query.contractId!)")
            }
        }
        
        // Search in well-known contracts
        let wellKnownMatches = getWellKnownContracts().filter { contract in
            if let name = query.name, !name.isEmpty {
                return contract.name.localizedCaseInsensitiveContains(name)
            }
            if let ownerId = query.ownerId, !ownerId.isEmpty {
                return contract.ownerIdString.contains(ownerId)
            }
            if let keywords = query.keywords, !keywords.isEmpty {
                return keywords.allSatisfy { keyword in
                    contract.keywords.contains { $0.localizedCaseInsensitiveContains(keyword) }
                }
            }
            return false
        }
        
        results.append(contentsOf: wellKnownMatches)
        
        // Remove duplicates
        results = Array(Set(results))
        
        // Apply limit
        if let limit = query.limit {
            results = Array(results.prefix(Int(limit)))
        }
        
        print("🔍 Found \(results.count) contracts matching query")
        return results
    }
    
    /// Get popular or trending contracts
    func getPopularContracts(limit: Int = 10) async throws -> [ContractModel] {
        print("🔥 Fetching popular contracts")
        
        // For now, return well-known contracts
        // In a full implementation, this would query platform metrics
        let wellKnown = getWellKnownContracts()
        return Array(wellKnown.prefix(limit))
    }
    
    /// Get contracts by owner
    func getContractsByOwner(ownerId: String, limit: Int = 10) async throws -> [ContractModel] {
        print("👤 Fetching contracts by owner: \(ownerId)")
        
        // This would require a specialized query API
        // For now, filter well-known contracts
        let wellKnown = getWellKnownContracts()
        return wellKnown.filter { $0.ownerIdString == ownerId }
    }
    
    // MARK: - Contract Validation
    
    /// Validate a contract's schema and structure
    func validateContract(_ contract: ContractModel) throws -> ContractValidationResult {
        var issues: [ContractValidationIssue] = []
        var warnings: [ContractValidationWarning] = []
        
        // Validate contract ID format
        if !isValidContractId(contract.id) {
            issues.append(.invalidContractId)
        }
        
        // Validate owner ID format
        if contract.ownerId.count != 32 {
            issues.append(.invalidOwnerId)
        }
        
        // Validate document types
        if contract.documentTypes.isEmpty {
            warnings.append(.noDocumentTypes)
        }
        
        // Validate schema structure
        for (docType, schemaObj) in contract.schema {
            guard let schema = schemaObj as? [String: Any] else {
                issues.append(.invalidSchemaFormat(docType))
                continue
            }
            
            // Check for required schema fields
            if schema["type"] == nil {
                issues.append(.missingSchemaType(docType))
            }
            
            if schema["properties"] == nil {
                warnings.append(.noSchemaProperties(docType))
            }
        }
        
        return ContractValidationResult(
            isValid: issues.isEmpty,
            issues: issues,
            warnings: warnings
        )
    }
    
    // MARK: - Caching
    
    /// Save contract to local cache
    func cacheContract(_ contract: ContractModel) async throws {
        try dataManager.saveContract(contract)
    }
    
    /// Get contract from cache
    func getCachedContract(id: String) throws -> ContractModel? {
        return try dataManager.fetchContract(id: id)
    }
    
    /// Get all cached contracts
    func getAllCachedContracts() throws -> [ContractModel] {
        return try dataManager.fetchContracts()
    }
    
    /// Clear contract cache
    func clearCache() throws {
        try dataManager.clearContracts()
    }
    
    // MARK: - Private Implementation
    
    private func performContractFetch(sdkHandle: OpaquePointer, contractId: String) async throws -> ContractModel {
        return try await withUnsafeThrowingContinuation { continuation in
            contractId.withCString { contractIdCStr in
                let result = dash_sdk_data_contract_fetch(sdkHandle, contractIdCStr)
                
                do {
                    let contractModel = try self.handleContractFetchResult(result, contractId: contractId)
                    continuation.resume(returning: contractModel)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func performContractsBatch(sdkHandle: OpaquePointer, contractIds: [String]) async throws -> [ContractModel] {
        return try await withUnsafeThrowingContinuation { continuation in
            let contractIdsJson = contractIds.joined(separator: ",")
            contractIdsJson.withCString { contractIdsCStr in
                let result = dash_sdk_data_contracts_fetch_many(sdkHandle, contractIdsCStr)
                
                do {
                    let contracts = try self.handleContractsBatchResult(result, contractIds: contractIds)
                    continuation.resume(returning: contracts)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func performContractHistoryFetch(
        sdkHandle: OpaquePointer, 
        contractId: String, 
        limit: UInt, 
        offset: UInt, 
        startAtMs: UInt64
    ) async throws -> ContractHistoryResult {
        return try await withUnsafeThrowingContinuation { continuation in
            contractId.withCString { contractIdCStr in
                let result = dash_sdk_data_contract_fetch_history(
                    sdkHandle, 
                    contractIdCStr, 
                    UInt32(limit), 
                    UInt32(offset), 
                    startAtMs
                )
                
                do {
                    let history = try self.handleContractHistoryResult(result)
                    continuation.resume(returning: history)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func handleContractFetchResult(_ result: DashSDKResult, contractId: String) throws -> ContractModel {
        if let error = result.error {
            let errorMessage = FFIHelpers.extractErrorMessage(error)
            defer { dash_sdk_error_free(error) }
            
            if errorMessage.contains("not found") || errorMessage.contains("NotFound") {
                throw ContractError.contractNotFound(contractId)
            } else {
                throw ContractError.fetchFailed(errorMessage)
            }
        }
        
        guard let data = result.data else {
            throw ContractError.invalidResponse("No data returned")
        }
        
        // Convert FFI result to JSON string
        guard let jsonString = FFIHelpers.safeString(from: data.assumingMemoryBound(to: CChar.self)) else {
            throw ContractError.invalidResponse("Failed to convert response to string")
        }
        
        return try parseContractFromJson(jsonString, contractId: contractId)
    }
    
    private func handleContractsBatchResult(_ result: DashSDKResult, contractIds: [String]) throws -> [ContractModel] {
        if let error = result.error {
            let errorMessage = FFIHelpers.extractErrorMessage(error)
            defer { dash_sdk_error_free(error) }
            throw ContractError.fetchFailed(errorMessage)
        }
        
        guard let data = result.data else {
            throw ContractError.invalidResponse("No data returned")
        }
        
        guard let jsonString = FFIHelpers.safeString(from: data.assumingMemoryBound(to: CChar.self)) else {
            throw ContractError.invalidResponse("Failed to convert response to string")
        }
        
        return try parseContractsFromBatchJson(jsonString, expectedIds: contractIds)
    }
    
    private func handleContractHistoryResult(_ result: DashSDKResult) throws -> ContractHistoryResult {
        if let error = result.error {
            let errorMessage = FFIHelpers.extractErrorMessage(error)
            defer { dash_sdk_error_free(error) }
            throw ContractError.fetchFailed(errorMessage)
        }
        
        guard let data = result.data else {
            throw ContractError.invalidResponse("No data returned")
        }
        
        guard let jsonString = FFIHelpers.safeString(from: data.assumingMemoryBound(to: CChar.self)) else {
            throw ContractError.invalidResponse("Failed to convert response to string")
        }
        
        return try parseContractHistoryFromJson(jsonString)
    }
    
    private func parseContractFromJson(_ jsonString: String, contractId: String) throws -> ContractModel {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ContractError.invalidResponse("Invalid JSON encoding")
        }
        
        do {
            let contractData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            guard let contractDict = contractData else {
                throw ContractError.invalidResponse("Invalid JSON structure")
            }
            
            return try parseContractFromDictionary(contractDict, contractId: contractId)
        } catch {
            throw ContractError.parseError("Failed to parse contract JSON: \(error.localizedDescription)")
        }
    }
    
    private func parseContractsFromBatchJson(_ jsonString: String, expectedIds: [String]) throws -> [ContractModel] {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ContractError.invalidResponse("Invalid JSON encoding")
        }
        
        do {
            let batchData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            guard let contractsDict = batchData else {
                throw ContractError.invalidResponse("Invalid batch JSON structure")
            }
            
            var contracts: [ContractModel] = []
            
            for contractId in expectedIds {
                if let contractData = contractsDict[contractId] as? [String: Any] {
                    let contract = try parseContractFromDictionary(contractData, contractId: contractId)
                    contracts.append(contract)
                }
            }
            
            return contracts
        } catch {
            throw ContractError.parseError("Failed to parse contracts batch JSON: \(error.localizedDescription)")
        }
    }
    
    private func parseContractFromDictionary(_ dict: [String: Any], contractId: String) throws -> ContractModel {
        // Extract basic contract information
        let version = dict["version"] as? Int ?? 0
        let ownerId = extractOwnerIdFromDict(dict)
        
        // Parse document types and schema
        let documentTypes = extractDocumentTypesFromDict(dict)
        let schema = extractSchemaFromDict(dict)
        
        // Extract DPP data contract if available
        let dppContract = try? extractDPPContractFromDict(dict, contractId: contractId)
        
        // Extract metadata
        let name = extractContractNameFromDict(dict, contractId: contractId)
        let description = dict["description"] as? String
        let keywords = dict["keywords"] as? [String] ?? []
        let tokens = extractTokensFromDict(dict)
        
        return ContractModel(
            id: contractId,
            name: name,
            version: version,
            ownerId: ownerId,
            documentTypes: documentTypes,
            schema: schema,
            dppDataContract: dppContract,
            tokens: tokens,
            keywords: keywords,
            description: description
        )
    }
    
    private func parseContractHistoryFromJson(_ jsonString: String) throws -> ContractHistoryResult {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ContractError.invalidResponse("Invalid JSON encoding")
        }
        
        do {
            let historyData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            guard let historyDict = historyData else {
                throw ContractError.invalidResponse("Invalid history JSON structure")
            }
            
            let totalCount = historyDict["totalCount"] as? Int ?? 0
            let hasMore = historyDict["hasMore"] as? Bool ?? false
            let entries = (historyDict["entries"] as? [[String: Any]]) ?? []
            
            let historyEntries = entries.compactMap { entry -> ContractHistoryEntry? in
                guard let version = entry["version"] as? Int,
                      let timestamp = entry["timestamp"] as? Double else {
                    return nil
                }
                
                return ContractHistoryEntry(
                    version: version,
                    timestamp: Date(timeIntervalSince1970: timestamp / 1000),
                    changes: entry["changes"] as? [String: Any] ?? [:]
                )
            }
            
            return ContractHistoryResult(
                totalCount: totalCount,
                hasMore: hasMore,
                entries: historyEntries
            )
        } catch {
            throw ContractError.parseError("Failed to parse contract history JSON: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func isValidContractId(_ id: String) -> Bool {
        // Check if it's a valid base58 identifier or hex string
        if id.count == 64 && id.allSatisfy({ $0.isHexDigit }) {
            return true // Hex format
        }
        
        // Try to decode as base58
        if let _ = Data.identifier(fromBase58: id), id.count >= 32 {
            return true // Base58 format
        }
        
        return false
    }
    
    private func extractOwnerIdFromDict(_ dict: [String: Any]) -> Data {
        if let ownerIdString = dict["ownerId"] as? String {
            if let base58Data = Data.identifier(fromBase58: ownerIdString) {
                return base58Data
            }
            if let hexData = Data(hexString: ownerIdString) {
                return hexData
            }
        }
        
        // Return empty data if not found or invalid
        return Data(repeating: 0, count: 32)
    }
    
    private func extractDocumentTypesFromDict(_ dict: [String: Any]) -> [String] {
        if let documents = dict["documents"] as? [String: Any] {
            return Array(documents.keys)
        }
        if let documentTypes = dict["documentTypes"] as? [String] {
            return documentTypes
        }
        return []
    }
    
    private func extractSchemaFromDict(_ dict: [String: Any]) -> [String: Any] {
        if let documents = dict["documents"] as? [String: Any] {
            var schema: [String: Any] = [:]
            for (docType, docSchema) in documents {
                schema[docType] = docSchema
            }
            return schema
        }
        return [:]
    }
    
    private func extractDPPContractFromDict(_ dict: [String: Any], contractId: String) throws -> DPPDataContract {
        // This is a complex conversion that would need full implementation
        // For now, create a basic DPPDataContract
        let version = UInt32(dict["version"] as? Int ?? 0)
        let ownerId = extractOwnerIdFromDict(dict)
        let id = Data.identifier(fromBase58: contractId) ?? Data(hexString: contractId) ?? Data(repeating: 0, count: 32)
        
        return DPPDataContract(
            id: id,
            version: version,
            ownerId: ownerId,
            documentTypes: [:], // Would need full parsing
            config: DataContractConfig(
                canBeDeleted: false,
                readOnly: false,
                keepsHistory: true,
                documentsKeepRevisionLogForPassedTimeMs: nil,
                documentsMutableContractDefaultStored: true
            ),
            schemaDefs: nil,
            createdAt: dict["createdAt"] as? TimestampMillis,
            updatedAt: dict["updatedAt"] as? TimestampMillis,
            createdAtBlockHeight: dict["createdAtBlockHeight"] as? BlockHeight,
            updatedAtBlockHeight: dict["updatedAtBlockHeight"] as? BlockHeight,
            createdAtEpoch: dict["createdAtEpoch"] as? EpochIndex,
            updatedAtEpoch: dict["updatedAtEpoch"] as? EpochIndex,
            groups: [:],
            tokens: [:],
            keywords: dict["keywords"] as? [String] ?? [],
            description: dict["description"] as? String
        )
    }
    
    private func extractContractNameFromDict(_ dict: [String: Any], contractId: String) -> String {
        if let name = dict["name"] as? String, !name.isEmpty {
            return name
        }
        
        // Try to determine name from well-known contracts
        if let wellKnown = getWellKnownContracts().first(where: { $0.id == contractId }) {
            return wellKnown.name
        }
        
        // Generate a name based on contract ID
        return "Contract \(String(contractId.prefix(8)))"
    }
    
    private func extractTokensFromDict(_ dict: [String: Any]) -> [TokenConfiguration] {
        // This would need full implementation of token parsing
        return []
    }
    
    /// Get well-known contracts for easier discovery
    private func getWellKnownContracts() -> [ContractModel] {
        return [
            ContractModel(
                id: "GWRSAVFMjXx8HpQFaNJMqBV7MBgMK4br5UESsB4S31Ec", // DPNS testnet
                name: "DPNS",
                version: 1,
                ownerId: Data(repeating: 0, count: 32),
                documentTypes: ["domain", "preorder"],
                schema: [
                    "domain": [
                        "type": "object",
                        "properties": [
                            "label": ["type": "string"],
                            "normalizedLabel": ["type": "string"],
                            "normalizedParentDomainName": ["type": "string"],
                            "preorderSalt": ["type": "array"],
                            "records": ["type": "object"],
                            "subdomainRules": ["type": "object"]
                        ]
                    ],
                    "preorder": [
                        "type": "object",
                        "properties": [
                            "saltedDomainHash": ["type": "array"]
                        ]
                    ]
                ],
                tokens: [],
                keywords: ["dpns", "domain", "name", "registry"],
                description: "Dash Platform Name Service for decentralized domain registration"
            ),
            ContractModel(
                id: "Bwr4jHXb7vtJEKjGgajQzHk7aMXWvNJUAfZXgvFtB5yM", // DashPay testnet
                name: "DashPay",
                version: 1,
                ownerId: Data(repeating: 0, count: 32),
                documentTypes: ["profile", "contactRequest"],
                schema: [
                    "profile": [
                        "type": "object",
                        "properties": [
                            "displayName": ["type": "string"],
                            "publicMessage": ["type": "string"],
                            "avatarUrl": ["type": "string"],
                            "avatarHash": ["type": "array"],
                            "avatarFingerprint": ["type": "array"]
                        ]
                    ],
                    "contactRequest": [
                        "type": "object",
                        "properties": [
                            "toUserId": ["type": "array"],
                            "encryptedPublicKey": ["type": "array"],
                            "senderKeyIndex": ["type": "integer"],
                            "recipientKeyIndex": ["type": "integer"],
                            "accountReference": ["type": "integer"]
                        ]
                    ]
                ],
                tokens: [],
                keywords: ["dashpay", "profile", "contact", "social"],
                description: "DashPay social features and contact management"
            ),
            ContractModel(
                id: "rUnsWrFu3PKyRMGk2mxmZVBPbBzGb5cjpPu5XrqSzVQ", // Masternode Reward Shares testnet
                name: "Masternode Reward Shares",
                version: 1,
                ownerId: Data(repeating: 0, count: 32),
                documentTypes: ["rewardShare"],
                schema: [
                    "rewardShare": [
                        "type": "object",
                        "properties": [
                            "payToId": ["type": "array"],
                            "percentage": ["type": "integer"]
                        ]
                    ]
                ],
                tokens: [],
                keywords: ["masternode", "rewards", "shares", "governance"],
                description: "Masternode reward sharing and distribution management"
            )
        ]
    }
}

// MARK: - Contract Service Models

struct ContractSearchQuery {
    let contractId: String?
    let name: String?
    let ownerId: String?
    let keywords: [String]?
    let limit: UInt?
    
    init(contractId: String? = nil, name: String? = nil, ownerId: String? = nil, keywords: [String]? = nil, limit: UInt? = nil) {
        self.contractId = contractId
        self.name = name
        self.ownerId = ownerId
        self.keywords = keywords
        self.limit = limit
    }
}

struct ContractHistoryResult {
    let totalCount: Int
    let hasMore: Bool
    let entries: [ContractHistoryEntry]
}

struct ContractHistoryEntry {
    let version: Int
    let timestamp: Date
    let changes: [String: Any]
}

struct ContractValidationResult {
    let isValid: Bool
    let issues: [ContractValidationIssue]
    let warnings: [ContractValidationWarning]
}

// ContractValidationIssue is defined in ContractsView.swift

enum ContractValidationWarning {
    case noDocumentTypes
    case noSchemaProperties(String)
}

enum ContractError: Error, LocalizedError {
    case invalidContractId(String)
    case contractNotFound(String)
    case fetchFailed(String)
    case invalidResponse(String)
    case parseError(String)
    case validationFailed([ContractValidationIssue])
    
    var errorDescription: String? {
        switch self {
        case .invalidContractId(let id):
            return "Invalid contract ID format: \(id)"
        case .contractNotFound(let id):
            return "Contract not found: \(id)"
        case .fetchFailed(let message):
            return "Failed to fetch contract: \(message)"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .validationFailed(let issues):
            return "Contract validation failed: \(issues.count) issues found"
        }
    }
}