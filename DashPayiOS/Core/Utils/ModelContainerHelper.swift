import Foundation
import SwiftData
import SwiftDashCoreSDK
import SQLite3

// Transaction, UTXO, and Balance types are now imported from SwiftDashCoreSDK
// WatchedAddress type alias removed to avoid conflicts with SwiftDashCoreSDK.WatchedAddress

// MARK: - Wallet Migration Plan

/// Migration plan for wallet-related models to handle schema evolution
enum WalletMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [WalletSchemaV1.self]
    }
    
    static var stages: [MigrationStage] {
        // No migrations yet - this is V1
        []
    }
}

/// Version 1 of the wallet schema - initial version
enum WalletSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }
    
    static var models: [any PersistentModel.Type] {
        [
            HDWallet.self,
            HDAccount.self,
            HDWatchedAddress.self,
            Transaction.self,
            LocalUTXO.self,
            SyncState.self,
            Balance.self
        ]
    }
}

// MARK: - Database Validation

/// Minimal database validation for table existence
struct DatabaseValidator {
    static func tableExists(_ tableName: String, at url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return false
        }
        defer { sqlite3_close(db) }
        
        let query = "SELECT name FROM sqlite_master WHERE type='table' AND name=?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, tableName, -1, nil)
        return sqlite3_step(statement) == SQLITE_ROW
    }
}

// MARK: - Database Error

enum DatabaseError: LocalizedError {
    case missingTable(String)
    
    var errorDescription: String? {
        switch self {
        case .missingTable(let table):
            return "Missing required table: \(table)"
        }
    }
}

/// Helper for creating and managing SwiftData ModelContainer with migration support
struct ModelContainerHelper {
    
    /// Create a ModelContainer with automatic migration recovery
    static func createContainer() throws -> ModelContainer {
        // Use versioned schema from migration plan
        let schema = Schema(versionedSchema: WalletSchemaV1.self)
        
        // Also include platform models that aren't part of wallet schema
        let fullSchema = Schema([
            HDWallet.self,
            HDAccount.self,
            HDWatchedAddress.self,
            Transaction.self,
            LocalUTXO.self,
            SyncState.self,
            Balance.self,
            PersistentIdentity.self,
            PersistentDocument.self
        ])
        
        // Check if we have migration issues by looking for specific error patterns
        let shouldCleanup = UserDefaults.standard.bool(forKey: "ForceModelCleanup")
        
        // Also check for a debug cleanup flag for testing
        #if DEBUG
        let debugCleanup = UserDefaults.standard.bool(forKey: "DebugForceCleanup")
        if debugCleanup {
            print("Debug force cleanup requested, removing all data...")
            cleanupCorruptStore()
            UserDefaults.standard.set(false, forKey: "DebugForceCleanup")
        }
        #endif
        
        if shouldCleanup {
            print("Force cleanup requested, removing all data...")
            cleanupCorruptStore()
            UserDefaults.standard.set(false, forKey: "ForceModelCleanup")
        }
        
        do {
            // First attempt: try to create normally with migration support
            return try createContainer(with: fullSchema, migrationPlan: WalletMigrationPlan.self, inMemory: false)
        } catch {
            print("Initial ModelContainer creation failed: \(error)")
            print("Detailed error: \(error.localizedDescription)")
            
            // Check if it's a migration error, model error, or missing table error
            let errorSubstrings = [
                "migration",
                "relationship",
                "to-one",
                "to-many",
                "materialize",
                "Array",
                "no such table",
                "ZHDWATCHEDADDRESS"
            ]
            
            if errorSubstrings.contains(where: { error.localizedDescription.contains($0) }) {
                print("Model/Migration error detected, performing complete cleanup...")
                UserDefaults.standard.set(true, forKey: "ForceModelCleanup")
            }
            
            // Second attempt: clean up and retry
            cleanupCorruptStore()
            
            do {
                return try createContainer(with: fullSchema, migrationPlan: WalletMigrationPlan.self, inMemory: false)
            } catch {
                print("Failed to create persistent store after cleanup: \(error)")
                
                // Final attempt: in-memory store
                print("Falling back to in-memory store")
                return try createContainer(with: fullSchema, migrationPlan: WalletMigrationPlan.self, inMemory: true)
            }
        }
    }
    
