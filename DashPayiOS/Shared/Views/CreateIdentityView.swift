import SwiftUI

enum CreateIdentityError: LocalizedError {
    case noWalletAvailable
    
    var errorDescription: String? {
        switch self {
        case .noWalletAvailable:
            return "No wallet available. Please create or import a wallet first."
        }
    }
}

struct CreateIdentityView: View {
    @EnvironmentObject var unifiedState: UnifiedStateManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var fundingAmount: String = "0.01"
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var creationStage: CreationStage = .idle
    @State private var estimatedFee: UInt64 = 0
    @State private var totalCost: UInt64 = 0
    
    enum CreationStage {
        case idle
        case validatingFunds
        case creatingTransaction
        case broadcastingTransaction
        case waitingForInstantLock
        case creatingIdentity
        case completed
        
        var description: String {
            switch self {
            case .idle:
                return "Ready to create identity"
            case .validatingFunds:
                return "Validating wallet balance..."
            case .creatingTransaction:
                return "Creating asset lock transaction..."
            case .broadcastingTransaction:
                return "Broadcasting to network..."
            case .waitingForInstantLock:
                return "Waiting for InstantSend confirmation..."
            case .creatingIdentity:
                return "Creating Platform identity..."
            case .completed:
                return "Identity created successfully!"
            }
        }
        
        var isInProgress: Bool {
            switch self {
            case .idle, .completed:
                return false
            default:
                return true
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Funding Amount Section
                Section("Funding Amount") {
                    HStack {
                        TextField("Amount", text: $fundingAmount)
                            .keyboardType(.decimalPad)
                            .onChange(of: fundingAmount) { newValue in
                                updateEstimatedCosts()
                            }
                        
                        Text("DASH")
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Minimum: 0.001 DASH")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if estimatedFee > 0 {
                            HStack {
                                Text("Estimated fee:")
                                Spacer()
                                Text("\(formatDash(estimatedFee)) DASH")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            
                            HStack {
                                Text("Total cost:")
                                Spacer()
                                Text("\(formatDash(totalCost)) DASH")
                                    .fontWeight(.medium)
                            }
                            .font(.caption)
                            .foregroundColor(.primary)
                        }
                    }
                }
                
                // Info Section
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Creating an identity requires locking DASH on the Core chain. These funds will be converted to Platform credits.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("The process involves:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("• Creating an asset lock transaction")
                            Text("• Broadcasting to Dash network")
                            Text("• Waiting for InstantSend confirmation")
                            Text("• Registering identity on Platform")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        
                        if let platformStatus = unifiedState.platformWrapper {
                            HStack {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 6, height: 6)
                                Text("Platform SDK connected")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Spacer()
                            }
                        } else {
                            HStack {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 6, height: 6)
                                Text("Platform SDK not available")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Spacer()
                            }
                        }
                    }
                }
                
                // Creation Progress Section
                if creationStage.isInProgress {
                    Section("Progress") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(creationStage.description)
                                    .font(.subheadline)
                                Spacer()
                            }
                            
