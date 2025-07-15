import Foundation
import SwiftData
import SwiftDashCoreSDK
import os.log

/// Service responsible for address management (generation, discovery, watching)
@MainActor
class AddressManagementService: ObservableObject {
    private let logger = Logger(subsystem: "com.dash.wallet", category: "AddressManagementService")
    private weak var modelContext: ModelContext?
    
    /// Configure the service with model context
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        logger.info("🔧 AddressManagementService configured with modelContext")
    }
    
    /// Discover addresses for an account
    func discoverAddresses(for account: HDAccount, sdk: DashSDK) async throws {
        guard let wallet = account.wallet else {
            throw WalletError.invalidState
        }
        
        logger.info("🔍 Starting address discovery for account: \(account.displayName)")
        
        // Use the AddressDiscoveryService for proper gap limit discovery
        let discoveryService = AddressDiscoveryService(sdk: sdk)
        
        let (externalAddresses, internalAddresses) = try await discoveryService.discoverAddresses(
            for: account,
            network: wallet.network,
            gapLimit: account.gapLimit
        )
        
        logger.info("✅ Discovered \(externalAddresses.count) external and \(internalAddresses.count) internal addresses")
        
        // Save discovered addresses
        try await saveDiscoveredAddresses(
            account: account,
            external: externalAddresses,
            internal: internalAddresses
        )
        
        logger.info("✅ Address discovery completed for account: \(account.displayName)")
    }
    
    /// Generate addresses with gap limit checking
    func generateAddressesWithGapLimit(for account: HDAccount, sdk: DashSDK) async throws {
        guard let wallet = account.wallet else {
            throw WalletError.invalidState
        }
        
        logger.info("🏗️ Generating addresses with gap limit for account: \(account.displayName)")
        
        // Generate addresses up to gap limit
        let gapLimit = account.gapLimit
        
        // Generate receive addresses
        try await generateReceiveAddresses(
            for: account,
            wallet: wallet,
            gapLimit: gapLimit,
            sdk: sdk
        )
        
        // Generate change addresses
        try await generateChangeAddresses(
            for: account,
            wallet: wallet,
            gapLimit: gapLimit,
            sdk: sdk
        )
        
        do {
            try modelContext?.save()
            logger.info("✅ Address generation completed")
        } catch {
            logger.error("❌ Failed to save addresses to model context: \(error)")
            throw error
        }
    }
    
    /// Generate a new address for an account
    func generateNewAddress(for account: HDAccount, isChange: Bool = false) throws -> HDWatchedAddress {
        guard let wallet = account.wallet, let context = modelContext else {
            throw WalletError.noContext
        }
        
        logger.info("🏗️ Generating new \(isChange ? "change" : "receive") address")
        
        let index = isChange ? account.lastUsedInternalIndex + 1 : account.lastUsedExternalIndex + 1
        
        // Move heavy cryptographic operations to background
        let addressResult = try performAddressGeneration(
            xpub: account.extendedPublicKey,
            network: wallet.network,
            accountIndex: account.accountIndex,
            change: isChange,
            index: index
        )
        
        let watchedAddress = HDWatchedAddress(
            address: addressResult.address,
            index: index,
            isChange: isChange,
            derivationPath: addressResult.path,
            label: isChange ? "Change" : "Receive"
        )
        watchedAddress.account = account
        
        account.addresses.append(watchedAddress)
        
        if isChange {
            account.lastUsedInternalIndex = index
        } else {
            account.lastUsedExternalIndex = index
        }
        
        try context.save()
        
        logger.info("✅ New address generated: \(addressResult.address)")
        return watchedAddress
    }
    
    /// Watch address in SDK with proper error handling
    func watchAddress(_ address: String, label: String, sdk: DashSDK) async {
        do {
            try await sdk.watchAddress(address, label: label)
            logger.info("✅ Successfully watching address: \(address)")
        } catch {
            logger.error("❌ Failed to watch address \(address): \(error)")
        }
    }
    
    /// Watch all addresses for an account
    func watchAccountAddresses(_ account: HDAccount, sdk: DashSDK) async -> [(address: String, error: Error)] {
        logger.info("👀 Watching \(account.addresses.count) addresses for account: \(account.displayName)")
        
        var failedAddresses: [(address: String, error: Error)] = []
        
        for address in account.addresses {
            do {
                try await sdk.watchAddress(address.address, label: address.label)
                logger.info("✅ Successfully watching address: \(address.address)")
            } catch {
                logger.error("❌ Failed to watch address \(address.address): \(error)")
                failedAddresses.append((address.address, error))
            }
        }
        
        logger.info("📊 Address watching complete - \(failedAddresses.count) failures")
        return failedAddresses
    }
    
    // MARK: - Private Helper Methods
    
    private func generateReceiveAddresses(
        for account: HDAccount,
        wallet: HDWallet,
        gapLimit: UInt32,
        sdk: DashSDK
    ) async throws {
        var consecutiveUnused: UInt32 = 0
        var currentIndex = account.lastUsedExternalIndex + 1
        
        while consecutiveUnused < gapLimit && currentIndex < 1000 {
            let address = try HDWalletService.deriveAddress(
                xpub: account.extendedPublicKey,
                network: wallet.network,
                change: false,
                index: currentIndex
            )
            
            // Check if address has been used
            let balance = try await sdk.getBalance(for: address)
            let isUsed = balance.total > 0
            
            if isUsed {
                consecutiveUnused = 0
                account.lastUsedExternalIndex = currentIndex
            } else {
                consecutiveUnused += 1
            }
            
            // Create watched address
            let path = HDWalletService.BIP44.derivationPath(
                network: wallet.network,
                account: account.accountIndex,
                change: false,
                index: currentIndex
            )
            
            let watchedAddress = HDWatchedAddress(
                address: address,
                index: currentIndex,
                isChange: false,
                derivationPath: path,
                label: "Receive"
            )
            watchedAddress.account = account
            account.addresses.append(watchedAddress)
            
            // Watch the address
            try await sdk.watchAddress(address)
            
            currentIndex += 1
        }
    }
    
    private func generateChangeAddresses(
        for account: HDAccount,
        wallet: HDWallet,
        gapLimit: UInt32,
        sdk: DashSDK
    ) async throws {
        var consecutiveUnused: UInt32 = 0
        var currentIndex = account.lastUsedInternalIndex + 1
        let changeGapLimit = min(gapLimit, 5) // Limit change addresses
        
        while consecutiveUnused < changeGapLimit && currentIndex < 100 {
            let address = try HDWalletService.deriveAddress(
                xpub: account.extendedPublicKey,
                network: wallet.network,
                change: true,
                index: currentIndex
            )
            
            // Check if address has been used
            let balance = try await sdk.getBalance(for: address)
            let isUsed = balance.total > 0
            
            if isUsed {
                consecutiveUnused = 0
                account.lastUsedInternalIndex = currentIndex
            } else {
                consecutiveUnused += 1
            }
            
            // Create watched address
            let path = HDWalletService.BIP44.derivationPath(
                network: wallet.network,
                account: account.accountIndex,
                change: true,
                index: currentIndex
            )
            
            let watchedAddress = HDWatchedAddress(
                address: address,
                index: currentIndex,
                isChange: true,
                derivationPath: path,
                label: "Change"
            )
            watchedAddress.account = account
            account.addresses.append(watchedAddress)
            
            // Watch the address
            try await sdk.watchAddress(address)
            
            currentIndex += 1
        }
    }
    
    /// Helper method to perform heavy cryptographic operations in a non-isolated context
    nonisolated private func performAddressGeneration(
        xpub: String,
        network: DashNetwork,
        accountIndex: UInt32,
        change: Bool,
        index: UInt32
    ) throws -> (address: String, path: String) {
        // Perform heavy cryptographic operations outside of MainActor
        let address = try HDWalletService.deriveAddress(
            xpub: xpub,
            network: network,
            change: change,
            index: index
        )
        
        let path = HDWalletService.BIP44.derivationPath(
            network: network,
            account: accountIndex,
            change: change,
            index: index
        )
        
        return (address: address, path: path)
    }
    
    private func saveDiscoveredAddresses(
        account: HDAccount,
        external: [String],
        internal: [String]
    ) async throws {
        guard let wallet = account.wallet, let context = modelContext else {
            throw WalletError.noContext
        }
        
        // Save external addresses
        for (index, address) in external.enumerated() {
            let path = HDWalletService.BIP44.derivationPath(
                network: wallet.network,
                account: account.accountIndex,
                change: false,
                index: UInt32(index)
            )
            
            let watchedAddress = HDWatchedAddress(
                address: address,
                index: UInt32(index),
                isChange: false,
                derivationPath: path,
                label: "Receive"
            )
            watchedAddress.account = account
            
            account.addresses.append(watchedAddress)
        }
        
        // Save internal addresses
        for (index, address) in `internal`.enumerated() {
            let path = HDWalletService.BIP44.derivationPath(
                network: wallet.network,
                account: account.accountIndex,
                change: true,
                index: UInt32(index)
            )
            
            let watchedAddress = HDWatchedAddress(
                address: address,
                index: UInt32(index),
                isChange: true,
                derivationPath: path,
                label: "Change"
            )
            watchedAddress.account = account
            
            account.addresses.append(watchedAddress)
        }
        
        try context.save()
    }
}