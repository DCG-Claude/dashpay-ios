import SwiftUI
import CoreImage.CIFilterBuiltins

struct EnhancedReceiveAddressView: View {
    @EnvironmentObject private var walletService: WalletService
    @Environment(\.dismiss) private var dismiss
    
    let account: HDAccount
    @State private var currentAddress: HDWatchedAddress?
    @State private var isCopied = false
    @State private var showNewAddressConfirm = false
    @State private var recentActivity: [RecentActivity] = []
    @State private var refreshTimer: Timer?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let address = currentAddress ?? account.receiveAddress {
                    // QR Code with Activity Indicator
                    VStack(spacing: 12) {
                        ZStack {
                            QRCodeView(content: address.address)
                                .frame(width: 200, height: 200)
                                .cornerRadius(12)
                            
                            // Activity indicator overlay
                            if hasRecentActivity(for: address) {
                                VStack {
                                    HStack {
                                        Spacer()
                                        ActivityIndicator()
                                            .frame(width: 30, height: 30)
                                    }
                                    Spacer()
                                }
                                .padding(8)
                            }
                        }
                        
                        // Activity status
                        if let lastActivity = address.lastActivityTimestamp {
                            HStack(spacing: 6) {
                                Image(systemName: "circle.fill")
                                    .foregroundColor(activityColor(for: lastActivity))
                                    .font(.caption)
                                
                                Text(formatActivityTime(lastActivity))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Address Display with Enhanced Info
                    VStack(spacing: 12) {
                        Text("Your Dash Address")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text(address.address)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            
                            Button(action: copyAddress) {
                                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                    .foregroundColor(isCopied ? .green : .accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        
                        // Enhanced Address Info
                        VStack(spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Derivation Path")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text(address.derivationPath)
                                        .font(.caption)
                                        .fontDesign(.monospaced)
                                        .foregroundColor(.primary)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Index")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text("\(address.index)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            Divider()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Status")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    HStack(spacing: 6) {
                                        if address.transactionIds.isEmpty {
                                            Image(systemName: "checkmark.shield")
                                                .foregroundColor(.green)
                                                .font(.caption)
                                            
                                            Text("Unused")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        } else {
                                            Image(systemName: "arrow.left.arrow.right")
                                                .foregroundColor(.orange)
                                                .font(.caption)
                                            
                                            Text("\(address.transactionIds.count) transactions")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Balance")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if let balance = address.balance {
                                        Text(balance.formattedTotal)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .monospacedDigit()
                                    } else {
                                        Text("0.00000000 DASH")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    
                    // Recent Activity Section
                    if !recentActivity.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent Activity")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            VStack(spacing: 6) {
                                ForEach(recentActivity.prefix(3), id: \.id) { activity in
                                    RecentActivityRow(activity: activity)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                    
                    Spacer()
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        // Test Address Button (for development)
                        if let testAddress = walletService.createTestReceiveAddress() {
                            Button("Create Test Address") {
                                print("🧪 Test address: \(testAddress)")
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        // Generate New Address Button
                        Button("Generate New Address") {
                            showNewAddressConfirm = true
                        }
                        .disabled(address.transactionIds.isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                    
                } else {
                    // No address available
                    VStack(spacing: 20) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No receive address available")
                            .font(.title3)
                        
                        Button("Generate Address") {
                            generateNewAddress()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
            .navigationTitle("Receive Dash")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: refreshActivity) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                setupActivityRefresh()
                loadRecentActivity()
            }
            .onDisappear {
                refreshTimer?.invalidate()
            }
        }
        #if os(macOS)
        .frame(width: 450, height: 700)
        #endif
        .alert("Generate New Address", isPresented: $showNewAddressConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Generate") {
                generateNewAddress()
            }
        } message: {
            Text("The current address has been used. Generate a new address for better privacy?")
        }
    }
    
    // MARK: - Helper Methods
    
    private func copyAddress() {
        guard let address = currentAddress ?? account.receiveAddress else { return }
        
        Clipboard.copy(address.address)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
    
    private func generateNewAddress() {
        do {
            let newAddress = try walletService.generateNewAddress(for: account, isChange: false)
            currentAddress = newAddress
            loadRecentActivity()
        } catch {
            print("Error generating address: \(error)")
        }
    }
    
    private func hasRecentActivity(for address: HDWatchedAddress) -> Bool {
        let (hasRecent, _) = walletService.getRecentActivityForAddress(address.address)
        return hasRecent
    }
    
    private func activityColor(for timestamp: Date) -> Color {
        let timeSince = Date().timeIntervalSince(timestamp)
        if timeSince < 300 { // 5 minutes
            return .green
        } else if timeSince < 3600 { // 1 hour
            return .orange
        } else {
            return .gray
        }
    }
    
    private func formatActivityTime(_ timestamp: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Last activity: " + formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    private func setupActivityRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            refreshActivity()
        }
    }
    
    private func refreshActivity() {
        loadRecentActivity()
    }
    
    private func loadRecentActivity() {
        guard let address = currentAddress ?? account.receiveAddress else { return }
        
        Task {
            do {
                // Get transactions for this specific address
                let transactions = try await walletService.sdk?.getTransactions(for: address.address, limit: 5) ?? []
                
                // Map SDK transactions to RecentActivity objects
                await MainActor.run {
                    recentActivity = transactions.map { transaction in
                        RecentActivity(
                            id: UUID(),
                            type: transaction.amount > 0 ? .received : .sent,
                            amount: transaction.amount,
                            timestamp: transaction.timestamp,
                            txid: transaction.txid
                        )
                    }
                }
            } catch {
                print("❌ Error loading recent activity for address \(address.address): \(error)")
                // Fall back to empty activity on error
                await MainActor.run {
                    recentActivity = []
                }
            }
        }
    }
}

// MARK: - Activity Indicator

struct ActivityIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 10, height: 10)
            .scaleEffect(isAnimating ? 1.5 : 1.0)
            .opacity(isAnimating ? 0.3 : 1.0)
            .animation(
                Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Recent Activity Row

struct RecentActivityRow: View {
    let activity: RecentActivity
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: activity.type.icon)
                .foregroundColor(activity.type.color)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.type.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(formatTime(activity.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(formatAmount(activity.amount))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(activity.type.amountColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
    
    private func formatTime(_ timestamp: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    private func formatAmount(_ amount: Int64) -> String {
        let dash = Double(amount) / 100_000_000
        return String(format: "%.8f DASH", dash)
    }
}

// MARK: - Supporting Types

struct RecentActivity: Identifiable {
    let id: UUID
    let type: ActivityType
    let amount: Int64
    let timestamp: Date
    let txid: String
}

enum ActivityType {
    case received
    case sent
    
    var icon: String {
        switch self {
        case .received: return "arrow.down.circle.fill"
        case .sent: return "arrow.up.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .received: return .green
        case .sent: return .blue
        }
    }
    
    var amountColor: Color {
        switch self {
        case .received: return .green
        case .sent: return .red
        }
    }
    
    var displayName: String {
        switch self {
        case .received: return "Received"
        case .sent: return "Sent"
        }
    }
}