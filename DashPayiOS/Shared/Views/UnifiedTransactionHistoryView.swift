import SwiftUI
import SwiftDashCoreSDK

struct UnifiedTransactionHistoryView: View {
    @EnvironmentObject var unifiedState: UnifiedStateManager
    @StateObject private var historyService: UnifiedTransactionHistoryService
    
    @State private var selectedFilter: TransactionFilter = .all
    @State private var selectedDateRange: DateRange = .week
    @State private var searchText = ""
    @State private var showingFilterOptions = false
    
    init() {
        // Initialize with placeholder service - will be updated when view appears
        self._historyService = StateObject(wrappedValue: UnifiedTransactionHistoryService(
            coreSDK: MockDashSDK(),
            platformWrapper: nil,
            tokenService: TokenService()
        ))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter Bar
                FilterBar(
                    selectedFilter: $selectedFilter,
                    selectedDateRange: $selectedDateRange,
                    showingFilterOptions: $showingFilterOptions
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                // Transaction List
                if historyService.isLoading {
                    ProgressView("Loading transactions...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredTransactions.isEmpty {
                    EmptyTransactionView(filter: selectedFilter)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(groupedTransactions.keys.sorted(by: >), id: \.self) { date in
                            Section(formatDateHeader(date)) {
                                ForEach(groupedTransactions[date] ?? [], id: \.id) { transaction in
                                    TransactionRow(transaction: transaction)
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Search transactions...")
                }
            }
            .navigationTitle("Transaction History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Filter") {
                        showingFilterOptions = true
                    }
                }
            }
            .refreshable {
                await historyService.refreshAllTransactions()
            }
            .sheet(isPresented: $showingFilterOptions) {
                FilterOptionsView(
                    selectedFilter: $selectedFilter,
                    selectedDateRange: $selectedDateRange
                )
            }
            .onAppear {
                // Update history service with actual dependencies
                if let actualService = unifiedState.getTransactionHistory() {
                    // In a real implementation, we'd need a way to update the service
                    // For now, trigger a refresh
                    Task {
                        await historyService.refreshAllTransactions()
                    }
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredTransactions: [UnifiedTransaction] {
        var transactions = historyService.transactions
        
        // Apply type filter
        if selectedFilter != .all {
            transactions = transactions.filter { transaction in
                switch selectedFilter {
                case .all:
                    return true
                case .core:
                    return transaction.type == .coreTransaction
                case .platform:
                    return transaction.type == .identityCreation || transaction.type == .creditTransfer
                case .tokens:
                    return transaction.type == .tokenTransfer
                case .sent:
                    return transaction.direction == .sent
                case .received:
                    return transaction.direction == .received
                }
            }
        }
        
        // Apply date range filter
        let dateRange = selectedDateRange.dateRange
        transactions = historyService.getTransactions(from: dateRange.start, to: dateRange.end)
        
        // Apply search filter
        if !searchText.isEmpty {
            transactions = transactions.filter { transaction in
                transaction.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                transaction.txid.localizedCaseInsensitiveContains(searchText) ||
                (transaction.fromAddress?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (transaction.toAddress?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        return transactions
    }
    
    private var groupedTransactions: [Date: [UnifiedTransaction]] {
        Dictionary(grouping: filteredTransactions) { transaction in
            Calendar.current.startOfDay(for: transaction.timestamp)
        }
    }
    
    private func formatDateHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            formatter.dateFormat = "MMMM d"
        } else {
            formatter.dateFormat = "MMMM d, yyyy"
        }
        
        return formatter.string(from: date)
    }
}

// MARK: - Filter Bar

struct FilterBar: View {
    @Binding var selectedFilter: TransactionFilter
    @Binding var selectedDateRange: DateRange
    @Binding var showingFilterOptions: Bool
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(TransactionFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.displayName,
                        isSelected: selectedFilter == filter
                    ) {
                        selectedFilter = filter
                    }
                }
                
                Divider()
                    .frame(height: 20)
                
                ForEach(DateRange.allCases, id: \.self) { range in
                    FilterChip(
                        title: range.displayName,
                        isSelected: selectedDateRange == range
                    ) {
                        selectedDateRange = range
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected ? Color.accentColor : Color(.systemGray5))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Transaction Row

struct TransactionRow: View {
    let transaction: UnifiedTransaction
    @State private var showingDetails = false
    
    var body: some View {
        Button(action: { showingDetails = true }) {
            HStack(spacing: 12) {
                // Transaction Icon
                Image(systemName: transaction.type.icon)
                    .foregroundColor(Color(transaction.direction.color))
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(Color(transaction.direction.color).opacity(0.1))
                    .clipShape(Circle())
                
                // Transaction Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    HStack {
                        Text(formatTime(transaction.timestamp))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(transaction.status.displayName)
                            .font(.caption)
                            .foregroundColor(Color(transaction.status.color))
                    }
                }
                
                Spacer()
                
                // Amount and USD Value
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        if transaction.direction == .sent {
                            Text("-")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                        } else if transaction.direction == .received {
                            Text("+")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                        
                        Text(transaction.formattedAmount)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    
                    Text(transaction.formattedUSDValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetails) {
            TransactionDetailSheet(transaction: transaction)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Empty State

struct EmptyTransactionView: View {
    let filter: TransactionFilter
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No transactions found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("No \(filter.displayName.lowercased()) transactions for the selected period")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Transaction Detail Sheet

struct TransactionDetailSheet: View {
    let transaction: UnifiedTransaction
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: transaction.type.icon)
                            .font(.system(size: 40))
                            .foregroundColor(Color(transaction.direction.color))
                        
                        Text(transaction.displayTitle)
                            .font(.headline)
                        
                        Text(transaction.formattedAmount)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(transaction.formattedUSDValue)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                    
                    // Details
                    VStack(spacing: 16) {
                        DetailRow(label: "Status", value: transaction.status.displayName)
                        DetailRow(label: "Date", value: formatFullDate(transaction.timestamp))
                        DetailRow(label: "Transaction ID", value: transaction.txid)
                        
                        if let fromAddress = transaction.fromAddress {
                            DetailRow(label: "From", value: fromAddress)
                        }
                        
                        if let toAddress = transaction.toAddress {
                            DetailRow(label: "To", value: toAddress)
                        }
                        
                        DetailRow(label: "Confirmations", value: "\(transaction.confirmations)")
                        DetailRow(label: "Fee", value: formatFee(transaction.fee))
                        
                        // Metadata specific to transaction type
                        if let coreMetadata = transaction.metadata as? CoreTransactionMetadata {
                            DetailRow(label: "InstantSend", value: coreMetadata.isInstantSend ? "Yes" : "No")
                            if let blockHeight = coreMetadata.blockHeight {
                                DetailRow(label: "Block Height", value: "\(blockHeight)")
                            }
                        } else if let platformMetadata = transaction.metadata as? PlatformTransactionMetadata {
                            DetailRow(label: "Identity ID", value: platformMetadata.identityId)
                            DetailRow(label: "Operation", value: platformMetadata.operation)
                            DetailRow(label: "Credits Used", value: "\(platformMetadata.creditsUsed)")
                        } else if let tokenMetadata = transaction.metadata as? TokenTransactionMetadata {
                            DetailRow(label: "Token", value: tokenMetadata.tokenName)
                            DetailRow(label: "Contract ID", value: tokenMetadata.tokenContractId)
                            if let fromId = tokenMetadata.fromIdentityId {
                                DetailRow(label: "From Identity", value: fromId)
                            }
                            if let toId = tokenMetadata.toIdentityId {
                                DetailRow(label: "To Identity", value: toId)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Transaction Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatFee(_ fee: UInt64) -> String {
        let dashFee = Double(fee) / 100_000_000
        return String(format: "%.8f DASH", dashFee)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Filter Options Sheet

struct FilterOptionsView: View {
    @Binding var selectedFilter: TransactionFilter
    @Binding var selectedDateRange: DateRange
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction Type") {
                    ForEach(TransactionFilter.allCases, id: \.self) { filter in
                        HStack {
                            Text(filter.displayName)
                            Spacer()
                            if selectedFilter == filter {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFilter = filter
                        }
                    }
                }
                
                Section("Date Range") {
                    ForEach(DateRange.allCases, id: \.self) { range in
                        HStack {
                            Text(range.displayName)
                            Spacer()
                            if selectedDateRange == range {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedDateRange = range
                        }
                    }
                }
            }
            .navigationTitle("Filter Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

enum TransactionFilter: CaseIterable {
    case all
    case core
    case platform
    case tokens
    case sent
    case received
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .core: return "Core"
        case .platform: return "Platform"
        case .tokens: return "Tokens"
        case .sent: return "Sent"
        case .received: return "Received"
        }
    }
}

enum DateRange: CaseIterable {
    case day
    case week
    case month
    case year
    case all
    
    var displayName: String {
        switch self {
        case .day: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        case .year: return "This Year"
        case .all: return "All Time"
        }
    }
    
    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let endOfDay = calendar.dateInterval(of: .day, for: now)?.end ?? now
        
        switch self {
        case .day:
            let startOfDay = calendar.startOfDay(for: now)
            return (startOfDay, endOfDay)
        case .week:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (startOfWeek, endOfDay)
        case .month:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return (startOfMonth, endOfDay)
        case .year:
            let startOfYear = calendar.dateInterval(of: .year, for: now)?.start ?? now
            return (startOfYear, endOfDay)
        case .all:
            return (Date.distantPast, endOfDay)
        }
    }
}

// MARK: - Mock Implementation

struct MockDashSDK: DashSDKProtocol {
    func createTransaction(to: String, amount: UInt64, isAssetLock: Bool) async throws -> SwiftDashCoreSDK.Transaction {
        // Return the SDK Transaction type
        return SwiftDashCoreSDK.Transaction(
            txid: "mock",
            amount: Int64(amount)
        )
    }
    
    func createAssetLockTransaction(amount: UInt64) async throws -> SwiftDashCoreSDK.Transaction {
        return SwiftDashCoreSDK.Transaction(
            txid: "mock_asset_lock",
            amount: Int64(amount)
        )
    }
    
    func broadcastTransaction(_ tx: SwiftDashCoreSDK.Transaction) async throws -> String {
        return tx.txid
    }
    
    func getInstantLock(for txid: String) async throws -> InstantLock? {
        return nil
    }
    
    func waitForInstantLockResult(txid: String, timeout: TimeInterval) async throws -> InstantLock {
        return InstantLock(txid: txid, height: 0, signature: Data())
    }
}

// Mock transaction types for testing
struct MockAssetLockTransaction {
    let txid: String
    let outputs: [MockTransactionOutput]
    let amount: Int64
    var fee: Int64? { 250_000 }
}

struct MockTransactionOutput {
    let amount: UInt64
    let script: Data
}