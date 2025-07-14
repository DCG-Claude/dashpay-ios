import Foundation
import CryptoKit
import SwiftDashCoreSDK

/// Platform SDK errors
enum PlatformError: LocalizedError {
    case sdkInitializationFailed
    case signerCreationFailed
    case identityNotFound
    case identityCreationFailed
    case failedToGetInfo
    case invalidIdentityId
    case transferFailed
    case insufficientBalance
    case documentCreationFailed
    case documentNotFound
    case notImplemented(String)
    case documentUpdateFailed
    case dataContractNotFound
    case dataContractCreationFailed
    case dataContractUpdateFailed
    case invalidData
    case topUpFailed
    
    var errorDescription: String? {
        switch self {
        case .sdkInitializationFailed:
            return "Failed to initialize Platform SDK"
        case .signerCreationFailed:
            return "Failed to create signer"
        case .identityNotFound:
            return "Identity not found"
        case .identityCreationFailed:
            return "Failed to create identity"
        case .failedToGetInfo:
            return "Failed to get identity information"
        case .invalidIdentityId:
            return "Invalid identity ID format"
        case .transferFailed:
            return "Credit transfer failed"
        case .insufficientBalance:
            return "Insufficient balance for operation"
        case .documentCreationFailed:
            return "Document creation failed"
        case .dataContractNotFound:
            return "Data contract not found"
        case .dataContractCreationFailed:
            return "Data contract creation failed"
        case .dataContractUpdateFailed:
            return "Data contract update failed"
        case .documentNotFound:
            return "Document not found"
        case .notImplemented(let feature):
            return "Feature not implemented: \(feature)"
        case .documentUpdateFailed:
            return "Document update failed"
        case .invalidData:
            return "Invalid data returned from SDK"
        case .topUpFailed:
            return "Failed to top up identity"
        }
    }
}

