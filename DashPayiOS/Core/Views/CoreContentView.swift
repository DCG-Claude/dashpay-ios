import SwiftUI
import SwiftData
import SwiftDashCoreSDK
import os.log

struct CoreContentView: View {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DashPay", category: "CoreContentView")
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var walletService: WalletService
    @Query private var wallets: [HDWallet]
    
    @State private var showCreateWallet = false
    @State private var showImportWallet = false
    @State private var selectedWallet: HDWallet?
    
    var body: some View {
        #if os(iOS)
        NavigationStack {
            WalletListView(
                wallets: wallets,
                onCreateWallet: { showCreateWallet = true },
                onImportWallet: { showImportWallet = true }
            )
            .onAppear {
                logger.info("ContentView appeared with \(wallets.count) wallets")
                // Trigger auto-sync when view appears and wallets are loaded
                if !wallets.isEmpty {
                    Task {
                        logger.info("🔄 Triggering auto-sync for loaded wallets...")
                        await walletService.startAutoSync()
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateWallet) {
            CreateWalletView { wallet in
                showCreateWallet = false
                selectedWallet = wallet
            }
        }
        .sheet(isPresented: $showImportWallet) {
            ImportWalletView { wallet in
                showImportWallet = false
                selectedWallet = wallet
            }
        }
        #else
        NavigationSplitView {
            // Wallet List
            List(selection: $selectedWallet) {
                Section("Wallets") {
                    ForEach(wallets) { wallet in
                        WalletRowView(wallet: wallet)
                            .tag(wallet)
                    }
                }
                
                Section {
                    Button(action: { showCreateWallet = true }) {
                        Label("Create New Wallet", systemImage: "plus.circle")
                    }
                    
                    Button(action: { showImportWallet = true }) {
                        Label("Import Wallet", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationTitle("Dash HD Wallets")
            .listStyle(SidebarListStyle())
        } detail: {
            // Wallet Detail
            if let wallet = selectedWallet {
                WalletDetailView(wallet: wallet)
            } else {
                EmptyWalletView()
            }
        }
        .sheet(isPresented: $showCreateWallet) {
            CreateWalletView { wallet in
                selectedWallet = wallet
            }
        }
        .sheet(isPresented: $showImportWallet) {
            ImportWalletView { wallet in
                selectedWallet = wallet
            }
        }
        #endif
    }
}

// MARK: - Wallet List View

struct WalletListView: View {
    let wallets: [HDWallet]
    let onCreateWallet: () -> Void
    let onImportWallet: () -> Void
    
    @State private var showingSettings = false
    
    var body: some View {
        #if os(iOS)
        List {
            if wallets.isEmpty {
                Section {
                    VStack(spacing: 20) {
                        Image(systemName: "wallet.pass")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        
                        Text("No wallets yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Create or import a wallet to get started")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color.clear)
            } else {
                Section("Wallets") {
                    ForEach(wallets) { wallet in
                        NavigationLink(destination: WalletDetailView(wallet: wallet)) {
                            WalletRowView(wallet: wallet)
                        }
                    }
                }
            }
            
            Section {
                Button(action: onCreateWallet) {
                    Label("Create New Wallet", systemImage: "plus.circle")
                }
                
                Button(action: onImportWallet) {
                    Label("Import Wallet", systemImage: "square.and.arrow.down")
                }
            }
        }
        .navigationTitle("Dash HD Wallets")
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        #else
        List(selection: $selectedWallet) {
            Section("Wallets") {
                ForEach(wallets) { wallet in
                    WalletRowView(wallet: wallet)
                        .tag(wallet)
                }
            }
            
            Section {
                Button(action: onCreateWallet) {
                    Label("Create New Wallet", systemImage: "plus.circle")
                }
                
                Button(action: onImportWallet) {
                    Label("Import Wallet", systemImage: "square.and.arrow.down")
                }
            }
        }
        .navigationTitle("Dash HD Wallets")
        .listStyle(SidebarListStyle())
        #endif
    }
}

// MARK: - Wallet Row View

struct WalletRowView: View {
    let wallet: HDWallet
    @EnvironmentObject var walletService: WalletService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(wallet.name)
                    .font(.headline)
                
                Spacer()
                
                // Sync status indicator
                if walletService.activeWallet == wallet && walletService.isSyncing {
                    SyncStatusBadge(progress: walletService.syncProgress)
                } else if let lastSync = wallet.lastSynced {
                    LastSyncBadge(date: lastSync)
                }
                
                NetworkBadge(network: wallet.network)
            }
            
            HStack {
                Text("\(wallet.accounts.count) accounts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Show sync progress if syncing
                if walletService.activeWallet == wallet, 
                   let progress = walletService.syncProgress {
                    Text("\(Int(progress.progress * 100))% synced")
                        .font(.caption2)
                        .foregroundColor(.blue)
                } else {
                    Text(wallet.totalBalance?.formattedTotal ?? "0.00000000 DASH")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SyncStatusBadge: View {
    let progress: SyncProgress?
    
    var body: some View {
        HStack(spacing: 4) {
            ProgressView()
                .scaleEffect(0.7)
            
            if let progress = progress {
                Text("\(Int(progress.progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(4)
    }
}

struct LastSyncBadge: View {
    let date: Date
    
    var body: some View {
        Text(timeAgoString(from: date))
            .font(.caption2)
            .foregroundColor(.secondary)
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
    }
}

// MARK: - Network Badge

struct NetworkBadge: View {
    let network: DashNetwork
    
    var body: some View {
        Text(network.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }
    
    private var backgroundColor: Color {
        switch network {
        case .mainnet:
            return .blue
        case .testnet:
            return .orange
        case .devnet:
            return .pink
        case .regtest:
            return .purple
        }
    }
}

// MARK: - Empty Wallet View

struct EmptyWalletView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            Text("No Wallet Selected")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Create or import a wallet to get started")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

