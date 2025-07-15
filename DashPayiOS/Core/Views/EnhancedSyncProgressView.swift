import SwiftUI
import UIKit
import SwiftDashSDK
import SwiftDashCoreSDK

#if os(macOS)
import AppKit
#endif

struct EnhancedSyncProgressView: View {
    @EnvironmentObject private var walletService: WalletService
    @Environment(\.dismiss) private var dismiss
    
    @State private var hasStarted = false
    @State private var showStatistics = false
    @State private var syncError: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let detailedProgress = walletService.detailedSyncProgress {
                    // Enhanced Progress Display
                    DetailedProgressContent(progress: detailedProgress)
                        .transition(.opacity.combined(with: .scale))
                } else if let legacyProgress = walletService.syncProgress {
                    // Fallback to legacy progress
                    LegacyProgressContent(progress: legacyProgress)
                        .transition(.opacity)
                } else if !hasStarted {
                    // Start Sync
                    StartSyncContent(onStart: startSync)
                } else if let error = syncError {
                    // Error state
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        
                        Text("Sync Failed")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(error)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Try Again") {
                            syncError = nil
                            hasStarted = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    // Loading
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.5)
                        
                        Text("Starting sync...")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Text("This may take a moment")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Filter Sync Status Warning (if not available)
                if let syncProgress = walletService.syncProgress,
                   !syncProgress.filterSyncAvailable {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Compact filters not available - connected peers don't support BIP 157/158")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Statistics Toggle
                if walletService.detailedSyncProgress != nil {
                    Button(showStatistics ? "Hide Statistics" : "Show Statistics") {
                        withAnimation {
                            showStatistics.toggle()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                // Detailed Statistics
                if showStatistics, !walletService.syncStatistics.isEmpty {
                    DetailedStatisticsView(statistics: walletService.syncStatistics)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Blockchain Sync")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(walletService.isSyncing ? "Cancel" : "Close") {
                        if walletService.isSyncing {
                            walletService.stopSync()
                        }
                        dismiss()
                    }
                }
                
                if walletService.isSyncing {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Pause Sync", systemImage: "pause.circle") {
                                // Future: Implement pause functionality
                            }
                            .disabled(true)
                            
                            Button("Cancel Sync", systemImage: "xmark.circle") {
                                walletService.stopSync()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .animation(.easeInOut, value: walletService.detailedSyncProgress?.percentage ?? 0)
            .animation(.easeInOut, value: showStatistics)
        }
        #if os(macOS)
        .frame(width: 700, height: showStatistics ? 700 : 600)
        #endif
        .onAppear {
            // Don't reset if we're already syncing
            if walletService.isSyncing {
                hasStarted = true
            }
            // Otherwise keep the current state
        }
    }
    
    private func startSync() {
        hasStarted = true
        syncError = nil
        
        Task {
            do {
                print("📱 EnhancedSyncProgressView: Starting sync...")
                print("   Is connected: \(walletService.isConnected)")
                print("   Active wallet: \(walletService.activeWallet?.name ?? "none")")
                print("   Is syncing: \(walletService.isSyncing)")
                print("   SDK exists: \(walletService.sdk != nil)")
                
                // Check if we're actually connected
                guard walletService.isConnected else {
                    throw NSError(domain: "WalletError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Wallet is not connected"])
                }
                
                // Use structured concurrency with timeout to prevent race conditions
                try await withThrowingTaskGroup(of: Void.self) { group in
                    // Start the sync task
                    group.addTask {
                        try await withTaskCancellationHandler {
                            try await self.walletService.startSyncWithCallbacks()
                        } onCancel: {
                            print("🟡 Sync task cancelled due to timeout")
                        }
                    }
                    
                    // Start timeout task that will cancel the group
                    group.addTask {
                        try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                        group.cancelAll()
                        throw NSError(domain: "SyncTimeout", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sync timed out - no progress received after 10 seconds"])
                    }
                    
                    // Wait for the first task to complete and handle the result
                    do {
                        try await group.next()
                        // If we get here, sync completed successfully
                        group.cancelAll() // Cancel the timeout task
                    } catch is CancellationError {
                        // Sync was cancelled, let the timeout error propagate
                        try await group.next()
                    }
                }
                
                print("✅ EnhancedSyncProgressView: Sync started successfully")
            } catch {
                print("❌ EnhancedSyncProgressView: Sync error: \(error)")
                print("   Error type: \(type(of: error))")
                
                await MainActor.run {
                    syncError = "Sync failed: \(error.localizedDescription)"
                    hasStarted = false
                }
            }
        }
    }
}

// MARK: - Detailed Progress Content

struct DetailedProgressContent: View {
    let progress: SwiftDashCoreSDK.DetailedSyncProgress
    
    var body: some View {
        VStack(spacing: 24) {
            // Stage Icon and Status
            VStack(spacing: 12) {
                Text(progress.stage.icon)
                    .font(.system(size: 80))
                    .symbolEffect(.pulse, isActive: progress.stage.isActive)
                
                Text(progress.stage.description)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(progress.stageMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Progress Circle
            CircularProgressView(
                progress: progress.percentage / 100.0,
                formattedPercentage: progress.formattedPercentage,
                speed: progress.formattedSpeed
            )
            .frame(width: 200, height: 200)
            
            // Block Progress
            VStack(spacing: 16) {
                HStack(spacing: 30) {
                    ProgressStatView(
                        title: "Current Height",
                        value: "\(progress.currentHeight)",
                        icon: "arrow.up.square"
                    )
                    
                    ProgressStatView(
                        title: "Target Height",
                        value: "\(progress.totalHeight)",
                        icon: "flag.checkered"
                    )
                    
                    ProgressStatView(
                        title: "Connected Peers",
                        value: "\(progress.connectedPeers)",
                        icon: "network"
                    )
                }
                
                // ETA and Duration
                HStack(spacing: 30) {
                    VStack(spacing: 4) {
                        Label("Time Remaining", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(progress.formattedTimeRemaining)
                            .font(.headline)
                            .monospacedDigit()
                    }
                    
                    VStack(spacing: 4) {
                        Label("Sync Duration", systemImage: "timer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatDuration(from: progress.syncStartTimestamp))
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
            }
            .padding()
            .background(Color(PlatformColor.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let progress: Double
    let formattedPercentage: String
    let speed: String
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 20)
            
            // Progress circle
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
            
            // Center content
            VStack(spacing: 8) {
                Text(formattedPercentage)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .monospacedDigit()
                
                Text(speed)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Progress Stat View

struct ProgressStatView: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
            
            Text(value)
                .font(.headline)
                .monospacedDigit()
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Start Sync Content

struct StartSyncContent: View {
    let onStart: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "arrow.triangle.2.circlepath.circle")
                .font(.system(size: 100))
                .foregroundColor(.accentColor)
                .symbolEffect(.pulse)
            
            VStack(spacing: 12) {
                Text("Ready to Sync")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Synchronize your wallet with the Dash blockchain to see your latest balance and transactions")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            Button(action: onStart) {
                Label("Start Sync", systemImage: "play.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

// MARK: - Legacy Progress Content

struct LegacyProgressContent: View {
    let progress: SwiftDashCoreSDK.SyncProgress
    
    // Convert SwiftDashCoreSDK.SyncStatus to local SyncStatus
    private var localStatus: SyncStatus {
        switch progress.status {
        case .connecting:
            return .connecting
        case .downloadingHeaders:
            return .downloadingHeaders
        case .synced:
            return .synced
        default:
            return .idle
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Status Icon
            Image(systemName: localStatus.icon)
                .font(.system(size: 60))
                .foregroundColor(localStatus.color)
                .symbolEffect(.pulse, isActive: localStatus.isActive)
            
            // Status Text
            Text(localStatus.description)
                .font(.title2)
                .fontWeight(.medium)
            
            // Progress Bar
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress.progress)
                    .progressViewStyle(.linear)
                
                HStack {
                    Text("\(progress.percentageComplete)%")
                        .monospacedDigit()
                    
                    Spacer()
                    
                    if let eta = progress.formattedTimeRemaining {
                        Text("ETA: \(eta)")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: 400)
            
            // Message
            if let message = progress.message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
}

// MARK: - Detailed Statistics View

struct DetailedStatisticsView: View {
    let statistics: [String: String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Detailed Statistics", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
                .padding(.bottom, 8)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(statistics.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(key)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(value)
                            .font(.body)
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(PlatformColor.tertiarySystemBackground))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(PlatformColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Helper Functions

private func formatDuration(from startTime: Date) -> String {
    let elapsed = Date().timeIntervalSince(startTime)
    let hours = Int(elapsed) / 3600
    let minutes = Int(elapsed.truncatingRemainder(dividingBy: 3600)) / 60
    let seconds = Int(elapsed.truncatingRemainder(dividingBy: 60))
    
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

struct EnhancedSyncProgressView_Previews: PreviewProvider {
    static var previews: some View {
        EnhancedSyncProgressView()
            .environmentObject(WalletService.shared)
    }
}