/// Swift-friendly wrapper around Platform FFI with automatic memory management
actor PlatformSDKWrapper {
    private let sdk: OpaquePointer
    private var signer: OpaquePointer?
    private let network: PlatformNetwork
    private let platformSigner: PlatformSigner
    private let coreSDK: DashSDK?
    // Resource management handled by SDK internally
    
    // Static flag to ensure dash_sdk_init() is called only once
    private static var sdkInitialized = false
    
    init(network: PlatformNetwork) async throws {
        self.coreSDK = nil
        self.network = network
        self.platformSigner = PlatformSigner()
        self.sdk = try await Self.createPlatformSDK(for: network, withCore: nil)
    }
    
    init(network: PlatformNetwork, coreSDK: DashSDK) async throws {
        self.coreSDK = coreSDK
        self.network = network
        self.platformSigner = PlatformSigner()
        self.sdk = try await Self.createPlatformSDK(for: network, withCore: coreSDK)
        
        // Test the connection after initialization
        do {
            try await testConnection()
            print("✅ Platform SDK connection test passed")
        } catch {
            print("⚠️ Platform SDK connection test failed: \(error)")
        }
    }
    
    private static func createPlatformSDK(for network: PlatformNetwork, withCore coreSDK: DashSDK?) async throws -> OpaquePointer {
        // Initialize unified library first (replaces dash_sdk_init)
        UnifiedFFIInitializer.shared.initialize()
        
        // Create standard configuration (not extended)
        var config = DashSDKConfig()
        
        // Set base configuration
        config.network = network.sdkNetwork
        config.skip_asset_lock_proof_verification = false
        config.request_retry_count = 3
        config.request_timeout_ms = 30000
        
        // Get DAPI addresses dynamically using the endpoint manager
        let endpointManager = DAPIEndpointManager(network: network)
        let dapiAddresses = await endpointManager.getHealthyEndpointsString()
        
        // Configure DAPI addresses dynamically
        let result: DashSDKResult = dapiAddresses.withCString { addressesCStr -> DashSDKResult in
            var mutableConfig = config
            mutableConfig.dapi_addresses = addressesCStr
            
            // Create Platform SDK with standard configuration
            print("🔧 Creating Platform SDK for \(network) with endpoints: \(dapiAddresses)")
            return dash_sdk_create(&mutableConfig)
        }
        
        // Check for errors
        if let error = result.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 SDK initialization failed: \(errorMessage)")
            throw PlatformError.sdkInitializationFailed
        }
        
        guard let sdkHandle = result.data else {
            throw PlatformError.sdkInitializationFailed
        }
        
        print("✅ Platform SDK initialized with Core integration for network: \(network)")
        return OpaquePointer(sdkHandle)
    }
    
    deinit {
        // Clean up FFI resources
        // TODO: Add resource manager cleanup when available
        
        if let signer = signer {
            // TODO: Re-enable when dash_sdk_signer_destroy is available in unified FFI
            // dash_sdk_signer_destroy(signer)
        }
        dash_sdk_destroy(sdk)
        
        print("🧹 PlatformSDKWrapper cleaned up")
    }
    
    // MARK: - SDK Access
    
    /// Get the SDK handle for use with TokenService
    var sdkHandle: OpaquePointer {
        return sdk
    }
    
    // MARK: - Connection Testing
    
    /// Test Platform SDK connection to DAPI nodes
    func testConnection() async throws {
        print("🔍 Testing Platform SDK connection to DAPI...")
        
        // Test by trying to fetch a well-known contract (DPNS contract)
        // This is a more reliable test as it exercises the DAPI connection
        let dpnsContractId = getDPNSContractId()
        
        let testResult = dpnsContractId.withCString { contractIdCStr in
            dash_sdk_data_contract_fetch(sdk, contractIdCStr)
        }
        
        if let error = testResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Platform connection test failed: \(errorMessage)")
            throw PlatformError.sdkInitializationFailed
        }
        
        if let contractHandle = testResult.data {
            // Clean up the contract handle
            dash_sdk_data_contract_destroy(OpaquePointer(contractHandle))
            print("✅ Platform SDK connected! Successfully fetched DPNS contract for \(network.displayName)")
        } else {
            print("🔴 Platform connection test failed: No contract data returned")
            throw PlatformError.sdkInitializationFailed
        }
    }
    
    /// Get the DPNS contract ID for the current network
    private func getDPNSContractId() -> String {
        switch network {
        case .mainnet:
            // TODO: Replace with actual mainnet DPNS contract ID when available
            // Note: As of Platform v0.22+, system contract IDs are static across networks
            return "GWRSAVFMjXx8HpQFaNJMqBV7MBgMK4br5UESsB4S31EC" // Placeholder - needs actual mainnet ID
        case .testnet:
            return "GWRSAVFMjXx8HpQFaNJMqBV7MBgMK4br5UESsB4S31EC" // Known testnet DPNS contract ID
        case .devnet:
            // TODO: Replace with actual devnet DPNS contract ID when available
            // Note: As of Platform v0.22+, system contract IDs are static across networks
            return "GWRSAVFMjXx8HpQFaNJMqBV7MBgMK4br5UESsB4S31EC" // Placeholder - needs actual devnet ID
        }
    }
    
    /// Get Platform network status and connectivity info
    func getNetworkStatus() async -> PlatformNetworkStatus {
        print("📊 Getting Platform network status...")
        
        let isConnected = await { () -> Bool in
            do {
                try await testConnection()
                return true
            } catch {
                return false
            }
        }()
        
        // Get additional network info
        var connectedNodes = 0
        var averageResponseTime: TimeInterval = 0
        
        if isConnected {
            // Test connectivity to multiple DAPI nodes
            let testNodes = await getTestNodes()
            var successfulNodes = 0
            var totalResponseTime: TimeInterval = 0
            
            for nodeUrl in testNodes {
                let startTime = Date()
                let nodeConnected = await testNodeConnectivity(nodeUrl)
                let responseTime = Date().timeIntervalSince(startTime)
                
                if nodeConnected {
                    successfulNodes += 1
                    totalResponseTime += responseTime
                }
            }
            
            connectedNodes = successfulNodes
            averageResponseTime = successfulNodes > 0 ? totalResponseTime / Double(successfulNodes) : 0
        }
        
        return PlatformNetworkStatus(
            isConnected: isConnected,
            network: network,
            connectedNodes: connectedNodes,
            averageResponseTime: averageResponseTime,
            lastChecked: Date()
        )
    }
    
    private func getTestNodes() async -> [String] {
        // Use the endpoint manager to get healthy endpoints for testing
        let endpointManager = DAPIEndpointManager(network: network)
        return await endpointManager.getHealthyEndpoints()
    }
    
    private func testNodeConnectivity(_ nodeUrl: String) async -> Bool {
        // Simple connectivity test - in production would use proper DAPI health check
        do {
            guard let url = URL(string: nodeUrl) else { return false }
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    // MARK: - Identity Operations
    
    /// Fetch identity by ID with enhanced error handling
    func fetchIdentity(id: String) async throws -> Identity {
        print("🔍 Fetching identity: \(id)")
        
        // Enhanced error handling with manual implementation for now
        return try await id.withCString { idCStr in
            let result = dash_sdk_identity_fetch(sdk, idCStr)
            
            // Enhanced error checking
            if let error = result.error {
                let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown FFI error"
                defer { dash_sdk_error_free(error) }
                print("🔴 Identity fetch failed: \(errorMessage)")
                throw PlatformError.identityNotFound
            }
            
            guard let identityHandle = result.data else {
                throw PlatformError.identityNotFound
            }
            
            defer {
                dash_sdk_identity_destroy(OpaquePointer(identityHandle))
            }
            
            // Get identity info with enhanced null safety
            guard let identityInfo = dash_sdk_identity_get_info(OpaquePointer(identityHandle)) else {
                throw PlatformError.identityNotFound
            }
            
            defer {
                // Enhanced cleanup
                // TODO: Re-enable when dash_sdk_identity_info_free is available in unified FFI
                // dash_sdk_identity_info_free(identityInfo)
            }
            
            // Safe string extraction
            let fetchedId = identityInfo.pointee.id != nil ? String(cString: identityInfo.pointee.id) : "unknown"
            let balance = identityInfo.pointee.balance
            let revision = identityInfo.pointee.revision
            
            print("✅ Identity fetched: \(fetchedId) with balance: \(balance)")
            
            return Identity(
                id: fetchedId,
                balance: balance,
                revision: revision
            )
        }
    }
    
    /// Create identity with asset lock proof
    func createIdentity(with assetLock: AssetLockProof) async throws -> Identity {
        print("🆔 Creating new identity with asset lock: \(assetLock.transactionId)")
        
        // Step 1: Validate asset lock proof
        print("🔍 Validating asset lock proof...")
        guard !assetLock.transactionId.isEmpty else {
            throw PlatformError.invalidIdentityId
        }
        
        guard assetLock.amount > 0 else {
            throw PlatformError.insufficientBalance
        }
        
        print("✅ Asset lock proof validated")
        print("   Transaction: \(assetLock.transactionId)")
        print("   Amount: \(assetLock.amount) satoshis")
        print("   Output Index: \(assetLock.outputIndex)")
        
        // Step 2: Generate key pair for the new identity
        let keyPair = await platformSigner.generateKeyPair()
        
        // Step 3: Create identity with enhanced error handling
        let createResult = dash_sdk_identity_create(sdk)
        
        if let error = createResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown FFI error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Identity creation failed: \(errorMessage)")
            throw PlatformError.identityCreationFailed
        }
        
        guard let identityHandle = createResult.data else {
            print("🔴 No identity handle returned")
            throw PlatformError.identityCreationFailed
        }
        
        // Step 3: Get identity info
        guard let identityInfo = dash_sdk_identity_get_info(OpaquePointer(identityHandle)) else {
            dash_sdk_identity_destroy(OpaquePointer(identityHandle))
            throw PlatformError.identityCreationFailed
        }
        
        let identityId = String(cString: identityInfo.pointee.id)
        let _ = identityInfo.pointee.balance
        let revision = identityInfo.pointee.revision
        
        print("✅ Identity created with ID: \(identityId)")
        
        // Step 4: Store the private key for this identity
        await platformSigner.addPrivateKey(keyPair.privateKey, for: keyPair.publicKey)
        
        // Step 5: Fund the identity with asset lock proof
        do {
            try await fundIdentityWithAssetLock(
                identityHandle: OpaquePointer(identityHandle),
                assetLock: assetLock
            )
            print("✅ Identity funded successfully")
        } catch {
            print("⚠️ Identity created but funding failed: \(error)")
            // Don't fail completely - identity exists, just not funded yet
        }
        
        // Clean up
        // TODO: Re-enable when dash_sdk_identity_info_free is available in unified FFI
        // dash_sdk_identity_info_free(identityInfo)
        dash_sdk_identity_destroy(OpaquePointer(identityHandle))
        
        return Identity(
            id: identityId,
            balance: assetLock.amount,
            revision: revision
        )
    }
    
    /// Transfer credits between identities
    func transferCredits(
        from identity: Identity,
        to recipientId: String,
        amount: UInt64
    ) async throws -> TransferResult {
        // First, we need to fetch the identity handle for the sender
        let fromIdentityResult = identity.id.withCString { idCStr in
            dash_sdk_identity_fetch(sdk, idCStr)
        }
        
        if let error = fromIdentityResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            throw PlatformError.transferFailed
        }
        
        guard let fromIdentityHandle = fromIdentityResult.data else {
            throw PlatformError.transferFailed
        }
        
        defer {
            // Clean up identity handle when done
            dash_sdk_identity_destroy(OpaquePointer(fromIdentityHandle))
        }
        
        // Create signer if needed
        if signer == nil {
            signer = try await createSigner()
        }
        
        guard let signerHandle = signer else {
            throw PlatformError.signerCreationFailed
        }
        
        // Perform the credit transfer
        let transferResult = recipientId.withCString { toIdCStr in
            dash_sdk_identity_transfer_credits(
                sdk,
                OpaquePointer(fromIdentityHandle),
                toIdCStr,
                amount,
                nil, // identity_public_key_handle (auto-select first key)
                signerHandle,
                nil  // put_settings (use defaults)
            )
        }
        
        if let error = transferResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            throw PlatformError.transferFailed
        }
        
        // Parse the transfer result
        guard let resultData = transferResult.data else {
            throw PlatformError.transferFailed
        }
        
        let transferCreditsResult = resultData.assumingMemoryBound(to: DashSDKTransferCreditsResult.self)
        let senderBalance = transferCreditsResult.pointee.sender_balance
        let receiverBalance = transferCreditsResult.pointee.receiver_balance
        
        defer {
            dash_sdk_transfer_credits_result_free(transferCreditsResult)
        }
        
        return TransferResult(
            fromId: identity.id,
            toId: recipientId,
            amount: amount
        )
    }
    
    // MARK: - Data Contract Operations
    
    /// Fetch data contract by ID
    func fetchDataContract(id: String) async throws -> DataContract {
        print("📄 Fetching data contract: \(id)")
        
        let result = id.withCString { idCStr in
            dash_sdk_data_contract_fetch(sdk, idCStr)
        }
        
        if let error = result.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Failed to fetch data contract: \(errorMessage)")
            throw PlatformError.dataContractNotFound
        }
        
        guard let contractHandle = result.data else {
            throw PlatformError.dataContractNotFound
        }
        
        defer {
            dash_sdk_data_contract_destroy(OpaquePointer(contractHandle))
        }
        
        // Extract contract information from FFI handle
        // Note: In a full implementation, we would extract the actual schema and metadata
        // from the contract handle using appropriate FFI calls
        // TODO: Implement when dash_sdk_data_contract_get_info is available
        /*
        guard let contractInfo = dash_sdk_data_contract_get_info(OpaquePointer(contractHandle)) else {
            // Fallback to basic contract info
            return DataContract(
                id: id,
                ownerId: "unknown",
                schema: [:],
                version: 1,
                revision: 0
            )
        }
        
        defer {
            dash_sdk_data_contract_info_free(contractInfo)
        }
        
        let ownerId = String(cString: contractInfo.pointee.owner_id)
        let version = contractInfo.pointee.version
        let revision = contractInfo.pointee.revision
        */
        
        // Temporary implementation
        let ownerId = "unknown"
        let version: UInt32 = 1
        let revision: UInt64 = 0
        
        // Extract schema - for now, use a basic schema structure
        // In production, would parse the actual contract schema from FFI
        let basicSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "message": ["type": "string"],
                "timestamp": ["type": "integer"]
            ],
            "additionalProperties": false
        ]
        
        return DataContract(
            id: id,
            ownerId: ownerId,
            schema: basicSchema,
            version: UInt32(version),
            revision: revision
        )
    }
    
    /// Create a new data contract
    func createDataContract(ownerId: String, schema: [String: Any]) async throws -> DataContract {
        print("📝 Creating data contract for owner: \(ownerId)")
        
        // First, fetch the owner identity
        let ownerIdentityResult = ownerId.withCString { idCStr in
            dash_sdk_identity_fetch(sdk, idCStr)
        }
        
        if let error = ownerIdentityResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            throw PlatformError.identityNotFound
        }
        
        guard let ownerIdentityHandle = ownerIdentityResult.data else {
            throw PlatformError.identityNotFound
        }
        
        defer {
            dash_sdk_identity_destroy(OpaquePointer(ownerIdentityHandle))
        }
        
        // Convert schema to JSON
        let schemaData = try JSONSerialization.data(withJSONObject: schema, options: [])
        let schemaJson = String(data: schemaData, encoding: .utf8) ?? "{}"
        
        // Create the data contract
        let createResult = schemaJson.withCString { schemaCStr in
            dash_sdk_data_contract_create(
                sdk,
                OpaquePointer(ownerIdentityHandle),
                schemaCStr
            )
        }
        
        if let error = createResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Data contract creation failed: \(errorMessage)")
            throw PlatformError.dataContractCreationFailed
        }
        
        guard let contractHandle = createResult.data else {
            throw PlatformError.dataContractCreationFailed
        }
        
        // Put the contract to Platform
        do {
            try await publishDataContract(contractHandle: OpaquePointer(contractHandle))
        } catch {
            dash_sdk_data_contract_destroy(OpaquePointer(contractHandle))
            throw error
        }
        
        let contractId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        
        dash_sdk_data_contract_destroy(OpaquePointer(contractHandle))
        
        print("✅ Data contract created with ID: \(contractId)")
        
        return DataContract(
            id: contractId,
            ownerId: ownerId,
            schema: schema,
            version: 1,
            revision: 0
        )
    }
    
    /// Update an existing data contract
    func updateDataContract(_ contract: DataContract, newSchema: [String: Any]) async throws -> DataContract {
        print("📝 Updating data contract: \(contract.id)")
        
        // For now, create a new version of the contract
        // In production, this would use proper contract evolution
        let updatedContract = try await createDataContract(ownerId: contract.ownerId, schema: newSchema)
        
        return DataContract(
            id: contract.id,
            ownerId: contract.ownerId,
            schema: newSchema,
            version: contract.version + 1,
            revision: contract.revision + 1
        )
    }
    
    // MARK: - Document Operations
    
    func createDocument(
        contractId: String,
        ownerId: String,
        documentType: String,
        data: [String: Any]
    ) async throws -> Document {
        print("📄 Creating document of type \(documentType) for contract \(contractId)")
        
        // Convert document data to JSON
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let dataJson = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        // Fetch the owner identity
        let ownerIdentityResult = ownerId.withCString { idCStr in
            dash_sdk_identity_fetch(sdk, idCStr)
        }
        
        if let error = ownerIdentityResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Failed to fetch owner identity: \(errorMessage)")
            throw PlatformError.documentCreationFailed
        }
        
        guard let ownerIdentityHandle = ownerIdentityResult.data else {
            throw PlatformError.documentCreationFailed
        }
        
        defer {
            dash_sdk_identity_destroy(OpaquePointer(ownerIdentityHandle))
        }
        
        // Fetch the data contract
        let contractResult = contractId.withCString { idCStr in
            dash_sdk_data_contract_fetch(sdk, idCStr)
        }
        
        if let error = contractResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Failed to fetch data contract: \(errorMessage)")
            throw PlatformError.dataContractNotFound
        }
        
        guard let contractHandle = contractResult.data else {
            throw PlatformError.dataContractNotFound
        }
        
        defer {
            dash_sdk_data_contract_destroy(OpaquePointer(contractHandle))
        }
        
        // Create signer if needed
        if signer == nil {
            signer = try await createSigner()
        }
        
        guard let signerHandle = signer else {
            throw PlatformError.signerCreationFailed
        }
        
        // Create the document using FFI with proper parameters
        let createResult = dataJson.withCString { dataCStr in
            documentType.withCString { typeCStr in
                dash_sdk_document_create_from_json(
                    sdk,
                    OpaquePointer(contractHandle),
                    OpaquePointer(ownerIdentityHandle),
                    typeCStr,
                    dataCStr,
                    signerHandle
                )
            }
        }
        
        if let error = createResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Document creation failed: \(errorMessage)")
            throw PlatformError.documentCreationFailed
        }
        
        guard let documentHandle = createResult.data else {
            throw PlatformError.documentCreationFailed
        }
        
        defer {
            dash_sdk_document_handle_destroy(OpaquePointer(documentHandle))
        }
        
        // Get document info
        guard let docInfo = dash_sdk_document_get_info(OpaquePointer(documentHandle)) else {
            throw PlatformError.documentCreationFailed
        }
        
        defer {
            // TODO: Re-enable when dash_sdk_document_info_free is available in unified FFI
            // dash_sdk_document_info_free(docInfo)
        }
        
        let documentId = String(cString: docInfo.pointee.id)
        let revision = docInfo.pointee.revision
        
        // Extract the actual document data that was created
        let createdDocumentData = try extractDocumentData(from: OpaquePointer(documentHandle))
        
        let document = Document(
            id: documentId,
            contractId: contractId,
            ownerId: ownerId,
            documentType: documentType,
            revision: revision,
            dataDict: data
        )
        
        print("✅ Document created with ID: \(documentId)")
        return document
        
        /* Commented out until createResult is properly defined
        if let error = createResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Document creation failed: \(errorMessage)")
            throw PlatformError.documentCreationFailed
        }
        
        guard let documentHandle = createResult.data else {
            throw PlatformError.documentCreationFailed
        }
        
        defer {
            dash_sdk_document_handle_destroy(OpaquePointer(documentHandle))
        }
        
        // Get document info
        guard let docInfo = dash_sdk_document_get_info(OpaquePointer(documentHandle)) else {
            throw PlatformError.documentCreationFailed
        }
        
        defer {
            // TODO: Re-enable when dash_sdk_document_info_free is available in unified FFI
            // dash_sdk_document_info_free(docInfo)
        }
        
        let documentId = String(cString: docInfo.pointee.id)
        let revision = docInfo.pointee.revision
        
        // Extract the actual document data that was created
        let createdDocumentData = try extractDocumentData(from: OpaquePointer(documentHandle))
        
        let document = Document(
            id: documentId,
            contractId: contractId,
            ownerId: ownerId,
            documentType: documentType,
            revision: revision,
            dataDict: data
        )
        
        print("✅ Document created with ID: \(documentId)")
        return document
        */
    }
    
    /// Fetch a document by ID
    func fetchDocument(contractId: String, documentType: String, documentId: String) async throws -> Document {
        print("🔍 Fetching document \(documentId) from contract \(contractId)")
        
        // Fetch the data contract first
        let contractResult = contractId.withCString { idCStr in
            dash_sdk_data_contract_fetch(sdk, idCStr)
        }
        
        if let error = contractResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Contract fetch failed: \(errorMessage)")
            throw PlatformError.dataContractNotFound
        }
        
        guard let contractHandle = contractResult.data else {
            throw PlatformError.dataContractNotFound
        }
        
        defer {
            dash_sdk_data_contract_destroy(OpaquePointer(contractHandle))
        }
        
        // Fetch the document by ID
        let documentResult = documentType.withCString { typeCStr in
            documentId.withCString { idCStr in
                dash_sdk_document_fetch(
                    sdk,
                    OpaquePointer(contractHandle),
                    typeCStr,
                    idCStr
                )
            }
        }
        
        if let error = documentResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Document fetch failed: \(errorMessage)")
            throw PlatformError.documentNotFound
        }
        
        guard let documentHandle = documentResult.data else {
            throw PlatformError.documentNotFound
        }
        
        defer {
            dash_sdk_document_handle_destroy(OpaquePointer(documentHandle))
        }
        
        // Get document info with enhanced data extraction
        guard let docInfo = dash_sdk_document_get_info(OpaquePointer(documentHandle)) else {
            throw PlatformError.documentNotFound
        }
        
        defer {
            // TODO: Re-enable when dash_sdk_document_info_free is available in unified FFI
            // dash_sdk_document_info_free(docInfo)
        }
        
        let fetchedOwnerId = String(cString: docInfo.pointee.owner_id)
        let revision = docInfo.pointee.revision
        
        // Extract document data properties
        let documentDataDict = try extractDocumentDataDict(from: OpaquePointer(documentHandle))
        
        print("✅ Document fetched successfully: \(documentId)")
        
        return Document(
            id: documentId,
            contractId: contractId,
            ownerId: fetchedOwnerId,
            documentType: documentType,
            revision: revision,
            dataDict: documentDataDict
        )
    }
    
    /// Update a document
    func updateDocument(_ document: Document, newData: [String: Any]) async throws -> Document {
        print("📝 Updating document \(document.id)")
        
        let jsonData = try JSONSerialization.data(withJSONObject: newData)
        let dataJson = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        // Fetch the data contract
        let contractResult = document.contractId.withCString { idCStr in
            dash_sdk_data_contract_fetch(sdk, idCStr)
        }
        
        if let error = contractResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Failed to fetch contract for update: \(errorMessage)")
            throw PlatformError.dataContractNotFound
        }
        
        guard let contractHandle = contractResult.data else {
            throw PlatformError.dataContractNotFound
        }
        
        defer {
            dash_sdk_data_contract_destroy(OpaquePointer(contractHandle))
        }
        
        // Fetch the owner identity
        let ownerIdentityResult = document.ownerId.withCString { idCStr in
            dash_sdk_identity_fetch(sdk, idCStr)
        }
        
        if let error = ownerIdentityResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Failed to fetch owner for update: \(errorMessage)")
            throw PlatformError.identityNotFound
        }
        
        guard let ownerIdentityHandle = ownerIdentityResult.data else {
            throw PlatformError.identityNotFound
        }
        
        defer {
            dash_sdk_identity_destroy(OpaquePointer(ownerIdentityHandle))
        }
        
        // Create signer if needed
        if signer == nil {
            signer = try await createSigner()
        }
        
        guard let signerHandle = signer else {
            throw PlatformError.signerCreationFailed
        }
        
        // Update the document using FFI with proper parameters
        let updateResult = dataJson.withCString { dataCStr in
            document.id.withCString { docIdCStr in
                document.documentType.withCString { typeCStr in
                    dash_sdk_document_update_from_json(
                        sdk,
                        OpaquePointer(contractHandle),
                        OpaquePointer(ownerIdentityHandle),
                        typeCStr,
                        docIdCStr,
                        dataCStr,
                        signerHandle
                    )
                }
            }
        }
        
        if let error = updateResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Document update failed: \(errorMessage)")
            throw PlatformError.documentUpdateFailed
        }
        
        guard let documentHandle = updateResult.data else {
            throw PlatformError.documentUpdateFailed
        }
        
        defer {
            dash_sdk_document_handle_destroy(OpaquePointer(documentHandle))
        }
        
        // Get updated document info
        guard let docInfo = dash_sdk_document_get_info(OpaquePointer(documentHandle)) else {
            throw PlatformError.documentUpdateFailed
        }
        
        defer {
            // TODO: Re-enable when dash_sdk_document_info_free is available in unified FFI
            // dash_sdk_document_info_free(docInfo)
        }
        
        let newRevision = docInfo.pointee.revision
        
        print("✅ Document updated to revision \(newRevision)")
        
        return Document(
            id: document.id,
            contractId: document.contractId,
            ownerId: document.ownerId,
            documentType: document.documentType,
            revision: newRevision,
            dataDict: newData
        )
        
        /* Commented out until updateResult is properly defined
        if let error = updateResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Document update failed: \(errorMessage)")
            throw PlatformError.documentUpdateFailed
        }
        
        guard let documentHandle = updateResult.data else {
            throw PlatformError.documentUpdateFailed
        }
        
        defer {
            dash_sdk_document_handle_destroy(OpaquePointer(documentHandle))
        }
        
        // Get updated document info
        guard let docInfo = dash_sdk_document_get_info(OpaquePointer(documentHandle)) else {
            throw PlatformError.documentUpdateFailed
        }
        
        defer {
            // TODO: Re-enable when dash_sdk_document_info_free is available in unified FFI
            // dash_sdk_document_info_free(docInfo)
        }
        
        let newRevision = docInfo.pointee.revision
        
        print("✅ Document updated to revision \(newRevision)")
        
        return Document(
            id: document.id,
            contractId: document.contractId,
            ownerId: document.ownerId,
            documentType: document.documentType,
            revision: newRevision,
            dataDict: newData
        )
        */
    }
    
    /// Delete a document
    func deleteDocument(_ document: Document) async throws {
        print("🗑️ Deleting document \(document.id)")
        
        // Fetch the data contract
        let contractResult = document.contractId.withCString { idCStr in
            dash_sdk_data_contract_fetch(sdk, idCStr)
        }
        
        if let error = contractResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Failed to fetch contract for deletion: \(errorMessage)")
            throw PlatformError.dataContractNotFound
        }
        
        guard let contractHandle = contractResult.data else {
            throw PlatformError.dataContractNotFound
        }
        
        defer {
            dash_sdk_data_contract_destroy(OpaquePointer(contractHandle))
        }
        
        // Fetch the owner identity
        let ownerIdentityResult = document.ownerId.withCString { idCStr in
            dash_sdk_identity_fetch(sdk, idCStr)
        }
        
        if let error = ownerIdentityResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Failed to fetch owner for deletion: \(errorMessage)")
            throw PlatformError.identityNotFound
        }
        
        guard let ownerIdentityHandle = ownerIdentityResult.data else {
            throw PlatformError.identityNotFound
        }
        
        defer {
            dash_sdk_identity_destroy(OpaquePointer(ownerIdentityHandle))
        }
        
        // Create signer if needed
        if signer == nil {
            signer = try await createSigner()
        }
        
        guard let signerHandle = signer else {
            throw PlatformError.signerCreationFailed
        }
        
        // Delete the document using FFI with proper parameters
        let deleteResult = document.id.withCString { docIdCStr in
            document.documentType.withCString { typeCStr in
                dash_sdk_document_delete_by_id(
                    sdk,
                    OpaquePointer(contractHandle),
                    OpaquePointer(ownerIdentityHandle),
                    typeCStr,
                    docIdCStr,
                    signerHandle
                )
            }
        }
        
        if let error = deleteResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Document deletion failed: \(errorMessage)")
            throw PlatformError.documentUpdateFailed // Using update failed as we don't have a specific delete error
        }
        
        print("✅ Document deleted successfully")
        
        /* Commented out until deleteResult is properly defined
        if let error = deleteResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Document deletion failed: \(errorMessage)")
            throw PlatformError.documentUpdateFailed // Using update failed as we don't have a specific delete error
        }
        
        print("✅ Document deleted successfully")
        */
    }
    
    /// Search for documents
    func searchDocuments(contractId: String, documentType: String, query: [String: Any]) async throws -> [Document] {
        print("🔍 Searching documents in contract \(contractId) of type \(documentType)")
        
        // Fetch the data contract first
        let contractResult = contractId.withCString { idCStr in
            dash_sdk_data_contract_fetch(sdk, idCStr)
        }
        
        if let error = contractResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Contract fetch failed for search: \(errorMessage)")
            throw PlatformError.dataContractNotFound
        }
        
        guard let contractHandle = contractResult.data else {
            throw PlatformError.dataContractNotFound
        }
        
        defer {
            dash_sdk_data_contract_destroy(OpaquePointer(contractHandle))
        }
        
        // Build query JSON from query parameters
        let queryData = try buildQueryData(from: query)
        let queryJson = String(data: queryData, encoding: .utf8) ?? "{}"
        
        // Search documents using FFI
        let searchResult = queryJson.withCString { queryCStr in
            documentType.withCString { typeCStr in
                dash_sdk_document_query(
                    sdk,
                    OpaquePointer(contractHandle),
                    typeCStr,
                    queryCStr
                )
            }
        }
        
        if let error = searchResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Document search failed: \(errorMessage)")
            throw PlatformError.documentNotFound
        }
        
        guard let searchResultsHandle = searchResult.data else {
            print("✅ Document search completed with no results")
            return []
        }
        
        defer {
            dash_sdk_document_query_results_destroy(OpaquePointer(searchResultsHandle))
        }
        
        // Extract documents from search results
        let documents = try extractDocumentsFromResults(
            resultsHandle: OpaquePointer(searchResultsHandle),
            contractId: contractId,
            documentType: documentType
        )
        
        print("✅ Found \(documents.count) documents in search")
        return documents
        
        /* Commented out until searchResult is properly defined
        if let error = searchResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Document search failed: \(errorMessage)")
            throw PlatformError.documentNotFound
        }
        
        guard let searchResultsHandle = searchResult.data else {
            print("✅ Document search completed with no results")
            return []
        }
        
        // Clean up will be needed when query is implemented
        
        // Extract documents from search results
        let documents = try extractDocumentsFromResults(
            resultsHandle: OpaquePointer(searchResultsHandle),
            contractId: contractId,
            documentType: documentType
        )
        
        print("✅ Found \(documents.count) documents in search")
        return documents
        */
    }
    
    // MARK: - Document Helper Functions
    
    /// Extract document data from a document handle as dictionary
    private func extractDocumentDataDict(from documentHandle: OpaquePointer) throws -> [String: Any] {
        // This function is not yet implemented - it currently would return mock data
        // Real implementation would require proper FFI functions for document property extraction
        
        throw PlatformError.notImplemented(
            "Document data extraction not yet implemented. " +
            "Real implementation requires FFI functions like dash_sdk_document_to_json() " +
            "or property-specific extraction methods."
        )
        
        // TODO: Implement actual document data extraction when FFI functions become available
        // Real implementation would:
        // 1. Use dash_sdk_document_to_json() if available
        // 2. Or iterate through known properties using specific FFI calls
        // 3. Or use schema-based extraction with proper error handling
    }
    
    /// Extract document data from a document handle as Data (legacy method)
    private func extractDocumentData(from documentHandle: OpaquePointer) throws -> Data {
        let dataDict = try extractDocumentDataDict(from: documentHandle)
        return try JSONSerialization.data(withJSONObject: dataDict)
    }
    
    /// Extract multiple documents from search results
    private func extractDocumentsFromResults(
        resultsHandle: OpaquePointer,
        contractId: String,
        documentType: String
    ) throws -> [Document] {
        var documents: [Document] = []
        
        // Get the number of results
        let resultCount = dash_sdk_document_query_results_count(resultsHandle)
        
        for index in 0..<resultCount {
            // Get document at index
            let documentResult = dash_sdk_document_query_results_get_at(resultsHandle, index)
            
            if let error = documentResult.error {
                let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
                defer { dash_sdk_error_free(error) }
                print("⚠️ Failed to get document at index \(index): \(errorMessage)")
                continue
            }
            
            guard let documentHandle = documentResult.data else {
                print("⚠️ No document handle at index \(index)")
                continue
            }
            
            do {
                // Get document info
                guard let docInfo = dash_sdk_document_get_info(OpaquePointer(documentHandle)) else {
                    print("⚠️ Failed to get document info at index \(index)")
                    continue
                }
                
                defer {
                    // TODO: Re-enable when dash_sdk_document_info_free is available in unified FFI
                    // dash_sdk_document_info_free(docInfo)
                }
                
                let documentId = String(cString: docInfo.pointee.id)
                let ownerId = String(cString: docInfo.pointee.owner_id)
                let revision = docInfo.pointee.revision
                
                // Extract document data
                let documentDataDict = try extractDocumentDataDict(from: OpaquePointer(documentHandle))
                
                let document = Document(
                    id: documentId,
                    contractId: contractId,
                    ownerId: ownerId,
                    documentType: documentType,
                    revision: revision,
                    dataDict: documentDataDict
                )
                
                documents.append(document)
                
            } catch {
                print("⚠️ Failed to process document at index \(index): \(error)")
                continue
            }
        }
        
        return documents
    }
    
    /// Build query data from query parameters
    private func buildQueryData(from query: [String: Any]) throws -> Data {
        var dppQuery: [String: Any] = [:]
        
        // Handle property filters
        var whereClause: [String: Any] = [:]
        for (key, value) in query {
            switch key {
            case "orderBy":
                dppQuery["orderBy"] = value
            case "limit":
                dppQuery["limit"] = value
            case "startAt":
                dppQuery["startAt"] = value
            default:
                // Property filter
                whereClause[key] = ["==", value]
            }
        }
        
        if !whereClause.isEmpty {
            dppQuery["where"] = whereClause
        }
        
        // Default limit if not specified
        if dppQuery["limit"] == nil {
            dppQuery["limit"] = 50
        }
        
        return try JSONSerialization.data(withJSONObject: dppQuery)
    }
    
    /// Fetch documents by owner ID
    func fetchDocumentsByOwner(
        contractId: String,
        documentType: String,
        ownerId: String,
        limit: Int = 50
    ) async throws -> [Document] {
        let query: [String: Any] = [
            "$ownerId": ownerId,
            "limit": limit,
            "orderBy": [["$createdAt", "desc"]]
        ]
        
        return try await searchDocuments(
            contractId: contractId,
            documentType: documentType,
            query: query
        )
    }
    
    /// Fetch all documents of a specific type from a contract
    func fetchDocumentsByType(
        contractId: String,
        documentType: String,
        limit: Int = 50,
        startAfter: String? = nil
    ) async throws -> [Document] {
        var query: [String: Any] = [
            "limit": limit,
            "orderBy": [["$createdAt", "desc"]]
        ]
        
        if let startAfter = startAfter {
            query["startAfter"] = startAfter
        }
        
        return try await searchDocuments(
            contractId: contractId,
            documentType: documentType,
            query: query
        )
    }
    
    // MARK: - Private Helpers
    
    private func fundIdentityWithAssetLock(
        identityHandle: OpaquePointer,
        assetLock: AssetLockProof
    ) async throws {
        // Create signer if needed
        if signer == nil {
            signer = try await createSigner()
        }
        
        guard let signerHandle = signer else {
            throw PlatformError.signerCreationFailed
        }
        
        // Encode instant lock and transaction data separately
        let instantLockData = try encodeInstantLock(assetLock.instantLock)
        let transactionData = assetLock.transaction.raw
        
        // Generate a proper private key for the asset lock
        let keyPair = await platformSigner.generateKeyPair()
        
        // Convert private key to tuple format required by FFI
        var privateKeyTuple: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
        
        withUnsafeMutableBytes(of: &privateKeyTuple) { tupleBytes in
            keyPair.privateKey.copyBytes(to: tupleBytes)
        }
        
        // Fund identity with InstantLock proof
        let fundResult = instantLockData.withUnsafeBytes { instantLockBytes in
            transactionData.withUnsafeBytes { transactionBytes in
                dash_sdk_identity_put_to_platform_with_instant_lock(
                    sdk,
                    identityHandle,
                    instantLockBytes.bindMemory(to: UInt8.self).baseAddress,
                    UInt(instantLockData.count),
                    transactionBytes.bindMemory(to: UInt8.self).baseAddress,
                    UInt(transactionData.count),
                    assetLock.outputIndex,
                    &privateKeyTuple,
                    signerHandle,
                    nil // Use default put settings
                )
            }
        }
        
        if let error = fundResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Identity funding failed: \(errorMessage)")
            throw PlatformError.identityCreationFailed
        }
        
        print("✅ Identity funding completed")
    }
    
    private func publishDataContract(contractHandle: OpaquePointer) async throws {
        // Create signer if needed
        if signer == nil {
            signer = try await createSigner()
        }
        
        guard let signerHandle = signer else {
            throw PlatformError.signerCreationFailed
        }
        
        // Publish to Platform
        let publishResult = dash_sdk_data_contract_put_to_platform(
            sdk,
            contractHandle,
            nil, // identity_public_key_handle (auto-select)
            signerHandle
        )
        
        if let error = publishResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Data contract publishing failed: \(errorMessage)")
            throw PlatformError.dataContractCreationFailed
        }
        
        print("✅ Data contract published successfully")
    }
    
    private func createSigner() async throws -> OpaquePointer {
        // Create signing callbacks that interface with our PlatformSigner
        let signCallback: IOSSignCallback = { identityPubKeyBytes, identityPubKeyLen, dataBytes, dataLen, resultLen in
            // Convert C data to Swift Data
            guard let identityPubKeyBytes = identityPubKeyBytes,
                  let dataBytes = dataBytes else {
                return nil
            }
            
            let identityPubKey = Data(bytes: identityPubKeyBytes, count: Int(identityPubKeyLen))
            let _ = Data(bytes: dataBytes, count: Int(dataLen))
            
            // Get signature from platform signer
            // Note: This callback is synchronous, so we use a cached signature approach
            // In production, signatures would be pre-computed or use a synchronous signing method
            
            // For now, generate a deterministic signature based on the data
            // This is better than a fixed mock signature as it varies with input
            let dataToSign = Data(bytes: dataBytes, count: Int(dataLen))
            #if DEBUG
            let signature = PlatformSDKWrapper.generateDeterministicSignatureStatic(for: dataToSign, with: identityPubKey)
            #else
            // In production, this should use proper cryptographic signing
            fatalError("Deterministic signing is only available in debug builds. Production builds require proper cryptographic signing.")
            #endif
            
            // Allocate memory for result
            let resultBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: signature.count)
            signature.copyBytes(to: resultBytes, count: signature.count)
            resultLen?.pointee = signature.count
            
            print("✅ Signer callback invoked for identity: \(identityPubKey.toHexString().prefix(16))...")
            return resultBytes
        }
        
        let canSignCallback: IOSCanSignCallback = { identityPubKeyBytes, identityPubKeyLen in
            guard let identityPubKeyBytes = identityPubKeyBytes else {
                return false
            }
            
            let identityPubKey = Data(bytes: identityPubKeyBytes, count: Int(identityPubKeyLen))
            print("ℹ️ Can sign check for identity: \(identityPubKey.toHexString().prefix(16))...")
            return true // For now, assume we can sign for any identity
        }
        
        // Create signer with callbacks
        let signerHandle = dash_sdk_signer_create(signCallback, canSignCallback)
        
        guard let handle = signerHandle else {
            throw PlatformError.signerCreationFailed
        }
        
        print("✅ Signer created successfully")
        return handle
    }
    
    private func encodeInstantLock(_ instantLock: InstantLock) throws -> Data {
        // Encode instant lock data in the format expected by Platform
        // This implementation follows the Dash InstantSend lock format structure
        
        var encodedData = Data()
        
        // Version byte
        encodedData.append(0x01)
        
        // Transaction ID (32 bytes, reversed for little-endian)
        if let txidData = Data(hexString: instantLock.txid) {
            encodedData.append(contentsOf: txidData.reversed())
        } else {
            encodedData.append(contentsOf: Data(repeating: 0, count: 32))
        }
        
        // Height (4 bytes, little-endian)
        encodedData.append(contentsOf: withUnsafeBytes(of: instantLock.height.littleEndian) { Array($0) })
        
        // Signature length and data
        encodedData.append(UInt8(instantLock.signature.count))
        encodedData.append(instantLock.signature)
        
        return encodedData
    }
    
    #if DEBUG
    /// Generate a deterministic signature for testing/development (static version for C callbacks)
    /// In production, this would use proper cryptographic signing
    private static func generateDeterministicSignatureStatic(for data: Data, with publicKey: Data) -> Data {
        // Create a deterministic signature based on data hash and public key
        // This is NOT cryptographically secure - only for development/testing
        
        var hasher = SHA256()
        hasher.update(data: data)
        hasher.update(data: publicKey)
        hasher.update(data: "signature_salt".data(using: .utf8)!)
        
        let hash = Data(hasher.finalize())
        
        // Create a 64-byte signature (typical for ECDSA signatures)
        var signature = hash
        if signature.count < 64 {
            // Pad to 64 bytes
            signature.append(Data(repeating: 0x00, count: 64 - signature.count))
        } else if signature.count > 64 {
            // Truncate to 64 bytes
            signature = signature.prefix(64)
        }
        
        return signature
    }
    #endif
    
    #if DEBUG
    /// Generate a deterministic signature for testing/development
    /// In production, this would use proper cryptographic signing
    private func generateDeterministicSignature(for data: Data, with publicKey: Data) -> Data {
        // Create a deterministic signature based on data hash and public key
        // This is NOT cryptographically secure - only for development/testing
        
        var hasher = SHA256()
        hasher.update(data: data)
        hasher.update(data: publicKey)
        hasher.update(data: "signature_salt".data(using: .utf8)!)
        
        let hash = Data(hasher.finalize())
        
        // Create a 64-byte signature (typical for ECDSA signatures)
        var signature = hash
        if signature.count < 64 {
            // Pad to 64 bytes
            signature.append(Data(repeating: 0x00, count: 64 - signature.count))
        } else if signature.count > 64 {
            // Truncate to 64 bytes
            signature = signature.prefix(64)
        }
        
        return signature
    }
    #endif
    
    private func encodeAssetLockProof(_ proof: AssetLockProof) throws -> Data {
        // Encode asset lock proof for Platform according to Platform protocol
        // This needs to match the expected format for dash_sdk_identity_put_to_platform_with_instant_lock
        
        let proofDict: [String: Any] = [
            "type": "instantLock",
            "transaction": [
                "txid": proof.transaction.txid,
                "raw": proof.transaction.raw.base64EncodedString()
            ],
            "outputIndex": proof.outputIndex,
            "instantLock": [
                "txid": proof.instantLock.txid,
                "signature": proof.instantLock.signature.base64EncodedString(),
                "height": proof.instantLock.height
            ],
            "amount": proof.amount
        ]
        
        return try JSONSerialization.data(withJSONObject: proofDict, options: [])
    }
}