                            // Progress steps
                            CreationProgressView(currentStage: creationStage)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Action Section
                Section {
                    Button(action: createIdentity) {
                        if isCreating {
                            HStack {
                                ProgressView()
                                Text(creationStage.description)
                            }
                        } else {
                            Text("Create Identity")
                        }
                    }
                    .disabled(isCreating || !isValidAmount || !isPlatformAvailable)
                    
                    if !isValidAmount && !fundingAmount.isEmpty {
                        Text("Amount must be at least 0.001 DASH")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    if !isPlatformAvailable {
                        Text("Platform SDK not available. Identity creation requires Platform connectivity.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            .navigationTitle("Create Identity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(creationStage.isInProgress)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {
                    showError = false
                    creationStage = .idle
                }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                updateEstimatedCosts()
            }
        }
    }
    
    private func createIdentity() {
        guard let amount = Decimal(string: fundingAmount),
              amount >= 0.001 else {
            errorMessage = "Invalid funding amount. Minimum is 0.001 DASH"
            showError = true
            return
        }
        
        isCreating = true
        creationStage = .validatingFunds
        
        Task {
            do {
                // Convert DASH to satoshis (1 DASH = 100,000,000 satoshis)
                let amountInSatoshis = UInt64(NSDecimalNumber(decimal: amount * 100_000_000).uint64Value)
                
                // Get the first available wallet
                guard let wallet = unifiedState.wallets.first else {
                    throw CreateIdentityError.noWalletAvailable
                }
                
                // Update stage to creating transaction
                await MainActor.run {
                    creationStage = .creatingTransaction
                }
                
                // Create funded identity using the unified state manager with progress updates
                let identity = try await createIdentityWithProgress(
                    from: wallet,
                    amount: amountInSatoshis
                )
                
                print("✅ Identity created successfully: \(identity.id)")
                
                // Mark as completed
                await MainActor.run {
                    creationStage = .completed
                }
                
                // Wait a moment to show completion, then dismiss
                try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                
                // Dismiss on success
                await MainActor.run {
                    dismiss()
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isCreating = false
                    creationStage = .idle
                }
            }
        }
    }
    
    private func createIdentityWithProgress(
        from wallet: Wallet,
        amount: UInt64
    ) async throws -> Identity {
        // Enhanced identity creation with detailed progress updates
        
        // Update stage to validating funds
        await MainActor.run {
            creationStage = .validatingFunds
        }
        
        // Validate wallet balance
        let estimatedFee = UInt64(250_000) // 0.0025 DASH estimated fee
        let totalRequired = amount + estimatedFee
        
        guard wallet.balance >= totalRequired else {
            throw CreateIdentityError.noWalletAvailable // Reusing existing error for insufficient funds
        }
        
        print("✅ Wallet balance validated: \(wallet.balance) >= \(totalRequired)")
        
        // Update stage to creating transaction
        await MainActor.run {
            creationStage = .creatingTransaction
        }
        
        // Create asset lock transaction using the unified state with real implementation
        let identity = try await unifiedState.createFundedIdentityWithProgress(
            from: wallet,
            amount: amount,
            progressCallback: { stage in
                Task { @MainActor in
                    switch stage {
                    case "broadcasting":
                        self.creationStage = .broadcastingTransaction
                    case "instantlock":
                        self.creationStage = .waitingForInstantLock
                    case "identity":
                        self.creationStage = .creatingIdentity
                    default:
                        break
                    }
                }
            }
        )
        
        return identity
    }
    
    private var isValidAmount: Bool {
        guard let amount = Decimal(string: fundingAmount) else { return false }
        return amount >= 0.001
    }
    
    private var isPlatformAvailable: Bool {
        return unifiedState.platformWrapper != nil && unifiedState.assetLockBridge != nil
    }
    
    private func updateEstimatedCosts() {
        guard let amount = Decimal(string: fundingAmount), amount > 0 else {
            estimatedFee = 0
            totalCost = 0
            return
        }
        
        let amountInSatoshis = UInt64(NSDecimalNumber(decimal: amount * 100_000_000).uint64Value)
        
        // Estimate fee (simplified calculation)
        // In production, this could query the actual wallet for more accurate estimation
        estimatedFee = 250 * 1000 / 1000 // ~250 bytes at 1000 sat/KB = ~250 sats
        totalCost = amountInSatoshis + estimatedFee
    }
    
    private func formatDash(_ satoshis: UInt64) -> String {
        let dash = Double(satoshis) / 100_000_000.0
        return String(format: "%.8f", dash)
    }
}

// MARK: - Creation Progress View

struct CreationProgressView: View {
    let currentStage: CreateIdentityView.CreationStage
    
    private let stages: [CreateIdentityView.CreationStage] = [
        .validatingFunds,
        .creatingTransaction,
        .broadcastingTransaction,
        .waitingForInstantLock,
        .creatingIdentity,
        .completed
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(stages, id: \.self) { stage in
                HStack {
                    Image(systemName: iconForStage(stage))
                        .foregroundColor(colorForStage(stage))
                        .frame(width: 16)
                    
                    Text(stage.description)
                        .font(.caption)
                        .foregroundColor(colorForStage(stage))
                    
                    Spacer()
                    
                    if stage == currentStage && stage.isInProgress {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
            }
        }
    }
    
    private func iconForStage(_ stage: CreateIdentityView.CreationStage) -> String {
        let currentIndex = stages.firstIndex(of: currentStage) ?? 0
        let stageIndex = stages.firstIndex(of: stage) ?? 0
        
        if stageIndex < currentIndex {
            return "checkmark.circle.fill"
        } else if stageIndex == currentIndex {
            return "circle.fill"
        } else {
            return "circle"
        }
    }
    
    private func colorForStage(_ stage: CreateIdentityView.CreationStage) -> Color {
        let currentIndex = stages.firstIndex(of: currentStage) ?? 0
        let stageIndex = stages.firstIndex(of: stage) ?? 0
        
        if stageIndex < currentIndex {
            return .green
        } else if stageIndex == currentIndex {
            return .blue
        } else {
            return .secondary
        }
    }
}

extension CreateIdentityView.CreationStage: Hashable {}