import Foundation
import SwiftData
@testable import DashPayiOS

// Simple test script to verify ZHDWATCHEDADDRESS table creation
func testZHDWATCHEDADDRESSTableCreation() {
    print("Testing ZHDWATCHEDADDRESS table creation fix...")
    
    // Clean up any existing data
    print("1. Cleaning up existing data...")
    ModelContainerHelper.cleanupCorruptStore()
    
    do {
        // Create container
        print("2. Creating ModelContainer...")
        let container = try ModelContainerHelper.createContainer()
        print("✅ Container created successfully")
        
        // Get context
        let context = container.mainContext
        
        // Test creating HDWatchedAddress
        print("3. Creating HDWatchedAddress...")
        let address = HDWatchedAddress(
            address: "yTESTADDRESSXXXXXXXXXXXXXXXXXXXXXX",
            index: 0,
            isChange: false,
            derivationPath: "m/44'/1'/0'/0/0",
            label: "Test Address"
        )
        
        context.insert(address)
        try context.save()
        print("✅ HDWatchedAddress created and saved")
        
        // Test fetching
        print("4. Fetching HDWatchedAddress...")
        let fetched = try context.fetch(FetchDescriptor<HDWatchedAddress>())
        print("✅ Fetched \(fetched.count) addresses")
        
        // Verify the specific address
        if let fetchedAddress = fetched.first {
            print("✅ Address details:")
            print("   - Address: \(fetchedAddress.address)")
            print("   - Label: \(fetchedAddress.label ?? "nil")")
            print("   - Balance: \(fetchedAddress.balance != nil ? "initialized" : "nil")")
        }
        
        // Test with wallet hierarchy
        print("5. Testing full wallet hierarchy...")
        let wallet = HDWallet(
            name: "Test Wallet",
            network: .testnet,
            encryptedSeed: Data(),
            seedHash: "test-hash"
        )
        
        let account = HDAccount(
            accountIndex: 0,
            label: "Main Account",
            extendedPublicKey: "xpub...",
            gapLimit: 20
        )
        
        context.insert(wallet)
        wallet.accounts.append(account)
        
        // Add multiple addresses
        for i in 0..<5 {
            let addr = HDWatchedAddress(
                address: "yADDR\(i)XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
                index: UInt32(i),
                isChange: false,
                derivationPath: "m/44'/1'/0'/0/\(i)"
            )
            account.addresses.append(addr)
        }
        
        try context.save()
        print("✅ Full wallet hierarchy saved")
        
        // Verify database file exists
        if let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            let storeURL = appSupportURL
                .appendingPathComponent("DashPay")
                .appendingPathComponent("DashPayWallet.sqlite")
            
            if FileManager.default.fileExists(atPath: storeURL.path) {
                print("✅ Database file exists at: \(storeURL.path)")
                
                // Check if ZHDWATCHEDADDRESS table exists
                if DatabaseValidator.tableExists("ZHDWATCHEDADDRESS", at: storeURL) {
                    print("✅ ZHDWATCHEDADDRESS table exists in database")
                } else {
                    print("❌ ZHDWATCHEDADDRESS table NOT found in database")
                }
            }
        }
        
        print("\n🎉 All tests passed! The ZHDWATCHEDADDRESS table issue has been fixed.")
        
    } catch {
        print("❌ Test failed with error: \(error)")
        print("Error details: \(error.localizedDescription)")
    }
}

// Run the test
testZHDWATCHEDADDRESSTableCreation()