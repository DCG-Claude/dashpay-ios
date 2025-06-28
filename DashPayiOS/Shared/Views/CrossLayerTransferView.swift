import SwiftUI

struct CrossLayerTransferView: View {
    @EnvironmentObject var unifiedState: UnifiedStateManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var transferType: TransferType = .coreToIdentity
    @State private var sourceWallet: Wallet?
    @State private var sourceIdentity: Identity?
    @State private var targetIdentityId: String = ""
    @State private var targetCoreAddress: String = ""
    @State private var amount: String = ""
    @State private var useBackupFunding = false
    
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var successMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                // Transfer Type Selection
                Section("Transfer Type") {
                    Picker("Transfer Type", selection: $transferType) {
                        ForEach(TransferType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Source Selection
                Section(transferType.sourceTitle) {
                    switch transferType {
                    case .coreToIdentity, .coreToNewIdentity:
                        WalletSelectionView(selectedWallet: $sourceWallet, wallets: unifiedState.wallets)
                        
                    case .identityToCore, .identityToIdentity:
                        IdentitySelectionView(selectedIdentity: $sourceIdentity, identities: unifiedState.identities)
                    }
                }
                
                // Target Selection
                Section(transferType.targetTitle) {
                    switch transferType {
                    case .coreToIdentity, .identityToIdentity:
                        HStack {
                            TextField("Identity ID", text: $targetIdentityId)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("Scan") {
                                // QR code scanning would be implemented here
                                // For now, show a placeholder message
                                appState.showError(message: "QR scanning feature coming soon")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                    case .identityToCore:
                        HStack {
                            TextField("DASH Address", text: $targetCoreAddress)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("Scan") {
                                // QR code scanning would be implemented here
                                // For now, show a placeholder message
                                appState.showError(message: "QR scanning feature coming soon")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                    case .coreToNewIdentity:
                        Text("New identity will be created")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Amount Section
                Section("Amount") {
                    HStack {
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                        
                        Text(transferType.amountUnit)
                            .foregroundColor(.secondary)
                    }
                    
                    if transferType.showUSDEstimate {
                        Text(estimatedUSDValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Options Section
                if transferType.supportsBackupFunding {
                    Section("Options") {
                        Toggle("Use backup funding if needed", isOn: $useBackupFunding)
                        
                        if useBackupFunding {
                            Text("Will automatically fund from Core wallet if Platform balance is insufficient")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Balance Information
                Section("Available Balance") {
                    BalanceInfoView(transferType: transferType, 
                                  sourceWallet: sourceWallet, 
                                  sourceIdentity: sourceIdentity,
                                  unifiedState: unifiedState)
                }
                
                // Action Section
                Section {
                    Button(action: performTransfer) {
                        if isProcessing {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Processing...")
                            }
                        } else {
                            Text(transferType.actionTitle)
                        }
                    }
                    .disabled(isProcessing || !canPerformTransfer)
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Cross-Layer Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { showError = false }
            } message: {
                Text(errorMessage)
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK") {
                    showSuccess = false
                    dismiss()
                }
            } message: {
                Text(successMessage)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private var canPerformTransfer: Bool {
        guard !amount.isEmpty,
              let amountValue = Double(amount),
              amountValue > 0 else { return false }
        
        switch transferType {
        case .coreToIdentity, .coreToNewIdentity:
            return sourceWallet != nil
        case .identityToCore:
            return sourceIdentity != nil && !targetCoreAddress.isEmpty
        case .identityToIdentity:
            return sourceIdentity != nil && !targetIdentityId.isEmpty
        }
    }
    
    private var estimatedUSDValue: String {
        guard let amountValue = Double(amount) else { return "$0.00" }
        
        let usdValue: Double
        switch transferType {
        case .coreToIdentity, .coreToNewIdentity, .identityToCore:
            // DASH amount
            usdValue = amountValue * unifiedState.unifiedBalance.priceData.dashPriceUSD
        case .identityToIdentity:
            // Credits - approximate USD value
            usdValue = amountValue * unifiedState.unifiedBalance.priceData.creditToUSDRate
        }
        
        return String(format: "≈ $%.2f", usdValue)
    }
    
    private func performTransfer() {
        guard let amountValue = Double(amount) else { return }
        
        isProcessing = true
        
        Task {
            do {
                switch transferType {
                case .coreToIdentity:
                    try await performCoreToIdentityTransfer(amountValue)
                case .coreToNewIdentity:
                    try await performCoreToNewIdentityTransfer(amountValue)
                case .identityToCore:
                    try await performIdentityToCoreTransfer(amountValue)
                case .identityToIdentity:
                    try await performIdentityToIdentityTransfer(amountValue)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isProcessing = false
                }
            }
        }
    }
    
    private func performCoreToIdentityTransfer(_ amountValue: Double) async throws {
        guard let wallet = sourceWallet else { throw TransferError.invalidSource }
        
        let amountInSatoshis = UInt64(amountValue * 100_000_000)
        
        let result = try await unifiedState.topUpIdentity(
            unifiedState.identities.first { $0.id == targetIdentityId } ?? Identity(id: targetIdentityId, balance: 0, revision: 0),
            from: wallet,
            amount: amountInSatoshis
        )
        
        await MainActor.run {
            successMessage = "Successfully funded identity with \(amountValue) DASH"
            showSuccess = true
            isProcessing = false
        }
    }
    
    private func performCoreToNewIdentityTransfer(_ amountValue: Double) async throws {
        guard let wallet = sourceWallet else { throw TransferError.invalidSource }
        
        let amountInSatoshis = UInt64(amountValue * 100_000_000)
        
        let identity = try await unifiedState.createFundedIdentity(
            from: wallet,
            amount: amountInSatoshis
        )
        
        await MainActor.run {
            successMessage = "Successfully created and funded new identity: \(identity.id)"
            showSuccess = true
            isProcessing = false
        }
    }
    
    private func performIdentityToCoreTransfer(_ amountValue: Double) async throws {
        guard let identity = sourceIdentity else { throw TransferError.invalidSource }
        
        let amountInCredits = UInt64(amountValue)
        
        let result = try await unifiedState.withdrawCreditsToCore(
            from: identity,
            to: targetCoreAddress,
            amount: amountInCredits
        )
        
        await MainActor.run {
            successMessage = "Withdrawal initiated. Transaction ID: \(result.transactionId)"
            showSuccess = true
            isProcessing = false
        }
    }
    
    private func performIdentityToIdentityTransfer(_ amountValue: Double) async throws {
        guard let identity = sourceIdentity else { throw TransferError.invalidSource }
        
        let amountInCredits = UInt64(amountValue)
        
        let result = try await unifiedState.transferBetweenIdentities(
            from: identity,
            to: targetIdentityId,
            amount: amountInCredits,
            useBackupFunding: useBackupFunding,
            backupWallet: sourceWallet
        )
        
        await MainActor.run {
            successMessage = "Successfully transferred \(amountValue) credits"
            showSuccess = true
            isProcessing = false
        }
    }
}

// MARK: - Supporting Views

struct WalletSelectionView: View {
    @Binding var selectedWallet: Wallet?
    let wallets: [Wallet]
    
    var body: some View {
        if wallets.isEmpty {
            Text("No wallets available")
                .foregroundColor(.secondary)
        } else {
            Picker("Select Wallet", selection: $selectedWallet) {
                Text("Select wallet").tag(nil as Wallet?)
                ForEach(wallets, id: \.id) { wallet in
                    VStack(alignment: .leading) {
                        Text(wallet.address)
                            .font(.caption)
                        Text(formatBalance(wallet.balance))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .tag(wallet as Wallet?)
                }
            }
        }
    }
    
    private func formatBalance(_ balance: UInt64) -> String {
        let dash = Double(balance) / 100_000_000
        return String(format: "%.8g DASH", dash)
    }
}

struct IdentitySelectionView: View {
    @Binding var selectedIdentity: Identity?
    let identities: [Identity]
    
    var body: some View {
        if identities.isEmpty {
            Text("No identities available")
                .foregroundColor(.secondary)
        } else {
            Picker("Select Identity", selection: $selectedIdentity) {
                Text("Select identity").tag(nil as Identity?)
                ForEach(identities, id: \.id) { identity in
                    VStack(alignment: .leading) {
                        Text(identity.id.prefix(16) + "...")
                            .font(.caption)
                        Text("\(identity.balance) credits")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .tag(identity as Identity?)
                }
            }
        }
    }
}

struct BalanceInfoView: View {
    let transferType: TransferType
    let sourceWallet: Wallet?
    let sourceIdentity: Identity?
    let unifiedState: UnifiedStateManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch transferType {
            case .coreToIdentity, .coreToNewIdentity:
                if let wallet = sourceWallet {
                    HStack {
                        Text("Core Wallet:")
                        Spacer()
                        Text(formatDashBalance(wallet.balance))
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("USD Value:")
                        Spacer()
                        Text(formatUSDBalance(wallet.balance))
                            .foregroundColor(.secondary)
                    }
                }
                
            case .identityToCore, .identityToIdentity:
                if let identity = sourceIdentity {
                    HStack {
                        Text("Platform Credits:")
                        Spacer()
                        Text("\(identity.balance) credits")
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("USD Value:")
                        Spacer()
                        Text(formatCreditsUSD(identity.balance))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .font(.caption)
    }
    
    private func formatDashBalance(_ balance: UInt64) -> String {
        let dash = Double(balance) / 100_000_000
        return String(format: "%.8g DASH", dash)
    }
    
    private func formatUSDBalance(_ balance: UInt64) -> String {
        let dash = Double(balance) / 100_000_000
        let usd = dash * unifiedState.unifiedBalance.priceData.dashPriceUSD
        return String(format: "$%.2f", usd)
    }
    
    private func formatCreditsUSD(_ credits: UInt64) -> String {
        let usd = Double(credits) * unifiedState.unifiedBalance.priceData.creditToUSDRate
        return String(format: "$%.4f", usd)
    }
}

// MARK: - Models

enum TransferType: CaseIterable {
    case coreToIdentity
    case coreToNewIdentity
    case identityToCore
    case identityToIdentity
    
    var displayName: String {
        switch self {
        case .coreToIdentity:
            return "Core → Identity"
        case .coreToNewIdentity:
            return "Core → New Identity"
        case .identityToCore:
            return "Identity → Core"
        case .identityToIdentity:
            return "Identity → Identity"
        }
    }
    
    var sourceTitle: String {
        switch self {
        case .coreToIdentity, .coreToNewIdentity:
            return "Source Wallet"
        case .identityToCore, .identityToIdentity:
            return "Source Identity"
        }
    }
    
    var targetTitle: String {
        switch self {
        case .coreToIdentity:
            return "Target Identity"
        case .coreToNewIdentity:
            return "New Identity"
        case .identityToCore:
            return "Target Address"
        case .identityToIdentity:
            return "Target Identity"
        }
    }
    
    var amountUnit: String {
        switch self {
        case .coreToIdentity, .coreToNewIdentity, .identityToCore:
            return "DASH"
        case .identityToIdentity:
            return "credits"
        }
    }
    
    var actionTitle: String {
        switch self {
        case .coreToIdentity:
            return "Fund Identity"
        case .coreToNewIdentity:
            return "Create & Fund"
        case .identityToCore:
            return "Withdraw to Core"
        case .identityToIdentity:
            return "Transfer Credits"
        }
    }
    
    var showUSDEstimate: Bool {
        return true
    }
    
    var supportsBackupFunding: Bool {
        return self == .identityToIdentity
    }
}

enum TransferError: LocalizedError {
    case invalidSource
    case invalidTarget
    case invalidAmount
    
    var errorDescription: String? {
        switch self {
        case .invalidSource:
            return "Please select a valid source"
        case .invalidTarget:
            return "Please select a valid target"
        case .invalidAmount:
            return "Please enter a valid amount"
        }
    }
}