    private static func createContainer(
        with schema: Schema,
        migrationPlan: (any SchemaMigrationPlan.Type)? = nil,
        inMemory: Bool
    ) throws -> ModelContainer {
        print("Creating ModelContainer with schema containing \(schema.entities.count) entities")
        
        // Ensure directories exist
        if !inMemory {
            ensureApplicationSupportDirectoryExists()
        }
        
        // Create a custom store URL to avoid default.store issues
        let storeURL: URL?
        if !inMemory {
            if let appSupportURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first {
                let storeDirectory = appSupportURL.appendingPathComponent("DashPay")
                try? FileManager.default.createDirectory(
                    at: storeDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                storeURL = storeDirectory.appendingPathComponent("DashPayWallet.sqlite")
                print("Using custom store URL: \(storeURL!.path)")
            } else {
                storeURL = nil
            }
        } else {
            storeURL = nil
        }
        
        // Create configuration based on whether we're using custom URL or not
        let modelConfiguration: ModelConfiguration
        if let storeURL = storeURL {
            // Use custom URL with simpler initializer
            modelConfiguration = ModelConfiguration(
                url: storeURL
            )
        } else {
            // Use default configuration
            modelConfiguration = ModelConfiguration(
                isStoredInMemoryOnly: inMemory,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
        }
        
        print("Configuration: inMemory=\(inMemory)")
        
        do {
            let container: ModelContainer
            
            // Validate database before creation if not in-memory
            if !inMemory, let storeURL = storeURL, FileManager.default.fileExists(atPath: storeURL.path) {
                // Check specifically for missing ZHDWATCHEDADDRESS table
                if !DatabaseValidator.tableExists("ZHDWATCHEDADDRESS", at: storeURL) {
                    print("⚠️ Critical table ZHDWATCHEDADDRESS is missing - will recreate database")
                    throw DatabaseError.missingTable("ZHDWATCHEDADDRESS")
                }
            }
            
            // Create container with or without migration plan
            if let migrationPlan = migrationPlan {
                container = try ModelContainer(
                    for: schema,
                    migrationPlan: migrationPlan,
                    configurations: [modelConfiguration]
                )
            } else {
                container = try ModelContainer(
                    for: schema,
                    configurations: [modelConfiguration]
                )
            }
            
            print("✅ ModelContainer created successfully")
            
            // Perform post-creation validation
            if !inMemory {
                // Validation will be performed when the container is first used
                // to avoid MainActor issues during initialization
            }
            
            return container
        } catch {
            print("❌ Failed to create ModelContainer: \(error)")
            print("Error type: \(type(of: error))")
            if let nsError = error as NSError? {
                print("Error domain: \(nsError.domain)")
                print("Error code: \(nsError.code)")
                print("Error userInfo: \(nsError.userInfo)")
            }
            throw error
        }
    }
    
    static func cleanupCorruptStore() {
        print("Starting cleanup of corrupt store...")
        
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        
        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first
        
        // Clean up specific SQLite and SwiftData related files
        let exactFilenames = [
            "default.store",
            "default.store-shm",
            "default.store-wal",
            "DashPayWallet.sqlite",
            "DashPayWallet.sqlite-shm",
            "DashPayWallet.sqlite-wal"
        ]
        
        let prefixesToRemove = [
            "default",
            "DashPayWallet"
        ]
        
        let containsPatterns = [
            "SwiftData",
            "ModelContainer"
        ]
        
        // Clean up all files in Application Support that could be related to the store
        if let contents = try? FileManager.default.contentsOfDirectory(at: appSupportURL, includingPropertiesForKeys: nil) {
            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                
                // Check if file matches any of our specific criteria
                let shouldRemove = exactFilenames.contains(filename) ||
                                 prefixesToRemove.contains { filename.hasPrefix($0) } ||
                                 containsPatterns.contains { filename.contains($0) }
                
                if shouldRemove {
                    do {
                        try FileManager.default.removeItem(at: fileURL)
                        print("Removed: \(filename)")
                    } catch {
                        print("Failed to remove \(filename): \(error)")
                    }
                }
            }
        }
        
        // Also clean up Documents directory
        if let documentsURL = documentsURL,
           let contents = try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil) {
            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                
                // Check if file matches any of our specific criteria
                let shouldRemove = exactFilenames.contains(filename) ||
                                 prefixesToRemove.contains { filename.hasPrefix($0) } ||
                                 containsPatterns.contains { filename.contains($0) }
                
                if shouldRemove {
                    do {
                        try FileManager.default.removeItem(at: fileURL)
                        print("Removed from Documents: \(filename)")
                    } catch {
                        print("Failed to remove from Documents \(filename): \(error)")
                    }
                }
            }
        }
        
