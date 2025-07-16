import Foundation
import SwiftData
import SwiftDashCoreSDK
import os.log

/// Service responsible for wallet lifecycle management (creation, deletion, account management)
@MainActor
class WalletLifecycleService: ObservableObject {
    private let logger = Logger(subsystem: "com.dash.wallet", category: "WalletLifecycleService")
    private weak var modelContext: ModelContext?
    
    /// Configure the service with model context
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        logger.info("🔧 WalletLifecycleService configured with modelContext")
    }
    
    /// Create a new wallet with the given parameters
    func createWallet(
        name: String,
        mnemonic: [String],
        password: String,
        network: DashNetwork
    ) async throws -> HDWallet {
        guard let context = modelContext else {
            throw WalletError.noContext
        }
        
        logger.info("🏗️ Creating new wallet: \(name)")
        
        // Generate seed from mnemonic
        let seed = try HDWalletService.mnemonicToSeed(mnemonic)
        let seedHash = HDWalletService.seedHash(seed)
        
        // Check for duplicate wallet
        let descriptor = FetchDescriptor<HDWallet>()
        let allWallets = try context.fetch(descriptor)
        if allWallets.first(where: { $0.seedHash == seedHash && $0.network == network }) != nil {
            throw WalletError.duplicateWallet
        }
        
        // Encrypt seed
        let encryptedSeed = try HDWalletService.encryptSeed(seed, password: password)
        
        // Create wallet
        let wallet = HDWallet(
            name: name,
            network: network,
            encryptedSeed: encryptedSeed,
            seedHash: seedHash
        )
        
        context.insert(wallet)
        
        // Create default account
        let account = try await createAccount(
            for: wallet,
            index: 0,
            label: "Primary Account",
            password: password
        )
        wallet.accounts.append(account)
        
        try context.save()
        
        logger.info("✅ Wallet created successfully: \(name)")
        return wallet
    }
    
    /// Create a new account for a wallet
    func createAccount(
        for wallet: HDWallet,
        index: UInt32,
        label: String,
        password: String
    ) async throws -> HDAccount {
        logger.info("🏗️ Creating account for wallet: \(wallet.name)")
        
        // Move heavy cryptographic operations to background
        let accountData = try performAccountCreation(
            encryptedSeed: wallet.encryptedSeed,
            password: password,
            network: wallet.network,
            accountIndex: index
        )
        
        // Create account
        let account = HDAccount(
            accountIndex: index,
            label: label,
            extendedPublicKey: accountData.xpub,
            wallet: wallet
        )
        
        // Generate initial addresses using the background-generated data
        for addressData in accountData.addresses {
            let watchedAddress = HDWatchedAddress(
                address: addressData.address,
                index: addressData.index,
                isChange: addressData.isChange,
                derivationPath: addressData.path,
                label: addressData.label
            )
            watchedAddress.account = account
            account.addresses.append(watchedAddress)
        }
        
        logger.info("✅ Account created successfully: \(label)")
        return account
    }
    
    /// Delete a wallet and all associated data
    func deleteWallet(_ wallet: HDWallet) throws {
        guard let context = modelContext else {
            throw WalletError.noContext
        }
        
        logger.info("🗑️ Deleting wallet: \(wallet.name)")
        
        context.delete(wallet)
        try context.save()
        
        logger.info("✅ Wallet deleted successfully")
    }
    
    /// Helper method to perform heavy cryptographic operations for account creation
    nonisolated private func performAccountCreation(
        encryptedSeed: Data,
        password: String,
        network: DashNetwork,
        accountIndex: UInt32
    ) throws -> (xpub: String, addresses: [(address: String, index: UInt32, isChange: Bool, path: String, label: String)]) {
        // Decrypt seed
        let seed = try HDWalletService.decryptSeed(encryptedSeed, password: password)
        
        // Derive account xpub
        let xpub = try HDWalletService.deriveExtendedPublicKey(
            seed: seed,
            network: network,
            account: accountIndex
        )
        
        // Generate initial addresses (5 receive, 1 change)
        let initialReceiveCount = 5
        let initialChangeCount = 1
        var addresses: [(address: String, index: UInt32, isChange: Bool, path: String, label: String)] = []
        
        // Generate receive addresses
        for i in 0..<initialReceiveCount {
            let address = try HDWalletService.deriveAddress(
                xpub: xpub,
                network: network,
                change: false,
                index: UInt32(i)
            )
            
            let path = HDWalletService.BIP44.derivationPath(
                network: network,
                account: accountIndex,
                change: false,
                index: UInt32(i)
            )
            
            addresses.append((
                address: address,
                index: UInt32(i),
                isChange: false,
                path: path,
                label: "Receive"
            ))
        }
        
        // Generate change address
        for i in 0..<initialChangeCount {
            let address = try HDWalletService.deriveAddress(
                xpub: xpub,
                network: network,
                change: true,
                index: UInt32(i)
            )
            
            let path = HDWalletService.BIP44.derivationPath(
                network: network,
                account: accountIndex,
                change: true,
                index: UInt32(i)
            )
            
            addresses.append((
                address: address,
                index: UInt32(i),
                isChange: true,
                path: path,
                label: "Change"
            ))
        }
        
        return (xpub: xpub, addresses: addresses)
    }
}