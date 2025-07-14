import SwiftUI
import SwiftData
import SwiftDashCoreSDK

struct AccountDetailView: View {
    @EnvironmentObject private var walletService: WalletService
    @Environment(\.modelContext) private var modelContext
    
    let account: HDAccount
    @State private var selectedTab = 0
    @State private var showReceiveAddress = false
    @State private var showSendTransaction = false
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var showConnectionError = false
    @State private var showForceConnect = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Connection Status Banner
            if !walletService.isConnected {
                ConnectionBanner(
                    isConnecting: $isConnecting,
                    onConnect: { connectWallet() }
                )
            }
            
            // Debug button
            Button("Force Connect Test") {
                showForceConnect = true
            }
            .padding()
            
            // Account Header
            AccountHeaderView(
                account: account,
                onReceive: { showReceiveAddress = true },
                onSend: { showSendTransaction = true }
            )
            
            Divider()
            
            // Tab View
            TabView(selection: $selectedTab) {
                // Transactions Tab
                TransactionsTabView(account: account)
                    .tabItem {
                        Label("Transactions", systemImage: "list.bullet")
                    }
                    .tag(0)
                
                // Addresses Tab
                AddressesTabView(account: account)
                    .tabItem {
                        Label("Addresses", systemImage: "qrcode")
                    }
                    .tag(1)
                
                // UTXOs Tab
                UTXOsTabView(account: account)
                    .tabItem {
                        Label("UTXOs", systemImage: "bitcoinsign.circle")
                    }
                    .tag(2)
            }
        }
        .sheet(isPresented: $showReceiveAddress) {
            ReceiveAddressView(account: account)
        }
        .sheet(isPresented: $showSendTransaction) {
            SendTransactionView(account: account)
        }
        .alert("Connection Error", isPresented: $showConnectionError) {
            Button("OK") {
                showConnectionError = false
            }
        } message: {
            Text(connectionError ?? "Unknown error")
        }
    }
    
    private func connectWallet() {
        guard let wallet = account.wallet else { return }
        
        isConnecting = true
        Task {
            do {
                print("🔌 Connecting from AccountDetailView...")
                try await walletService.connect(wallet: wallet, account: account)
                print("✅ Connection successful!")
            } catch {
                print("❌ Connection error: \(error)")
                connectionError = "Connection Failed\n\nError: \(error.localizedDescription)\n\nType: \(type(of: error))"
                showConnectionError = true
            }
            isConnecting = false
        }
    }
}

// MARK: - Connection Banner

struct ConnectionBanner: View {
    @Binding var isConnecting: Bool
    let onConnect: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "wifi.slash")
                .foregroundColor(.orange)
            
            Text("Not Connected")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: onConnect) {
                if isConnecting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("Connect")
                        .font(.subheadline.bold())
                }
            }
            .disabled(isConnecting)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - Account Header View