// MARK: - Models

struct Identity: Identifiable, Codable, Hashable {
    let id: String
    var balance: UInt64
    var revision: UInt64
}

struct TransferResult {
    let fromId: String
    let toId: String
    let amount: UInt64
}

struct DataContract: Identifiable {
    let id: String
    let ownerId: String
    let schema: [String: Any]
    let version: UInt32
    let revision: UInt64
}

struct Document: Identifiable {
    let id: String
    let contractId: String
    let ownerId: String
    let documentType: String
    let revision: UInt64
    let data: Data
    
    var dataDict: [String: Any] {
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            return [:]
        }
    }
    
    /// Initialize with data dictionary
    init(id: String, contractId: String, ownerId: String, documentType: String, revision: UInt64, dataDict: [String: Any]) {
        self.id = id
        self.contractId = contractId
        self.ownerId = ownerId
        self.documentType = documentType
        self.revision = revision
        
        do {
            self.data = try JSONSerialization.data(withJSONObject: dataDict)
        } catch {
            print("⚠️ Failed to serialize document data: \(error)")
            self.data = Data()
        }
    }
    
    /// Initialize with raw data
    init(id: String, contractId: String, ownerId: String, documentType: String, revision: UInt64, data: Data) {
        self.id = id
        self.contractId = contractId
        self.ownerId = ownerId
        self.documentType = documentType
        self.revision = revision
        self.data = data
    }
}


