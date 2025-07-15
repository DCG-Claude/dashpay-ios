import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var appState: UnifiedAppState
    @EnvironmentObject var walletService: WalletService
    
    var body: some View {
        if !appState.isInitialized {
            VStack(spacing: 20) {
                ProgressView("Initializing...")
                    .scaleEffect(1.5)
                
                if let error = appState.error {
                    VStack(spacing: 10) {
                        Text("Initialization Error")
                            .font(.headline)
                            .foregroundColor(.red)
                        
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Retry") {
                            Task {
                                appState.error = nil
                                await appState.initialize()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TabView {
                // Core features
                CoreWalletView()
                    .tabItem {
                        Label("Wallets", systemImage: "wallet.pass")
                    }
                
                CoreTransactionsView()
                    .tabItem {
                        Label("Transactions", systemImage: "list.bullet")
                    }
                
                // Platform features
                PlatformIdentitiesView()
                    .tabItem {
                        Label("Identities", systemImage: "person.3")
                    }
                
                PlatformDocumentsView()
                    .tabItem {
                        Label("Documents", systemImage: "doc.text")
                    }
                
                // Settings
                UnifiedSettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                
                // Debug tab removed - not in rust-dashcore reference implementation
            }
            .overlay(alignment: .top) {
                if walletService.isSyncing {
                    GlobalSyncIndicator()
                        .environmentObject(walletService)
                }
            }
        }
    }
}

struct GlobalSyncIndicator: View {
    @EnvironmentObject var walletService: WalletService
    @State private var showDetailedProgress = false
    
    var body: some View {
        VStack(spacing: 0) {
            if let progress = walletService.detailedSyncProgress {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .symbolEffect(.pulse)
                    
                    Text("Syncing: \(progress.formattedPercentage)")
                        .font(.caption)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(progress.formattedTimeRemaining)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        walletService.stopSync()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Material.thin)
                .contentShape(Rectangle()) // Make entire area tappable
                .onTapGesture {
                    showDetailedProgress = true
                }
                
                // Progress bar
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * (progress.percentage / 100))
                }
                .frame(height: 2)
            }
        }
        .sheet(isPresented: $showDetailedProgress) {
            EnhancedSyncProgressView()
                .environmentObject(walletService)
        }
    }
}

// Wrapper views - connecting to actual views from examples
struct CoreWalletView: View {
    @EnvironmentObject var appState: UnifiedAppState
    
    var body: some View {
        // Use the actual Core ContentView which contains WalletListView
        CoreContentView()
            .environmentObject(appState.walletService)
            .environment(\.modelContext, appState.modelContainer.mainContext)
    }
}

struct CoreTransactionsView: View {
    @EnvironmentObject var appState: UnifiedAppState
    @Query private var wallets: [HDWallet]
    
    var body: some View {
        NavigationStack {
            if let firstWallet = wallets.first {
                // Navigate directly to wallet detail which shows transactions
                WalletDetailView(wallet: firstWallet)
            } else {
                ContentUnavailableView(
                    "No Wallets",
                    systemImage: "wallet.pass",
                    description: Text("Create a wallet to view transactions")
                )
            }
        }
        .environmentObject(appState.walletService)
    }
}

struct PlatformIdentitiesView: View {
    @EnvironmentObject var appState: UnifiedAppState
    
    var body: some View {
        NavigationStack {
            IdentitiesView() // From Platform example
        }
        .environmentObject(appState.platformState)
    }
}

struct PlatformDocumentsView: View {
    @EnvironmentObject var appState: UnifiedAppState
    
    var body: some View {
        NavigationStack {
            DocumentsView() // From Platform example
        }
        .environmentObject(appState.platformState)
    }
}

struct UnifiedSettingsView: View {
    @EnvironmentObject var appState: UnifiedAppState
    
    var body: some View {
        NavigationStack {
            UnifiedSettingsContent()
        }
    }
}

struct UnifiedSettingsContent: View {
    @EnvironmentObject var appState: UnifiedAppState
    
    var body: some View {
        List {
            Section("Network") {
                HStack {
                    Text("Network")
                    Spacer()
                    Text("Testnet")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Core Sync")
                    Spacer()
                    if let progress = appState.walletService.detailedSyncProgress {
                        Text("\(Int(progress.percentage))%")
                            .foregroundColor(.secondary)
                    } else if appState.walletService.syncProgress != nil {
                        Text("Syncing...")
                            .foregroundColor(.secondary)
                    } else {
                        Text("Not syncing")
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text("Platform Sync")
                    Spacer()
                    Text(appState.unifiedState.isPlatformSynced ? "Synced" : "Offline")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }
}