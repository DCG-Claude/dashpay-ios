import SwiftUI

// MARK: - View Extensions
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

struct TokensView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedToken: TokenModel?
    @State private var selectedIdentity: IdentityModel?
    
    var body: some View {
        NavigationView {
            VStack {
                if appState.identities.isEmpty {
                    EmptyStateView(
                        systemImage: "person.3",
                        title: "No Identities",
                        message: "Add identities in the Identities tab to use tokens"
                    )
                } else {
                    List {
                        Section(header: Text("Select Identity")) {
                            Picker("Identity", selection: $selectedIdentity) {
                                Text("Select an identity").tag(nil as IdentityModel?)
                                ForEach(appState.identities) { identity in
                                    Text(identity.alias ?? identity.idString)
                                        .tag(identity as IdentityModel?)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        
                        if selectedIdentity != nil {
                            Section(header: Text("Available Tokens")) {
                                ForEach(appState.tokens) { token in
                                    TokenRow(token: token) {
                                        selectedToken = token
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tokens")
            .sheet(item: $selectedToken) { token in
                TokenActionsView(token: token, selectedIdentity: selectedIdentity)
                    .environmentObject(appState)
            }
            .onAppear {
                // Load real token data when view appears
                Task {
                    await appState.loadTokensForIdentities()
                }
            }
        }
    }
    
    // Removed sample token loading - now using real data from TokenService
}

struct TokenRow: View {
    let token: TokenModel
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(token.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(token.displaySymbol)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Balance: \(token.formattedBalance)")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    
                    if token.frozenBalance > 0 {
                        Text("(\(token.formattedFrozenBalance) frozen)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                HStack {
                    Text("Total Supply: \(token.formattedTotalSupply)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !token.availableClaims.isEmpty {
                        Spacer()
                        Label("\(token.availableClaims.count)", systemImage: "gift")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct TokenActionsView: View {
    let token: TokenModel
    let selectedIdentity: IdentityModel?
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var selectedAction: TokenAction?
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Token Information")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Name:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(token.displayName)
                                .font(.subheadline)
                        }
                        HStack {
                            Text("Symbol:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(token.displaySymbol)
                                .font(.subheadline)
                        }
                        HStack {
                            Text("Balance:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(token.formattedBalance)
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Section(header: Text("Actions")) {
                    ForEach(TokenAction.allCases, id: \.self) { action in
                        Button(action: {
                            if action.isEnabled {
                                selectedAction = action
                            }
                        }) {
                            HStack {
                                Image(systemName: action.systemImage)
                                    .frame(width: 24)
                                    .foregroundColor(action.isEnabled ? .blue : .gray)
                                
                                VStack(alignment: .leading) {
                                    Text(action.rawValue)
                                        .foregroundColor(action.isEnabled ? .primary : .gray)
                                    Text(action.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(!action.isEnabled)
                    }
                }
            }
            .navigationTitle(token.name ?? "Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedAction) { action in
                TokenActionDetailView(
                    token: token,
                    action: action,
                    selectedIdentity: selectedIdentity
                )
                .environmentObject(appState)
            }
        }
    }
}

struct TokenActionDetailView: View {
    let token: TokenModel
    let action: TokenAction
    let selectedIdentity: IdentityModel?
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var isProcessing = false
    @State private var recipientId = ""
    @State private var amount = ""
    @State private var tokenNote = ""
    
    var body: some View {
        NavigationView {
            Form {
                identitySection
                actionSection
                executeSection
            }
            .navigationTitle(action.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var identitySection: some View {
        Section(header: Text("Selected Identity")) {
            if let identity = selectedIdentity {
                VStack(alignment: .leading) {
                    Text(identity.alias ?? "Identity")
                        .font(.headline)
                    Text(identity.idString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Balance: \(identity.formattedBalance)")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
        }
    }
    
    @ViewBuilder
    private var actionSection: some View {
        switch action {
        case .transfer:
            Section(header: Text("Transfer Details")) {
                TextField("Recipient Identity ID", text: $recipientId)
                    .textContentType(.none)
                    .autocapitalization(.none)
                
                TextField("Amount", text: $amount)
                    .keyboardType(.numberPad)
                
                TextField("Note (Optional)", text: $tokenNote)
            }
            
        case .mint:
            Section(header: Text("Mint Details")) {
                TextField("Amount", text: $amount)
                    .keyboardType(.numberPad)
                
                TextField("Recipient Identity ID (Optional)", text: $recipientId)
                    .textContentType(.none)
                    .autocapitalization(.none)
            }
            
        case .burn:
            Section(header: Text("Burn Details")) {
                TextField("Amount", text: $amount)
                    .keyboardType(.numberPad)
                
                Text("Warning: This action is irreversible")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
        case .claim:
            Section(header: Text("Claim Details")) {
                if token.availableClaims.isEmpty {
                    Text("No claims available at this time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available claims:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(token.availableClaims, id: \.name) { claim in
                            HStack {
                                Text(claim.name)
                                Spacer()
                                let decimals = token.decimals ?? 8
                                let divisor = pow(10.0, Double(decimals))
                                let claimAmount = Double(claim.amount) / divisor
                                Text(String(format: "%.\(decimals)f %@", claimAmount, token.symbol ?? ""))
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 4)
                        
                        Text("All available claims will be processed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
        case .freeze:
            Section(header: Text("Freeze Details")) {
                TextField("Amount to Freeze", text: $amount)
                    .keyboardType(.numberPad)
                
                TextField("Reason (Optional)", text: $tokenNote)
                
                Text("Frozen tokens cannot be transferred until unfrozen")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
        case .unfreeze:
            Section(header: Text("Unfreeze Details")) {
                if token.frozenBalance > 0 {
                    Text("Frozen Balance: \(token.formattedFrozenBalance)")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                } else {
                    Text("No frozen tokens available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                TextField("Amount to Unfreeze", text: $amount)
                    .keyboardType(.numberPad)
                    .disabled(token.frozenBalance == 0)
                
                Text("Unfrozen tokens will be available for use immediately")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
        case .destroyFrozenFunds:
            Section(header: Text("Destroy Frozen Funds")) {
                if token.frozenBalance > 0 {
                    Text("Frozen Balance: \(token.formattedFrozenBalance)")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                } else {
                    Text("No frozen tokens available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                TextField("Amount to Destroy", text: $amount)
                    .keyboardType(.numberPad)
                
                Text("⚠️ This action permanently destroys frozen tokens")
                    .font(.caption)
                    .foregroundColor(.red)
                
                TextField("Confirmation Reason", text: $tokenNote)
            }
            
        case .directPurchase:
            Section(header: Text("Direct Purchase")) {
                Text("Price: \(token.pricePerToken, specifier: "%.6f") DASH per \(token.symbol ?? "token")")
                    .font(.subheadline)
                
                TextField("Amount to Purchase", text: $amount)
                    .keyboardType(.numberPad)
                
                if let purchaseAmount = Double(amount) {
                    let totalCost = purchaseAmount * token.pricePerToken
                    Text("Total Cost: \(totalCost, specifier: "%.6f") DASH")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                if let identity = selectedIdentity {
                    Text("Available Balance: \(identity.formattedBalance)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("Purchase will be deducted from your identity balance")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var executeSection: some View {
        Section {
            Button(action: {
                Task {
                    isProcessing = true
                    await performTokenAction()
                    isProcessing = false
                    dismiss()
                }
            }) {
                HStack {
                    Spacer()
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Execute \(action.rawValue)")
                    }
                    Spacer()
                }
            }
            .disabled(isProcessing || !isActionValid)
        }
    }
    
    private var isActionValid: Bool {
        switch action {
        case .transfer:
            return !recipientId.isEmpty && !amount.isEmpty
        case .mint:
            return !amount.isEmpty
        case .burn, .freeze, .unfreeze, .directPurchase:
            return !amount.isEmpty
        case .destroyFrozenFunds:
            return !amount.isEmpty && !tokenNote.isEmpty
        case .claim:
            return true // Claims don't require input
        }
    }
    
    private func performTokenAction() async {
        guard let tokenService = appState.tokenService,
              let platformSdk = appState.platformSDK,
              let signer = appState.platformSigner,
              let identity = selectedIdentity else {
            appState.showError(message: "Please select an identity or ensure SDK is initialized")
            return
        }
        
        // Create SDK wrapper for TokenService
        let sdkHandle = await platformSdk.sdkHandle
        let sdk = SimpleSDK(handle: sdkHandle)
        
        do {
            let resultMessage: String
            
            switch action {
            case .transfer:
                guard !recipientId.isEmpty else {
                    throw TokenError.invalidRecipient
                }
                
                guard let transferAmount = UInt64(amount) else {
                    throw TokenError.invalidAmount
                }
                
                let _ = try await tokenService.transferTokens(
                    sdk: sdk,
                    signer: signer,
                    fromIdentity: identity,
                    tokenContractId: token.contractId,
                    tokenPosition: token.tokenPosition,
                    recipientId: recipientId,
                    amount: transferAmount,
                    publicNote: tokenNote.isEmpty ? nil : tokenNote
                )
                
                resultMessage = "Transfer of \(transferAmount) \(token.displaySymbol) tokens initiated successfully"
                
            case .mint:
                guard let mintAmount = UInt64(amount) else {
                    throw TokenError.invalidAmount
                }
                
                let _ = try await tokenService.mintTokens(
                    sdk: sdk,
                    signer: signer,
                    ownerIdentity: identity,
                    tokenContractId: token.contractId,
                    tokenPosition: token.tokenPosition,
                    recipientId: recipientId.isEmpty ? nil : recipientId,
                    amount: mintAmount,
                    publicNote: tokenNote.isEmpty ? nil : tokenNote
                )
                
                resultMessage = "Minted \(mintAmount) \(token.displaySymbol) tokens successfully"
                
            case .burn:
                guard let burnAmount = UInt64(amount) else {
                    throw TokenError.invalidAmount
                }
                
                let _ = try await tokenService.burnTokens(
                    sdk: sdk,
                    signer: signer,
                    ownerIdentity: identity,
                    tokenContractId: token.contractId,
                    tokenPosition: token.tokenPosition,
                    amount: burnAmount,
                    publicNote: tokenNote.isEmpty ? nil : tokenNote
                )
                
                resultMessage = "Burned \(burnAmount) \(token.displaySymbol) tokens successfully"
                
            case .claim:
                let _ = try await tokenService.claimTokens(
                    sdk: sdk,
                    signer: signer,
                    claimerIdentity: identity,
                    tokenContractId: token.contractId,
                    tokenPosition: token.tokenPosition,
                    // distributionType: DashSDKTokenDistributionType(rawValue: 0),
                    publicNote: tokenNote.isEmpty ? nil : tokenNote
                )
                
                resultMessage = "Claimed available \(token.displaySymbol) tokens from distribution"
                
            case .freeze:
                guard let freezeAmount = UInt64(amount) else {
                    throw TokenError.invalidAmount
                }
                
                let targetId = recipientId.isEmpty ? identity.idString : recipientId
                let _ = try await tokenService.freezeTokens(
                    sdk: sdk,
                    signer: signer,
                    authorizedIdentity: identity,
                    tokenContractId: token.contractId,
                    tokenPosition: token.tokenPosition,
                    targetIdentityId: targetId,
                    publicNote: tokenNote.isEmpty ? nil : tokenNote
                )
                
                let reason = tokenNote.isEmpty ? "No reason provided" : tokenNote
                resultMessage = "Froze tokens for target identity. Reason: \(reason)"
                
            case .unfreeze:
                guard let unfreezeAmount = UInt64(amount) else {
                    throw TokenError.invalidAmount
                }
                
                let targetId = recipientId.isEmpty ? identity.idString : recipientId
                let _ = try await tokenService.unfreezeTokens(
                    sdk: sdk,
                    signer: signer,
                    authorizedIdentity: identity,
                    tokenContractId: token.contractId,
                    tokenPosition: token.tokenPosition,
                    targetIdentityId: targetId,
                    publicNote: tokenNote.isEmpty ? nil : tokenNote
                )
                
                resultMessage = "Unfroze tokens for target identity"
                
            case .destroyFrozenFunds:
                guard let destroyAmount = UInt64(amount) else {
                    throw TokenError.invalidAmount
                }
                
                guard !tokenNote.isEmpty else {
                    throw TokenError.missingReason
                }
                
                let targetId = recipientId.isEmpty ? identity.idString : recipientId
                let _ = try await tokenService.destroyFrozenFunds(
                    sdk: sdk,
                    signer: signer,
                    authorizedIdentity: identity,
                    tokenContractId: token.contractId,
                    tokenPosition: token.tokenPosition,
                    frozenIdentityId: targetId,
                    publicNote: tokenNote
                )
                
                resultMessage = "Destroyed frozen funds. Reason: \(tokenNote)"
                
            case .directPurchase:
                guard let purchaseAmount = UInt64(amount) else {
                    throw TokenError.invalidAmount
                }
                
                // Calculate total cost based on token price info
                let effectivePrice = token.priceInfo?.effectivePrice ?? 1000000 // Default 1M credits per token
                let totalCost = UInt64(Double(purchaseAmount) * Double(effectivePrice))
                
                let _ = try await tokenService.purchaseTokens(
                    sdk: sdk,
                    signer: signer,
                    buyerIdentity: identity,
                    tokenContractId: token.contractId,
                    tokenPosition: token.tokenPosition,
                    amount: purchaseAmount,
                    totalAgreedPrice: totalCost
                )
                
                resultMessage = "Purchased \(purchaseAmount) \(token.displaySymbol) tokens for \(totalCost) credits"
            }
            
            // Show success message
            appState.showError(message: resultMessage)
            
            // Refresh token data after successful operation
            await appState.refreshTokensForIdentity(identity)
            
        } catch {
            appState.showError(message: "Failed to perform \(action.rawValue): \(error.localizedDescription)")
        }
    }
}

enum TokenError: LocalizedError {
    case invalidRecipient
    case invalidAmount
    case missingReason
    
    var errorDescription: String? {
        switch self {
        case .invalidRecipient:
            return "Please enter a valid recipient ID"
        case .invalidAmount:
            return "Please enter a valid amount"
        case .missingReason:
            return "Please provide a reason for this action"
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}