struct AccountHeaderView: View {
    @EnvironmentObject private var walletService: WalletService
    let account: HDAccount
    let onReceive: () -> Void
    let onSend: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Account Info
            VStack(spacing: 8) {
                Text(account.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(account.derivationPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)
            }
            
            // Balance
            if let balance = account.balance {
                BalanceView(balance: balance)
            }
            
            // Mempool Status
            if walletService.mempoolTransactionCount > 0 {
                MempoolStatusView(count: walletService.mempoolTransactionCount)
            }
            
            // Watch Status - Removed during simplification
            // WatchStatusView(status: walletService.watchVerificationStatus)
            
            // Watch Errors - Removed during simplification
            // if !walletService.watchAddressErrors.isEmpty || walletService.pendingWatchCount > 0 {
            //     WatchErrorsView(
            //         errors: walletService.watchAddressErrors,
            //         pendingCount: walletService.pendingWatchCount
            //     )
            // }
            
            // Action Buttons
            HStack(spacing: 16) {
                Button(action: onReceive) {
                    Label("Receive", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: onSend) {
                    Label("Send", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(PlatformColor.controlBackground)
    }
}

// MARK: - Balance View

struct BalanceView: View {
    let balance: LocalBalance
    
    var body: some View {
        VStack(spacing: 8) {
            Text(formatDash(balance.total))
                .font(.system(size: 32, weight: .medium, design: .monospaced))
            
            HStack(spacing: 20) {
                BalanceComponent(
                    label: "Available",
                    amount: formatDash(balance.total),
                    color: .green
                )
                
                if balance.pending > 0 {
                    BalanceComponent(
                        label: "Pending",
                        amount: formatDash(balance.pending),
                        color: .orange
                    )
                }
                
                
            }
        }
    }
    
    private func formatDash(_ satoshis: UInt64) -> String {
        let dash = Double(satoshis) / 100_000_000.0
        return String(format: "%.8f", dash)
    }
}

struct BalanceComponent: View {
    let label: String
    let amount: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(amount)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

// MARK: - Transactions Tab

struct TransactionsTabView: View {
    let account: HDAccount
    @State private var searchText = ""
    @State private var transactions: [SwiftDashCoreSDK.Transaction] = []
    @State private var isLoading = true
    @State private var checkTimer: Timer?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var walletService: WalletService
    
    var filteredTransactions: [SwiftDashCoreSDK.Transaction] {
        if searchText.isEmpty {
            return transactions
        } else {
            return transactions.filter { transaction in
                transaction.txid.lowercased().contains(searchText.lowercased()) ||
                String(transaction.amount).contains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack {
            if account.transactionIds.isEmpty {
                AccountEmptyStateView(
                    icon: "list.bullet.rectangle",
                    title: "No Transactions",
                    message: "Transactions will appear here once you receive or send funds"
                )
            } else if isLoading {
                ProgressView("Loading transactions...")
                    .padding()
            } else if filteredTransactions.isEmpty && !searchText.isEmpty {
                AccountEmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results",
                    message: "No transactions match your search"
                )
            } else if filteredTransactions.isEmpty {
                AccountEmptyStateView(
                    icon: "list.bullet.rectangle",
                    title: "No Transactions Found",
                    message: "Unable to load transaction data"
                )
            } else {
                List {
                    ForEach(filteredTransactions) { transaction in
                        TransactionRowView(transaction: transaction)
                    }
                }
                .searchable(text: $searchText, prompt: "Search transactions")
            }
        }
        .task {
            await loadTransactions()
            // Also check for new transactions from the network
            await walletService.checkForNewTransactions()
            
            // Temporarily disabled periodic checking to debug
            // Set up periodic check every 10 seconds
            // checkTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            //     Task {
            //         await walletService.checkForNewTransactions()
            //         await loadTransactions()
            //     }
            // }
        }
        .onDisappear {
            checkTimer?.invalidate()
            checkTimer = nil
        }
        .refreshable {
            // Check for new transactions from the network first
            await walletService.checkForNewTransactions()
            // Then reload from SwiftData
            await loadTransactions()
        }
        .onChange(of: account.transactionIds) { _, _ in
            Task {
                await loadTransactions()
            }
        }
    }
    
    private func loadTransactions() async {
        isLoading = true
        transactions = await walletService.fetchTransactionsForAccount(account)
        isLoading = false
    }
}

// MARK: - Addresses Tab

struct AddressesTabView: View {
    @EnvironmentObject private var walletService: WalletService
    let account: HDAccount
    @State private var showingExternal = true
    
    var addresses: [HDWatchedAddress] {
        showingExternal ? account.externalAddresses : account.internalAddresses
    }
    
    var body: some View {
        VStack {
            // Address Type Picker
            Picker("Address Type", selection: $showingExternal) {
                Text("Receive").tag(true)
                Text("Change").tag(false)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            if addresses.isEmpty {
                AccountEmptyStateView(
                    icon: "qrcode",
                    title: "No Addresses",
                    message: "Generate addresses to receive funds"
                )
            } else {
                List {
                    ForEach(addresses) { address in
                        AddressRowView(address: address)
                    }
                }
            }
            
            // Generate New Address Button
            HStack {
                Spacer()
                Button("Generate New Address") {
                    generateNewAddress()
                }
                .padding()
            }
        }
    }
    
    private func generateNewAddress() {
        Task {
            do {
                _ = try walletService.generateNewAddress(
                    for: account,
                    isChange: !showingExternal
                )
            } catch {
                print("Error generating address: \(error)")
            }
        }
    }
}

// MARK: - UTXOs Tab

struct UTXOsTabView: View {
    let account: HDAccount
    @Environment(\.modelContext) private var modelContext
    
    var utxos: [SwiftDashCoreSDK.UTXO] {
        // TODO: Implement UTXO fetching from SDK
        // UTXO is not a SwiftData model, need to fetch from SDK
        return []
    }
    
    var totalValue: UInt64 {
        utxos.reduce(0) { $0 + $1.value }
    }
    
    var body: some View {
        VStack {
            if utxos.isEmpty {
                AccountEmptyStateView(
                    icon: "bitcoinsign.circle",
                    title: "No UTXOs",
                    message: "Unspent outputs will appear here"
                )
            } else {
                VStack {
                    // Summary
                    HStack {
                        Text("\(utxos.count) UTXOs")
                            .font(.headline)
                        Spacer()
                        Text("Total: \(formatDash(totalValue))")
                            .font(.headline)
                            .monospacedDigit()
                    }
                    .padding()
                    
                    // UTXO List
                    List {
                        ForEach(utxos.sorted { $0.value > $1.value }) { utxo in
                            UTXORowView(utxo: utxo)
                        }
                    }
                }
            }
        }
    }
    
    private func formatDash(_ satoshis: UInt64) -> String {
        let dash = Double(satoshis) / 100_000_000.0
        return String(format: "%.8f DASH", dash)
    }
}

// MARK: - Empty State View

struct AccountEmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.title3)
                .fontWeight(.medium)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row Views

struct TransactionRowView: View {
    let transaction: SwiftDashCoreSDK.Transaction
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: { showingDetail = true }) {
            HStack {
                // Direction Icon
                Image(systemName: transaction.amount >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundColor(transaction.amount >= 0 ? .green : .red)
                    .font(.title2)
                
                // Transaction Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.txid)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Text(transaction.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Amount and Status
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatAmount(transaction.amount))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(transaction.amount >= 0 ? .green : .red)
                    
                    if transaction.isInstantLocked {
                        Label("InstantSend", systemImage: "bolt.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    } else if transaction.confirmations > 0 {
                        Text("\(transaction.confirmations) conf")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Pending")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                
                // Chevron indicator
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .sheet(isPresented: $showingDetail) {
            TransactionDetailView(transaction: transaction)
        }
    }
    
    private func formatAmount(_ satoshis: Int64) -> String {
        let dash = Double(abs(satoshis)) / 100_000_000.0
        let sign = satoshis >= 0 ? "+" : "-"
        return "\(sign)\(String(format: "%.8f", dash))"
    }
}

struct AddressRowView: View {
    let address: HDWatchedAddress
    @State private var isCopied = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(address.address)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    if address.transactionIds.count > 0 {
                        Text("(\(address.transactionIds.count) tx)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("Index: \(address.index)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let balance = address.balance {
                Text(formatDash(balance.total))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            
            Button(action: copyAddress) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDash(_ satoshis: UInt64) -> String {
        let dash = Double(satoshis) / 100_000_000.0
        return String(format: "%.8f DASH", dash)
    }
    
    private func copyAddress() {
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
}

struct UTXORowView: View {
    let utxo: SwiftDashCoreSDK.UTXO
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(utxo.outpoint)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack {
                    Text("Height: \(utxo.height)")
                    Text("•")
                    Text("\(utxo.confirmations) conf")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(utxo.formattedValue)
                    .font(.system(.body, design: .monospaced))
                
                if utxo.isInstantLocked {
                    Text("InstantSend")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Mempool Status View

struct MempoolStatusView: View {
    let count: Int
    
    var body: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.purple)
            
            Text("\(count) unconfirmed transaction\(count == 1 ? "" : "s") in mempool")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.purple.opacity(0.1))
        .cornerRadius(8)
    }
}

