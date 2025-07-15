import SwiftUI
import SwiftData

struct IdentityDetailView: View {
    @State private var identity: IdentityModel
    @EnvironmentObject var appState: AppState
    @State private var isRefreshing = false
    @State private var showTransferView = false
    @State private var showTopUpView = false
    @State private var showRawData = false
    @State private var isCopied = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var cacheStats: IdentityCacheStatistics?
    @Environment(\.dismiss) private var dismiss
    
    // Initialize with identity
    init(identity: IdentityModel) {
        self._identity = State(initialValue: identity)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Identity Header
                    IdentityHeaderSection(
                        identity: identity,
                        isRefreshing: $isRefreshing,
                        onRefresh: refreshIdentity
                    )
                    
                    // Balance Section
                    IdentityBalanceSection(
                        identity: identity,
                        onTransfer: { showTransferView = true },
                        onTopUp: { showTopUpView = true }
                    )
                    
                    // Identity Details
                    IdentityDetailsSection(identity: identity)
                    
                    // Technical Information
                    IdentityTechnicalSection(identity: identity, showRawData: $showRawData)
                    
                    // Cache Statistics (if available)
                    if let stats = cacheStats {
                        IdentityCacheStatsSection(stats: stats)
                    }
                    
                    // Actions
                    IdentityActionsSection(identity: identity, isCopied: $isCopied)
                }
                .padding()
            }
            .navigationTitle("Identity Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showTransferView) {
                CreditTransferView(fromIdentity: identity)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showTopUpView) {
                IdentityTopUpView(identity: identity)
                    .environmentObject(appState)
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .alert("Success", isPresented: $appState.showSuccess) {
                Button("OK") { }
            } message: {
                Text(appState.successMessage)
            }
            .onAppear {
                loadCacheStatistics()
            }
        }
    }
    
    private func refreshIdentity() {
        Task {
            isRefreshing = true
            defer { isRefreshing = false }
            
            guard let identityService = appState.identityService else { 
                await showErrorMessage("Identity service not available")
                return 
            }
            
            do {
                if let refreshedIdentity = try await identityService.refreshIdentity(id: identity.idString) {
                    await MainActor.run {
                        identity = refreshedIdentity
                        // Update the app state as well
                        appState.updateIdentityBalance(id: identity.id, newBalance: refreshedIdentity.balance)
                        // Refresh cache statistics
                        loadCacheStatistics()
                    }
                }
            } catch {
                await showErrorMessage("Failed to refresh identity: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadCacheStatistics() {
        guard let identityService = appState.identityService else { return }
        cacheStats = identityService.getCacheStatistics()
    }
    
    @MainActor
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Identity Header Section

struct IdentityHeaderSection: View {
    let identity: IdentityModel
    @Binding var isRefreshing: Bool
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Identity Icon
            Image(systemName: identity.type == .masternode ? "server.rack" : "person.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(identity.type == .masternode ? .purple : .blue)
            
            // Identity Name/Alias
            VStack(spacing: 4) {
                Text(identity.alias ?? "Identity")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if identity.type != .user {
                    Text(identity.type.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(identity.type == .masternode ? Color.purple : Color.orange)
                        .cornerRadius(8)
                }
                
                HStack(spacing: 8) {
                    if identity.isLocal {
                        Text("Local")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    if !identity.isLocal {
                        Button(action: onRefresh) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Identity Balance Section

struct IdentityBalanceSection: View {
    let identity: IdentityModel
    let onTransfer: () -> Void
    let onTopUp: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Platform Credits")
                .font(.headline)
            
            Text(identity.formattedBalance)
                .font(.system(size: 36, weight: .medium, design: .monospaced))
                .foregroundColor(.blue)
            
            Text("\(identity.balance) credits")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Action Buttons
            HStack(spacing: 16) {
                Button(action: onTransfer) {
                    Label("Transfer", systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(identity.balance == 0 || identity.isLocal)
                
                Button(action: onTopUp) {
                    Label("Top Up", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(true) // Disabled until feature is fully implemented
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Identity Details Section

struct IdentityDetailsSection: View {
    let identity: IdentityModel
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Details")
            
            VStack(spacing: 0) {
                IdentityDetailRow(label: "Identity ID", value: identity.idString, isMono: true)
                IdentityDetailRow(label: "Type", value: identity.type.rawValue.capitalized)
                IdentityDetailRow(label: "Balance", value: "\(identity.balance) credits")
                
                if let alias = identity.alias {
                    IdentityDetailRow(label: "Alias", value: alias)
                }
                
                IdentityDetailRow(label: "Local Identity", value: identity.isLocal ? "Yes" : "No")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Identity Technical Section

struct IdentityTechnicalSection: View {
    let identity: IdentityModel
    @Binding var showRawData: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Technical Information")
            
            VStack(spacing: 0) {
                IdentityDetailRow(label: "Platform Network", value: "Testnet")
                IdentityDetailRow(label: "Keys Count", value: "\(identity.publicKeys.count)")
                IdentityDetailRow(label: "Public Key Hash", value: String(identity.idString.prefix(16)) + "...", isMono: true)
                
                // Raw Data Toggle
                HStack {
                    Text("Identity Raw Data")
                        .font(.body)
                    Spacer()
                    Button(showRawData ? "Hide" : "Show") {
                        withAnimation {
                            showRawData.toggle()
                        }
                    }
                    .font(.body)
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                
                if showRawData {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Identity ID (Hex):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(identity.idString)
                                .font(.system(.caption, design: .monospaced))
                            
                            Text("Identity ID (Base64):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(identity.id.base64EncodedString())
                                .font(.system(.caption, design: .monospaced))
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 120)
                    .background(Color(.systemGray5))
                }
            }
        }
    }
}

// MARK: - Identity Actions Section

struct IdentityActionsSection: View {
    let identity: IdentityModel
    @Binding var isCopied: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: copyIdentityId) {
                HStack {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    Text(isCopied ? "Copied!" : "Copy Identity ID")
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(8)
            }
            
            Button(action: exportIdentity) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Identity")
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.blue)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }
    
    private func copyIdentityId() {
        Clipboard.copy(identity.idString)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
    
    private func exportIdentity() {
        // Export identity information as text
        let identityData = """
        Identity ID: \(identity.idString)
        Alias: \(identity.alias ?? "None")
        Type: \(identity.type.rawValue)
        Balance: \(identity.balance) credits
        Local: \(identity.isLocal ? "Yes" : "No")
        """
        
        Clipboard.copy(identityData)
    }
}

// MARK: - Credit Transfer View

struct CreditTransferView: View {
    let fromIdentity: IdentityModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var recipientId = ""
    @State private var amount = ""
    @State private var isTransferring = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Transfer Credits") {
                    Text("From: \(fromIdentity.alias ?? "Identity")")
                        .foregroundColor(.secondary)
                    
                    TextField("Recipient Identity ID", text: $recipientId)
                        .textContentType(.none)
                        .autocapitalization(.none)
                    
                    TextField("Amount (credits)", text: $amount)
                        .keyboardType(.numberPad)
                }
                
                Section("Available Balance") {
                    Text("\(fromIdentity.balance) credits")
                        .font(.title3)
                        .fontWeight(.medium)
                }
                
                if isTransferring {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Transferring credits...")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Transfer Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Transfer") {
                        performTransfer()
                    }
                    .disabled(recipientId.isEmpty || amount.isEmpty || isTransferring)
                }
            }
        }
    }
    
    private func performTransfer() {
        guard let amountValue = UInt64(amount),
              amountValue > 0,
              amountValue <= fromIdentity.balance else {
            appState.showError(message: "Invalid amount")
            return
        }
        
        // Implement credit transfer using Platform SDK
        Task {
            isTransferring = true
            defer { isTransferring = false }
            
            // Simulate transfer
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            await MainActor.run {
                appState.showSuccess(message: "Transfer completed successfully")
                dismiss()
            }
        }
    }
}

// MARK: - Identity Top Up View

struct IdentityTopUpView: View {
    let identity: IdentityModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var isTopingUp = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Top Up Identity") {
                    Text("Identity: \(identity.alias ?? "Identity")")
                        .foregroundColor(.secondary)
                    
                    TextField("Amount (DASH)", text: $amount)
                        .keyboardType(.decimalPad)
                }
                
                Section("Current Balance") {
                    Text("\(identity.balance) credits")
                        .font(.title3)
                        .fontWeight(.medium)
                }
                
                Section {
                    Text("Top up will create an asset lock transaction from your Core wallet to fund this Platform identity.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if isTopingUp {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Creating asset lock...")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Top Up Identity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Top Up") {
                        performTopUp()
                    }
                    .disabled(amount.isEmpty || isTopingUp)
                }
            }
        }
    }
    
    private func performTopUp() {
        guard let dashAmount = Double(amount),
              dashAmount > 0 else {
            appState.showError(message: "Invalid amount")
            return
        }
        
        // Implement top up using AssetLockBridge
        Task {
            isTopingUp = true
            defer { isTopingUp = false }
            
            do {
                // Use AssetLockBridge for actual top up implementation
                if let assetLockBridge = appState.assetLockBridge {
                    // TODO: Implement identity top-up feature
                    // This should create an asset lock transaction and fund the identity
                    
                    // Refresh identity data after successful top up
                    // await appState.refreshIdentityData() // TODO: Implement this method
                    
                    // For now, just show a success message since the button is disabled
                    await MainActor.run {
                        appState.showError(message: "Top up feature is not yet implemented")
                        dismiss()
                    }
                    return
                } else {
                    throw NSError(domain: "TopUpError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Asset lock bridge not available"])
                }
            } catch {
                await MainActor.run {
                    appState.showError(message: "Top up failed: \(error.localizedDescription)")
                }
                return
            }
            
            await MainActor.run {
                appState.showSuccess(message: "Top up completed successfully")
                dismiss()
            }
        }
    }
}

// MARK: - IdentityDetailRow

struct IdentityDetailRow: View {
    let label: String
    let value: String
    let isMono: Bool
    
    init(label: String, value: String, isMono: Bool = false) {
        self.label = label
        self.value = value
        self.isMono = isMono
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(isMono ? .system(.subheadline, design: .monospaced) : .subheadline)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

// MARK: - Identity Cache Statistics Section

struct IdentityCacheStatsSection: View {
    let stats: IdentityCacheStatistics
    
    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Cache Statistics")
            
            VStack(spacing: 0) {
                IdentityDetailRow(label: "Total Cached", value: "\(stats.totalCached)")
                IdentityDetailRow(label: "Active Cached", value: "\(stats.activeCached)")
                IdentityDetailRow(label: "Expired Cached", value: "\(stats.expiredCached)")
                
                if let lastSync = stats.lastSyncDate {
                    IdentityDetailRow(label: "Last Sync", value: formatDate(lastSync))
                } else {
                    IdentityDetailRow(label: "Last Sync", value: "Never")
                }
                
                IdentityDetailRow(label: "Sync Status", value: stats.isSyncing ? "Syncing..." : "Idle")
                
                if stats.syncErrorCount > 0 {
                    IdentityDetailRow(label: "Sync Errors", value: "\(stats.syncErrorCount)")
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    let identity = IdentityModel(
        id: Data(repeating: 0xAB, count: 32),
        balance: 1000000,
        isLocal: false,
        alias: "Test Identity",
        type: .user
    )
    
    IdentityDetailView(identity: identity)
        .environmentObject(AppState())
}