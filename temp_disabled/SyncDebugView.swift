import SwiftUI

struct SyncDebugView: View {
    @EnvironmentObject private var walletService: WalletService
    @State private var showClearDataAlert = false
    @State private var isClearing = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "ant.circle.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text("Sync Debug Information")
                        .font(.headline)
                }
                .padding(.bottom, 4)
                
                Text("Real-time blockchain synchronization data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            
            ScrollView {
                VStack(spacing: 16) {
                    // Connection Status
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Connection Status", systemImage: "network")
                                .font(.headline)
                            
                            Divider()
                            
                            DebugRow(label: "Connected", value: walletService.isConnected ? "Yes ✅" : "No ❌")
                            DebugRow(label: "Syncing", value: walletService.isSyncing ? "Yes 🔄" : "No ⏸️")
                            // TODO: Add connectedPeers property to WalletService
                            // DebugRow(label: "Connected Peers", value: "\(walletService.connectedPeers)")
                            
                            // TODO: Add lastSyncError property to WalletService
                            /*
                            if let error = walletService.lastSyncError {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Last Error:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            */
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Sync Progress
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Sync Progress", systemImage: "arrow.triangle.2.circlepath")
                                .font(.headline)
                            
                            Divider()
                            
                            // TODO: Add block height properties to WalletService
                            /*
                            DebugRow(label: "Current Block", value: "\(walletService.currentBlockHeight)")
                            DebugRow(label: "Target Block", value: "\(walletService.targetBlockHeight)")
                            
                            if walletService.targetBlockHeight > 0 {
                                let progress = Double(walletService.currentBlockHeight) / Double(walletService.targetBlockHeight)
                                DebugRow(label: "Progress", value: String(format: "%.2f%%", progress * 100))
                                
                                let remaining = walletService.targetBlockHeight - walletService.currentBlockHeight
                                DebugRow(label: "Blocks Remaining", value: "\(remaining)")
                            }
                            */
                            
                            if let detailedProgress = walletService.detailedSyncProgress {
                                DebugRow(label: "Stage", value: "\(detailedProgress.stage)")
                                DebugRow(label: "Headers Processed", value: "\(detailedProgress.totalHeadersProcessed)")
                                
                                if detailedProgress.estimatedSecondsRemaining > 0 {
                                    DebugRow(label: "ETA", value: formatTime(Double(detailedProgress.estimatedSecondsRemaining)))
                                }
                                
                                if detailedProgress.headersPerSecond > 0 {
                                    DebugRow(label: "Speed", value: "\(Int(detailedProgress.headersPerSecond)) headers/sec")
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Wallet Status
                    if let wallet = walletService.activeWallet {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Wallet Status", systemImage: "wallet.pass")
                                    .font(.headline)
                                
                                Divider()
                                
                                DebugRow(label: "Name", value: wallet.name)
                                DebugRow(label: "Network", value: wallet.network.rawValue)
                                
                                if let lastSynced = wallet.lastSynced {
                                    DebugRow(label: "Last Synced", value: formatDate(lastSynced))
                                } else {
                                    DebugRow(label: "Last Synced", value: "Never")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    // Actions
                    GroupBox {
                        VStack(spacing: 12) {
                            Label("Debug Actions", systemImage: "wrench.and.screwdriver")
                                .font(.headline)
                            
                            Divider()
                            
                            // Force Resync Button
                            Button(action: forceSyncFromScratch) {
                                Label("Force Resync from Block 0", systemImage: "arrow.clockwise.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(!walletService.isConnected || walletService.isSyncing)
                            
                            // Clear Sync Data Button
                            Button(action: { showClearDataAlert = true }) {
                                Label("Clear All Sync Data", systemImage: "trash.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(.red)
                            .disabled(walletService.isSyncing || isClearing)
                            
                            // Test Connectivity Button
                            Button(action: testConnectivity) {
                                Label("Test Peer Connectivity", systemImage: "network.badge.shield.half.filled")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }
        }
        .alert("Clear Sync Data", isPresented: $showClearDataAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearSyncData()
            }
        } message: {
            Text("This will delete all blockchain data and force a complete resync. This action cannot be undone.")
        }
    }
    
    // MARK: - Helper Views
    
    struct DebugRow: View {
        let label: String
        let value: String
        
        var body: some View {
            HStack {
                Text(label)
                    .font(.callout)
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.callout.monospacedDigit())
                    .foregroundColor(.primary)
            }
        }
    }
    
    // MARK: - Actions
    
    private func forceSyncFromScratch() {
        Task {
            do {
                // TODO: Add forceSyncFromScratch method to WalletService
                // try await walletService.forceSyncFromScratch()
                print("Force sync from scratch not implemented yet")
            } catch {
                print("Force sync error: \(error)")
                // TODO: Add lastSyncError property to WalletService
                // await MainActor.run {
                //     walletService.lastSyncError = error.localizedDescription
                // }
            }
        }
    }
    
    private func clearSyncData() {
        Task {
            isClearing = true
            do {
                // TODO: Add clearSyncData method to WalletService
                // try await walletService.clearSyncData()
                print("Clear sync data not implemented yet")
            } catch {
                print("Clear sync data error: \(error)")
                // TODO: Add lastSyncError property to WalletService
                // await MainActor.run {
                //     walletService.lastSyncError = error.localizedDescription
                // }
            }
            isClearing = false
        }
    }
    
    private func testConnectivity() {
        Task {
            await walletService.testPeerConnectivity()
        }
    }
    
    // MARK: - Formatters
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatTime(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else {
            return "\(Int(seconds / 3600))h \(Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60))m"
        }
    }
}

#Preview {
    SyncDebugView()
        .environmentObject(WalletService.shared)
}