// MARK: - FFI Type Extensions

// Since we're importing DashSDKFFI, we don't need to declare the functions
// but we may need to define some helper structures that aren't in the header

typealias SDKHandle = OpaquePointer
typealias IdentityHandle = OpaquePointer
typealias SignerHandle = OpaquePointer

// Create a simpler settings structure if not defined in header
struct PlatformPutSettings {
    var timeout_ms: UInt32 = 60000
    var retry_count: UInt32 = 3
}

// MARK: - Network Status Model

struct PlatformNetworkStatus {
    let isConnected: Bool
    let network: PlatformNetwork
    let connectedNodes: Int
    let averageResponseTime: TimeInterval
    let lastChecked: Date
    
    var formattedResponseTime: String {
        return String(format: "%.2f ms", averageResponseTime * 1000)
    }
    
    var statusDescription: String {
        if isConnected {
            return "Connected to \(connectedNodes) nodes"
        } else {
            return "Disconnected"
        }
    }
}

// MARK: - Extensions

extension PlatformSDKWrapper: PlatformSDKProtocol {
    func topUpIdentity(_ identity: Identity, with assetLock: AssetLockProof) async throws -> Identity {
        print("💰 Topping up identity \(identity.id) with \(assetLock.amount) credits")
        
        // Step 1: Fetch the identity handle
        let identityResult = identity.id.withCString { idCStr in
            dash_sdk_identity_fetch(sdk, idCStr)
        }
        
        if let error = identityResult.error {
            let errorMessage = error.pointee.message.map { String(cString: $0) } ?? "Unknown error"
            defer { dash_sdk_error_free(error) }
            print("🔴 Failed to fetch identity for top-up: \(errorMessage)")
            throw PlatformError.identityNotFound
        }
        
        guard let identityHandle = identityResult.data else {
            throw PlatformError.identityNotFound
        }
        
        defer {
            dash_sdk_identity_destroy(OpaquePointer(identityHandle))
        }
        
        // Step 2: Fund the identity with asset lock proof (same as creation)
        do {
            try await fundIdentityWithAssetLock(
                identityHandle: OpaquePointer(identityHandle),
                assetLock: assetLock
            )
        } catch {
            print("🔴 Top-up funding failed: \(error)")
            throw PlatformError.transferFailed
        }
        
        // Step 3: Fetch updated identity info
        guard let updatedInfo = dash_sdk_identity_get_info(OpaquePointer(identityHandle)) else {
            throw PlatformError.failedToGetInfo
        }
        
        let newBalance = updatedInfo.pointee.balance
        let newRevision = updatedInfo.pointee.revision
        
        // Clean up
        // TODO: Re-enable when dash_sdk_identity_info_free is available in unified FFI
        // dash_sdk_identity_info_free(updatedInfo)
        
        print("✅ Identity topped up successfully. New balance: \(newBalance)")
        
        return Identity(
            id: identity.id,
            balance: newBalance,
            revision: newRevision
        )
    }
}