        // Clear any cached SwiftData files
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        if let cacheURL = cacheURL {
            let swiftDataCache = cacheURL.appendingPathComponent("SwiftData")
            if FileManager.default.fileExists(atPath: swiftDataCache.path) {
                do {
                    try FileManager.default.removeItem(at: swiftDataCache)
                    print("Removed SwiftData cache")
                } catch {
                    print("Failed to remove SwiftData cache: \(error)")
                }
            }
        }
        
        print("Store cleanup completed")
    }
    
    private static func ensureApplicationSupportDirectoryExists() {
        let fileManager = FileManager.default
        
        // Get Application Support directory
        guard let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            print("Failed to get Application Support directory")
            return
        }
        
        // Create if it doesn't exist
        if !fileManager.fileExists(atPath: appSupportURL.path) {
            do {
                try fileManager.createDirectory(
                    at: appSupportURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                print("Created Application Support directory at: \(appSupportURL.path)")
            } catch {
                print("Failed to create Application Support directory: \(error)")
            }
        }
        
        // Also ensure Documents directory exists for iOS
        #if os(iOS)
        guard let documentsURL = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            print("Failed to get Documents directory")
            return
        }
        
        if !fileManager.fileExists(atPath: documentsURL.path) {
            do {
                try fileManager.createDirectory(
                    at: documentsURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                print("Created Documents directory at: \(documentsURL.path)")
            } catch {
                print("Failed to create Documents directory: \(error)")
            }
        }
        #endif
    }
    
    /// Check if the current store needs migration
    static func needsMigration(for container: ModelContainer) -> Bool {
        // Check if migration is needed by comparing stored schema version
        // with current WalletSchemaV1 version
        let currentVersion = WalletSchemaV1.versionIdentifier
        
        // In SwiftData, migration detection is primarily handled by the migration plan itself.
        // However, we can check if there's a stored version indicator in UserDefaults
        // or attempt to detect schema mismatches through model access.
        
        // Check if we have a stored schema version
        let storedVersionKey = "WalletSchemaVersion"
        if let storedVersionString = UserDefaults.standard.string(forKey: storedVersionKey),
           let storedVersion = parseVersionString(storedVersionString) {
            
            // Compare versions - migration needed if stored version is different
            let migrationNeeded = !areVersionsEqual(storedVersion, currentVersion)
            
            if migrationNeeded {
                print("Migration needed: stored version \(storedVersion) != current version \(currentVersion)")
            } else {
                print("No migration needed: versions match (\(currentVersion))")
            }
            
            return migrationNeeded
        }
        
        // If no stored version exists, this is likely a new installation
        // Store the current version for future comparison
        let currentVersionString = "\(currentVersion.major).\(currentVersion.minor).\(currentVersion.patch)"
        UserDefaults.standard.set(currentVersionString, forKey: storedVersionKey)
        
        // Try to detect if the existing database schema matches our current models
        // by attempting to access the model context
        do {
            let context = container.mainContext
            // Attempt a simple fetch to verify the schema is compatible
            _ = try context.fetchCount(FetchDescriptor<HDWallet>())
            
            // If we can access the models successfully, no migration needed
            print("No migration needed: database schema is compatible with current models")
            return false
        } catch {
            // If we can't access the models, a migration might be needed
            // This could indicate a schema mismatch
            print("Potential migration needed: schema validation failed with error: \(error)")
            
            // Check if this is a specific migration-related error
            let migrationErrorSubstrings = [
                "migration",
                "schema",
                "model"
            ]
            
            if migrationErrorSubstrings.contains(where: { error.localizedDescription.contains($0) }) {
                return true
            }
            
            // For other errors, assume no migration needed as the error might be unrelated
            return false
        }
    }
    
    /// Parse a version string into a Schema.Version
    private static func parseVersionString(_ versionString: String) -> Schema.Version? {
        let components = versionString.components(separatedBy: ".")
        guard components.count >= 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]) else {
            return nil
        }
        
        return Schema.Version(major, minor, patch)
    }
    
    /// Compare two Schema.Version instances for equality
    private static func areVersionsEqual(_ version1: Schema.Version, _ version2: Schema.Version) -> Bool {
        return version1.major == version2.major &&
               version1.minor == version2.minor &&
               version1.patch == version2.patch
    }
    
    /// Validate container tables - should be called on first use
    @MainActor
    static func validateContainerTables(_ container: ModelContainer) throws {
        try validateAndRecoverIfNeeded(container: container)
    }
    
    /// Validate container and attempt recovery if needed
    @MainActor
    private static func validateAndRecoverIfNeeded(container: ModelContainer) throws {
        let context = container.mainContext
        
        // Try to access each model type to ensure tables exist
        do {
            // Attempt minimal fetches to verify table existence
            _ = try context.fetchCount(FetchDescriptor<HDWallet>())
            _ = try context.fetchCount(FetchDescriptor<HDAccount>())
            _ = try context.fetchCount(FetchDescriptor<HDWatchedAddress>())
            _ = try context.fetchCount(FetchDescriptor<Transaction>())
            _ = try context.fetchCount(FetchDescriptor<LocalUTXO>())
            _ = try context.fetchCount(FetchDescriptor<SyncState>())
            _ = try context.fetchCount(FetchDescriptor<Balance>())
            
            print("✅ All required tables validated successfully")
        } catch {
            print("❌ Table validation failed: \(error)")
            
            // Check for specific table errors
            if error.localizedDescription.contains("no such table") {
                if error.localizedDescription.contains("ZHDWATCHEDADDRESS") {
                    print("Critical: ZHDWATCHEDADDRESS table is missing")
                    throw DatabaseError.missingTable("ZHDWATCHEDADDRESS")
                }
                
                // If we detect missing tables, we need to recreate the database
                // This will be handled by the cleanup and retry logic in createContainer
            } else {
                throw error
            }
        }
    }
    
    /// Export wallet data before migration
    static func exportDataForMigration(from context: ModelContext) throws -> Data? {
        do {
            let wallets = try context.fetch(FetchDescriptor<HDWallet>())
            
            // Create export structure
            let exportData = MigrationExportData(
                wallets: wallets.map { wallet in
                    MigrationWallet(
                        id: wallet.id,
                        name: wallet.name,
                        network: wallet.network,
                        encryptedSeed: wallet.encryptedSeed,
                        seedHash: wallet.seedHash,
                        createdAt: wallet.createdAt
                    )
                }
            )
            
            return try JSONEncoder().encode(exportData)
        } catch {
            print("Failed to export data for migration: \(error)")
            return nil
        }
    }
}

// MARK: - Migration Data Structures

private struct MigrationExportData: Codable {
    let wallets: [MigrationWallet]
}

private struct MigrationWallet: Codable {
    let id: UUID
    let name: String
    let network: DashNetwork
    let encryptedSeed: Data
    let seedHash: String
    let createdAt: Date
}