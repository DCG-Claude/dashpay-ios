import Foundation
import SwiftDashSDK
import SwiftDashCoreSDK

// MARK: - Address Discovery Service

class AddressDiscoveryService {
    private let sdk: DashSDK
    
    init(sdk: DashSDK) {
        self.sdk = sdk
    }
    
    func discoverAddresses(
        for account: HDAccount,
        network: DashNetwork,
        gapLimit: UInt32 = 20
    ) async throws -> (external: [String], internal: [String]) {
        var externalAddresses: [String] = []
        var internalAddresses: [String] = []
        
        // Discover external addresses
        let (lastExternal, discoveredExternal) = try await discoverChain(
            xpub: account.extendedPublicKey,
            network: network,
            change: false,
            gapLimit: gapLimit
        )
        externalAddresses = discoveredExternal
        
        // Discover internal (change) addresses
        let (lastInternal, discoveredInternal) = try await discoverChain(
            xpub: account.extendedPublicKey,
            network: network,
            change: true,
            gapLimit: gapLimit
        )
        internalAddresses = discoveredInternal
        
        // Update account indices
        account.lastUsedExternalIndex = UInt32(max(0, lastExternal - 1))
        account.lastUsedInternalIndex = UInt32(max(0, lastInternal - 1))
        
        return (external: externalAddresses, internal: internalAddresses)
    }
    
    private func discoverChain(
        xpub: String,
        network: DashNetwork,
        change: Bool,
        gapLimit: UInt32
    ) async throws -> (lastIndex: UInt32, addresses: [String]) {
        var addresses: [String] = []
        var consecutiveUnused: UInt32 = 0
        var currentIndex: UInt32 = 0
        
        while consecutiveUnused < gapLimit {
            // Generate batch of addresses
            let batchSize: UInt32 = min(10, gapLimit)
            
            guard !xpub.contains("Mock") else {
                print("🔴 Cannot discover addresses with mock xpub: \(xpub)")
                throw WalletError.derivationFailed
            }
            
            let batchAddresses = try HDWalletService.deriveAddresses(
                xpub: xpub,
                network: network,
                change: change,
                startIndex: currentIndex,
                count: batchSize
            )
            
            // Check each address
            var foundUsed = false
            for (offset, address) in batchAddresses.enumerated() {
                // Validate address before using it
                guard HDWalletService.isValidAddress(address, network: network) else {
                    print("🔴 Skipping invalid address: \(address)")
                    continue
                }
                
                let balance = try await sdk.getBalance(for: address)
                let transactions = try await sdk.getTransactions(for: address)
                
                // Check if address has been used (has balance or transactions)
                let isUsed = balance.total > 0 || balance.confirmed > 0 || balance.pending > 0 || !transactions.isEmpty
                
                if isUsed {
                    foundUsed = true
                    consecutiveUnused = 0
                    addresses.append(address)
                    
                    // Watch the address - only if it's valid
                    do {
                        // TODO: Implement address watching when SDK API is available
                        // try await sdk.addWatchItem(type: .address, data: address)
                        print("⚠️ Address watching not yet implemented: \(address)")
                    } catch {
                        print("🔴 Failed to watch address \(address): \(error)")
                    }
                } else {
                    consecutiveUnused += 1
                    if consecutiveUnused < gapLimit {
                        addresses.append(address)
                    }
                }
                
                if consecutiveUnused >= gapLimit {
                    break
                }
            }
            
            currentIndex += batchSize
            
            // Stop if we've checked enough addresses
            if currentIndex > 1000 {
                break
            }
        }
        
        // Return the last index that was checked
        let lastCheckedIndex = currentIndex - consecutiveUnused
        return (lastCheckedIndex, addresses)
    }
}