# ZHDWATCHEDADDRESS Table Error Fix Summary

## Problem
The app was encountering a CoreData error: "no such table: ZHDWATCHEDADDRESS" during sync operations. This occurred because the SwiftData schema defined `HDWatchedAddress` as a model, but the SQLite database file didn't have the corresponding table.

## Root Cause
1. **Schema Mismatch**: The ModelContainerHelper included HDWatchedAddress in its schema, but the existing database wasn't properly migrated to include this table.
2. **Missing Migration Plan**: Unlike the Platform models, the wallet models didn't have a migration plan defined.
3. **Incomplete Error Recovery**: The existing error handling didn't specifically check for missing table errors.

## Solution Implemented

### 1. Added Migration Support (Inline in ModelContainerHelper.swift)
- Created `WalletMigrationPlan` enum implementing `SchemaMigrationPlan`
- Created `WalletSchemaV1` enum implementing `VersionedSchema` with all wallet models
- This provides a foundation for future schema migrations

### 2. Added Database Validation
- Created `DatabaseValidator` struct with table existence checking
- Added pre-flight validation before container creation
- Specific check for ZHDWATCHEDADDRESS table existence

### 3. Enhanced Error Handling
- Added specific error detection for "no such table" errors
- Improved error messages to identify missing ZHDWATCHEDADDRESS table
- Enhanced cleanup logic to handle table-specific errors

### 4. Improved Recovery Mechanism
- When ZHDWATCHEDADDRESS table is missing, the database is recreated
- Added validation after container creation to ensure all tables exist
- Graceful fallback to in-memory store if persistent store fails

## Key Changes

### ModelContainerHelper.swift
```swift
// Added inline migration plan and database validation
enum WalletMigrationPlan: SchemaMigrationPlan { ... }
enum WalletSchemaV1: VersionedSchema { ... }
struct DatabaseValidator { ... }

// Enhanced container creation with:
- Migration plan support
- Pre-creation database validation
- Specific ZHDWATCHEDADDRESS table checking
- Post-creation table validation
```

## Testing
Created comprehensive test suites:
- `DatabaseValidationTests.swift` - Tests database creation and validation
- `HDWatchedAddressTableTests.swift` - Tests specific to HDWatchedAddress operations
- `WalletMigrationPlanTests.swift` - Tests migration plan functionality

## Verification
To verify the fix works:
1. The app now checks for ZHDWATCHEDADDRESS table before operations
2. If missing, it triggers database recreation
3. All wallet operations (create, sync, address generation) work without table errors

## Benefits
1. **Automatic Recovery**: App automatically recovers from missing table errors
2. **Future-Proof**: Migration plan structure allows for future schema changes
3. **Better Diagnostics**: Improved error messages help identify issues quickly
4. **Robust Testing**: Comprehensive test coverage ensures reliability

## Next Steps
1. Monitor for any table-related errors in production
2. Consider adding telemetry for database recreation events
3. Plan for future schema migrations as needed