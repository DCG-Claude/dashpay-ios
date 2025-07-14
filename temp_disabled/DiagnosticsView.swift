import SwiftUI
import SwiftDashCoreSDK

struct DiagnosticsView: View {
    @EnvironmentObject var walletService: WalletService
    @State private var diagnosticReport: String = "Loading..."
    // Connection status removed during simplification
    // @State private var connectionStatus: ConnectionStatus?
    @State private var isRetrying = false
    @State private var isForceResyncing = false
    @State private var showingResyncAlert = false
    @State private var resyncError: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("Connection Diagnostics")
                    .font(.largeTitle)
                    .bold()
                
                // Connection Status Card - Removed during simplification
                // if let status = connectionStatus {
                //     ConnectionStatusCard(status: status)
                // }
                
                // Sync Progress Card (show during sync)
                if let progress = walletService.detailedSyncProgress {
                    SyncProgressCard(progress: progress)
                }
                
                // Action Buttons
                HStack(spacing: 15) {
                    Button(action: runDiagnostics) {
                        Label("Run Diagnostics", systemImage: "stethoscope")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: retryConnection) {
                        Label("Retry Connection", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRetrying)
                }
                
                // Diagnostic Report
                GroupBox("Diagnostic Report") {
                    Text(diagnosticReport)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Quick Actions
                GroupBox("Quick Actions") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Use Local Peers", isOn: Binding(
                            get: { walletService.isUsingLocalPeers() },
                            set: { walletService.setUseLocalPeers($0) }
                        ))
                        
                        if walletService.isUsingLocalPeers() {
                            HStack {
                                Text("Local Peer:")
                                TextField("IP Address", text: Binding(
                                    get: { walletService.getLocalPeerHost() },
                                    set: { walletService.setLocalPeerHost($0) }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                        
                        Divider()
                        
                        // Force Full Resync Button
                        Button(action: forceFullResync) {
                            Label("Force Full Resync", systemImage: "arrow.triangle.2.circlepath")
                                .foregroundColor(.orange)
                        }
                        .disabled(isForceResyncing || walletService.activeWallet == nil)
                        
                        if isForceResyncing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Clearing data and reconnecting...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        // FFI Direct Test Button
                        NavigationLink(destination: FFIDirectTestView()) {
                            Label("FFI Direct Test", systemImage: "wrench.and.screwdriver")
                                .foregroundColor(.purple)
                        }
                        
                        // Network Test Button
                        NavigationLink(destination: NetworkTestView()) {
                            Label("Network Connectivity Test", systemImage: "network")
                                .foregroundColor(.orange)
                        }
                        
                        // Direct Connection Test Button
                        NavigationLink(destination: DirectConnectionTestView()) {
                            Label("Direct SDK Test", systemImage: "bolt.horizontal.circle")
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            runDiagnostics()
        }
        .alert("Force Full Resync", isPresented: $showingResyncAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Resync", role: .destructive) {
                performForceResync()
            }
        } message: {
            Text("This will clear all blockchain data and resync from block 0. This process may take several minutes depending on your connection speed. Continue?")
        }
        .alert("Resync Error", isPresented: .constant(resyncError != nil)) {
            Button("OK") {
                resyncError = nil
            }
        } message: {
            if let error = resyncError {
                Text(error)
            }
        }
    }
    
    private func runDiagnostics() {
        // Diagnostics simplified - removed during connection simplification
        diagnosticReport = """
Connection Status: \(walletService.isConnected ? "Connected" : "Disconnected")
Sync Status: \(walletService.isSyncing ? "Syncing" : "Not Syncing")
Current Block: \(walletService.currentBlockHeight)
Target Block: \(walletService.targetBlockHeight)
Connected Peers: \(walletService.connectedPeers)
"""
    }
    
    private func retryConnection() {
        isRetrying = true
        Task {
            do {
                // Simple reconnect - retry mechanism removed during simplification
                if let wallet = walletService.activeWallet, 
                   let account = walletService.activeAccount {
                    try await walletService.connect(wallet: wallet, account: account)
                }
                runDiagnostics()
            } catch {
                diagnosticReport += "\n\nRetry failed: \(error.localizedDescription)"
            }
            isRetrying = false
        }
    }
    
    private func forceFullResync() {
        showingResyncAlert = true
    }
    
    private func performForceResync() {
        isForceResyncing = true
        resyncError = nil
        
        Task {
            do {
                try await walletService.forceSyncFromScratch()
                // Update diagnostics after resync starts
                await runDiagnostics()
            } catch {
                resyncError = "Failed to start resync: \(error.localizedDescription)"
            }
            isForceResyncing = false
        }
    }
}

// Connection status card removed during simplification
// struct ConnectionStatusCard: View {
//     let status: ConnectionStatus
//     
//     var body: some View {
//         GroupBox("Connection Status") {
//             VStack(alignment: .leading, spacing: 8) {
//                 StatusRow(label: "Core SDK", isSuccess: status.coreSDKInitialized)
//                 StatusRow(label: "Core Connected", isSuccess: status.coreSDKConnected)
//                 StatusRow(label: "Network Available", isSuccess: status.networkAvailable)
//                 
//                 if let error = status.coreConnectionError {
//                     Label(error, systemImage: "exclamationmark.triangle")
//                         .foregroundColor(.red)
//                         .font(.caption)
//                 }
//                 
//                 HStack {
//                     Text("Peer Config:")
//                         .font(.caption)
//                         .foregroundColor(.secondary)
//                     Text(status.peerConfiguration)
//                         .font(.caption)
//                 }
//             }
//         }
//     }
// }

struct StatusRow: View {
    let label: String
    let isSuccess: Bool
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isSuccess ? .green : .red)
        }
    }
}

struct SyncProgressCard: View {
    let progress: DetailedSyncProgress
    
    var body: some View {
        GroupBox("Sync Progress") {
            VStack(alignment: .leading, spacing: 8) {
                // Stage and status
                HStack {
                    Text(progress.stage.icon)
                    Text(progress.stageMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Progress bar
                ProgressView(value: progress.percentage, total: 100)
                    .progressViewStyle(.linear)
                
                // Progress details
                HStack {
                    Text("\(progress.formattedPercentage)")
                        .font(.caption)
                        .bold()
                    Spacer()
                    Text(progress.formattedTimeRemaining)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Statistics
                HStack {
                    VStack(alignment: .leading) {
                        Text("Height")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(progress.currentHeight)/\(progress.totalHeight)")
                            .font(.caption)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Speed")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(progress.formattedSpeed)
                            .font(.caption)
                    }
                }
                
                // Connected peers
                if progress.connectedPeers > 0 {
                    HStack {
                        Text("Peers:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(progress.connectedPeers)")
                            .font(.caption)
                    }
                }
            }
        }
    }
}

#Preview {
    DiagnosticsView()
        .environmentObject(WalletService.shared)
}