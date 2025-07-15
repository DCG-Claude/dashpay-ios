import SwiftUI
import SwiftData
import SwiftDashSDK
import DashSPVFFI
import SwiftDashCoreSDK

struct WalletDetailView: View {
    @EnvironmentObject private var walletService: WalletService
    @Environment(\.modelContext) private var modelContext
    
    let wallet: HDWallet
    @State private var selectedAccount: HDAccount?
    @State private var showCreateAccount = false
    @State private var showSyncProgress = false
    @State private var isConnecting = false
    @State private var syncWasCompleted = false  // Track if sync finished
    
    var body: some View {
        #if os(iOS)
        VStack {
            // Connection status indicator
            if isConnecting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Connecting...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            } else if walletService.isConnected && walletService.activeWallet == wallet {
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            
            if wallet.name.isEmpty {
                ContentUnavailableView {
                    Label("Wallet Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Unable to load wallet data")
                }
            } else {
                AccountListView(
                    wallet: wallet,
                    selectedAccount: $selectedAccount,
                    onCreateAccount: { showCreateAccount = true }
                )
            }
        }
        .navigationTitle(wallet.name.isEmpty ? "Error" : wallet.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup {
                if walletService.isConnected && walletService.activeWallet == wallet {
                    // Show sync button when connected
                    Button(action: { 
                        syncWasCompleted = false
                        showSyncProgress = true 
                    }) {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(walletService.isSyncing)
                } else {
                    // Show connect button when disconnected
                    Button(action: { 
                        Task {
                            await connectWallet()
                        }
                    }) {
                        Label("Connect", systemImage: "link")
                    }
                    .disabled(isConnecting)
                }
            }
        }
        .sheet(isPresented: $showCreateAccount) {
            CreateAccountView(wallet: wallet) { account in
                selectedAccount = account
            }
        }
        .sheet(isPresented: $showSyncProgress) {
            EnhancedSyncProgressView()
        }
        .onAppear {
            if selectedAccount == nil {
                selectedAccount = wallet.accounts.first
            }
            
            // Don't auto-connect - let user control the process
        }
        .onChange(of: walletService.syncProgress) { oldValue, newValue in
            handleSyncProgressChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: walletService.detailedSyncProgress) { newValue in
            handleDetailedSyncProgressChange(oldValue: nil, newValue: newValue)
        }
        #else
        HSplitView {
            // Account List
            AccountListView(
                wallet: wallet,
                selectedAccount: $selectedAccount,
                onCreateAccount: { showCreateAccount = true }
            )
            .frame(minWidth: 200, idealWidth: 250)
            
            // Account Detail
            if let account = selectedAccount {
                AccountDetailView(account: account)
            } else {
                EmptyAccountView()
            }
        }
        .navigationTitle(wallet.name)
        .navigationSubtitle(wallet.displayNetwork)
        .toolbar {
            ToolbarItemGroup {
                if walletService.isConnected && walletService.activeWallet == wallet {
                    // Show sync button when connected
                    Button(action: { 
                        syncWasCompleted = false
                        showSyncProgress = true 
                    }) {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(walletService.isSyncing)
                } else {
                    // Show connect button when disconnected
                    Button(action: { 
                        Task {
                            await connectWallet()
                        }
                    }) {
                        Label("Connect", systemImage: "link")
                    }
                    .disabled(isConnecting)
                }
            }
        }
        .sheet(isPresented: $showCreateAccount) {
            CreateAccountView(wallet: wallet) { account in
                selectedAccount = account
            }
        }
        .sheet(isPresented: $showSyncProgress) {
            EnhancedSyncProgressView()
        }
        .onAppear {
            if selectedAccount == nil {
                selectedAccount = wallet.accounts.first
            }
        }
        .onChange(of: walletService.syncProgress) { oldValue, newValue in
            handleSyncProgressChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: walletService.detailedSyncProgress) { newValue in
            handleDetailedSyncProgressChange(oldValue: nil, newValue: newValue)
        }
        #endif
    }
    
    private func connectWallet() async {
        guard let firstAccount = wallet.accounts.first else { return }
        
        isConnecting = true
        do {
            print("🔌 Connecting wallet...")
            try await walletService.connect(wallet: wallet, account: firstAccount)
            selectedAccount = firstAccount
            print("✅ Connected successfully!")
        } catch {
            print("❌ Connection failed: \(error)")
        }
        isConnecting = false
    }
    
    // MARK: - Helper Functions for Sync Progress Monitoring
    
    private func handleSyncProgressChange(oldValue: SyncProgress?, newValue: SyncProgress?) {
        // Monitor sync completion
        if let progress = newValue {
            // Check if sync just completed
            if progress.status == .synced && oldValue?.status != .synced {
                syncWasCompleted = true
            }
        }
    }
    
    private func handleDetailedSyncProgressChange(oldValue: SwiftDashCoreSDK.DetailedSyncProgress?, newValue: SwiftDashCoreSDK.DetailedSyncProgress?) {
        // Also monitor detailed sync progress for completion
        if let progress = newValue, progress.stage == .complete {
            if oldValue?.stage != .complete {
                syncWasCompleted = true
            }
        }
    }
    
}

// MARK: - Account List View

struct AccountListView: View {
    let wallet: HDWallet
    @Binding var selectedAccount: HDAccount?
    let onCreateAccount: () -> Void
    
    var body: some View {
        #if os(iOS)
        List {
            Section("Accounts") {
                ForEach(wallet.accounts.sorted { $0.accountIndex < $1.accountIndex }) { account in
                    NavigationLink(destination: AccountDetailView(account: account)) {
                        AccountRowView(account: account)
                    }
                }
            }
            
            Section {
                Button(action: onCreateAccount) {
                    Label("Add Account", systemImage: "plus.circle")
                }
            }
        }
        .listStyle(.insetGrouped)
        #else
        List(selection: $selectedAccount) {
            Section("Accounts") {
                ForEach(wallet.accounts.sorted { $0.accountIndex < $1.accountIndex }) { account in
                    AccountRowView(account: account)
                        .tag(account)
                }
            }
            
            Section {
                Button(action: onCreateAccount) {
                    Label("Add Account", systemImage: "plus.circle")
                }
            }
        }
        .listStyle(SidebarListStyle())
        #endif
    }
}

// MARK: - Account Row View

struct AccountRowView: View {
    let account: HDAccount
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(account.displayName)
                .font(.headline)
            
            Text(account.derivationPath)
                .font(.caption)
                .foregroundColor(.secondary)
                .fontDesign(.monospaced)
            
            if let balance = account.balance {
                Text(DashFormatting.formatDash(balance.total))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty Account View

struct EmptyAccountView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.dashed")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            Text("No Account Selected")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}



