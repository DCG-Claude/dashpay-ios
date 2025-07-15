import SwiftUI
import Charts
import SwiftDashSDK

struct UnifiedDashboardView: View {
    @EnvironmentObject var unifiedState: UnifiedStateManager
    @EnvironmentObject var walletService: WalletService
    
    @State private var showingTransferView = false
    @State private var showingBalanceManagement = false
    @State private var showingTransactionHistory = false
    @State private var selectedTimeframe: PortfolioTimeframe = .day
    @State private var showingEnhancedReceiveView = false
    
    var body: some View {
        ZStack {
            NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Enhanced Portfolio Overview
                    EnhancedPortfolioCard(
                        balance: unifiedState.unifiedBalance,
                        selectedTimeframe: $selectedTimeframe
                    )
                    
                    // Portfolio Breakdown Chart
                    PortfolioBreakdownSection(breakdown: unifiedState.unifiedBalance.portfolioBreakdown)
                    
                    // Cross-Layer Quick Actions
                    CrossLayerQuickActions(
                        showingTransferView: $showingTransferView,
                        showingBalanceManagement: $showingBalanceManagement,
                        unifiedState: unifiedState
                    )
                    
                    // Network Status with Enhanced Info
                    EnhancedSyncStatusCard(
                        coreProgress: walletService.detailedSyncProgress,
                        platformSynced: unifiedState.isPlatformSynced,
                        lastSyncTime: Date() // TODO: Get actual last sync time
                    )
                    
                    // Recent Cross-Layer Activity
                    RecentCrossLayerActivity(
                        transactionHistory: unifiedState.getTransactionHistory(),
                        showingTransactionHistory: $showingTransactionHistory
                    )
                    
                    // Platform Identities Overview
                    PlatformIdentitiesOverview(identities: unifiedState.identities)
                    
                    // Token Portfolio (if any tokens)
                    if !unifiedState.unifiedBalance.tokenBalances.isEmpty {
                        TokenPortfolioSection(tokenBalances: unifiedState.unifiedBalance.tokenBalances)
                    }
                }
                .padding()
            }
            .navigationTitle("DashPay")
            .refreshable {
                await refreshAllData()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Balance Management") {
                            showingBalanceManagement = true
                        }
                        
                        Button("Transaction History") {
                            showingTransactionHistory = true
                        }
                        
                        Button("Enhanced Receive Address") {
                            showingEnhancedReceiveView = true
                        }
                        
                        Button("Cross-Layer Transfer") {
                            showingTransferView = true
                        }
                        
                        Divider()
                        
                        Button("Refresh All") {
                            Task {
                                await refreshAllData()
                            }
                        }
                        
                        Divider()
                        
                        Button("🧪 Test Receiving Funds") {
                            Task {
                                await walletService.testReceivingFundsDetection()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingTransferView) {
                CrossLayerTransferView()
            }
            .sheet(isPresented: $showingBalanceManagement) {
                BalanceManagementView()
            }
            .sheet(isPresented: $showingTransactionHistory) {
                UnifiedTransactionHistoryView()
            }
            // .sheet(isPresented: $showingEnhancedReceiveView) {
            //     if let account = walletService.activeAccount {
            //         EnhancedReceiveAddressView(account: account)
            //     }
            // }
            }
            
            // Transaction notification overlay
            // TransactionNotificationOverlay()
        }
    }
    
    private func refreshAllData() async {
        await unifiedState.refreshAllData()
    }
}

// MARK: - Enhanced Portfolio Card

struct EnhancedPortfolioCard: View {
    let balance: UnifiedBalance
    @Binding var selectedTimeframe: PortfolioTimeframe
    
    var body: some View {
        VStack(spacing: 16) {
            // Total Portfolio Value
            VStack(spacing: 8) {
                Text("Total Portfolio Value")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 4) {
                    Text(balance.formattedTotalUSD)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(balance.formattedTotal)
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                
                // 24h Change
                HStack(spacing: 8) {
                    let change = balance.portfolioChange24h
                    
                    Image(systemName: change.isPositive ? "arrow.up.right" : "arrow.down.right")
                        .foregroundColor(Color(change.color))
                        .font(.caption)
                    
                    Text(change.formattedChangeUSD)
                        .fontWeight(.medium)
                        .foregroundColor(Color(change.color))
                    
                    Text("(\(change.formattedChangePercent))")
                        .foregroundColor(Color(change.color))
                    
                    Text("24h")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
            }
            
            // DASH Price Info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DASH Price")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Text(balance.priceData.formattedDashPrice)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(balance.priceData.formattedDashChange)
                            .font(.caption)
                            .foregroundColor(balance.priceData.dashChange24h >= 0 ? .green : .red)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Last Updated")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(formatLastUpdated(balance.priceData.lastUpdated))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
        )
    }
    
    private func formatLastUpdated(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Portfolio Breakdown Section

struct PortfolioBreakdownSection: View {
    let breakdown: PortfolioBreakdown
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Portfolio Breakdown")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                BreakdownRow(
                    icon: "bitcoinsign.circle.fill",
                    iconColor: .orange,
                    title: "Core DASH",
                    percentage: breakdown.formattedCore
                )
                
                BreakdownRow(
                    icon: "cloud.circle.fill",
                    iconColor: .purple,
                    title: "Platform Credits",
                    percentage: breakdown.formattedPlatform
                )
                
                if breakdown.tokensPercentage > 0 {
                    BreakdownRow(
                        icon: "circle.grid.hex.fill",
                        iconColor: .green,
                        title: "Tokens",
                        percentage: breakdown.formattedTokens
                    )
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

struct BreakdownRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let percentage: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Text(percentage)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Cross-Layer Quick Actions

struct CrossLayerQuickActions: View {
    @Binding var showingTransferView: Bool
    @Binding var showingBalanceManagement: Bool
    let unifiedState: UnifiedStateManager
    
    @State private var showingIdentityCreation = false
    @State private var isSync = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .padding(.horizontal)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                CrossLayerActionButton(
                    title: "Cross-Layer Transfer",
                    subtitle: "Move funds between layers",
                    icon: "arrow.left.arrow.right.circle",
                    color: .blue
                ) {
                    showingTransferView = true
                }
                
                CrossLayerActionButton(
                    title: "Create Identity",
                    subtitle: "Fund new Platform identity",
                    icon: "person.badge.plus",
                    color: .purple
                ) {
                    showingIdentityCreation = true
                }
                
                CrossLayerActionButton(
                    title: "Balance Management",
                    subtitle: "View portfolio details",
                    icon: "chart.pie",
                    color: .orange
                ) {
                    showingBalanceManagement = true
                }
                
                CrossLayerActionButton(
                    title: "Sync All",
                    subtitle: "Refresh all balances",
                    icon: isSync ? "arrow.clockwise.circle" : "arrow.clockwise.circle.fill",
                    color: .green
                ) {
                    Task {
                        isSync = true
                        await unifiedState.refreshAllData()
                        isSync = false
                    }
                }
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showingIdentityCreation) {
            CreateIdentityView()
        }
    }
}

struct CrossLayerActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                    
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
            }
            .padding()
            .frame(height: 80)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SyncStatusCard: View {
    let coreProgress: DetailedSyncProgress?
    let platformSynced: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Core sync status
            HStack {
                Image(systemName: "link.circle.fill")
                    .foregroundColor(coreProgress != nil ? .green : .gray)
                
                Text("Core Network")
                    .font(.subheadline)
                
                Spacer()
                
                if let progress = coreProgress {
                    Text("\(Int(progress.percentage))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let progress = coreProgress {
                ProgressView(value: progress.percentage / 100.0)
                
                Text(progress.stageMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Platform sync status
            HStack {
                Image(systemName: "cloud.fill")
                    .foregroundColor(platformSynced ? .green : .gray)
                
                Text("Platform Network")
                    .font(.subheadline)
                
                Spacer()
                
                Text(platformSynced ? "Synced" : "Offline")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Enhanced Sync Status Card

struct EnhancedSyncStatusCard: View {
    let coreProgress: DetailedSyncProgress?
    let platformSynced: Bool
    let lastSyncTime: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Network Status")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                // Core sync status
                HStack {
                    Image(systemName: "link.circle.fill")
                        .foregroundColor(coreProgress != nil ? .green : .gray)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Core Network")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if let progress = coreProgress {
                            Text(progress.stageMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Connecting...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if let progress = coreProgress {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(progress.percentage))%")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            ProgressView(value: progress.percentage / 100.0)
                                .frame(width: 60)
                        }
                    }
                }
                
                Divider()
                
                // Platform sync status
                HStack {
                    Image(systemName: "cloud.fill")
                        .foregroundColor(platformSynced ? .green : .gray)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Platform Network")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(platformSynced ? "Connected" : "Offline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(platformSynced ? "Synced" : "Offline")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(platformSynced ? .green : .secondary)
                        
                        Text(formatRelativeTime(lastSyncTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Recent Cross-Layer Activity

struct RecentCrossLayerActivity: View {
    let transactionHistory: UnifiedTransactionHistoryService?
    @Binding var showingTransactionHistory: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                
                Spacer()
                
                Button("View All") {
                    showingTransactionHistory = true
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal)
            
            VStack(spacing: 0) {
                if let recentTransactions = transactionHistory?.transactions.prefix(3) {
                    ForEach(Array(recentTransactions), id: \.id) { transaction in
                        UnifiedRecentActivityRow(transaction: transaction)
                        
                        if transaction.id != recentTransactions.last?.id {
                            Divider()
                                .padding(.leading, 50)
                        }
                    }
                } else {
                    Text("No recent activity")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

struct UnifiedRecentActivityRow: View {
    let transaction: UnifiedTransaction
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.type.icon)
                .foregroundColor(Color(transaction.direction.color))
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(formatTime(transaction.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(transaction.formattedAmount)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(transaction.formattedUSDValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Platform Identities Overview

struct PlatformIdentitiesOverview: View {
    let identities: [Identity]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Platform Identities")
                    .font(.headline)
                
                Spacer()
                
                Text("\(identities.count) identities")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            if identities.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("No identities created yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Create an identity to access Platform features")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(identities.prefix(3), id: \.id) { identity in
                        IdentityOverviewRow(identity: identity)
                        
                        if identity.id != identities.prefix(3).last?.id {
                            Divider()
                        }
                    }
                    
                    if identities.count > 3 {
                        Text("+ \(identities.count - 3) more identities")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
}

struct IdentityOverviewRow: View {
    let identity: Identity
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .foregroundColor(.purple)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(identity.idString.prefix(16) + "...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Revision \(identity.revision)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(identity.balance)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("credits")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Token Portfolio Section

struct TokenPortfolioSection: View {
    let tokenBalances: [String: TokenBalance]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Token Portfolio")
                    .font(.headline)
                
                Spacer()
                
                Text("\(tokenBalances.count) tokens")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            VStack(spacing: 8) {
                ForEach(Array(tokenBalances.values.prefix(3)), id: \.tokenId) { tokenBalance in
                    TokenBalanceRow(tokenBalance: tokenBalance)
                    
                    if tokenBalance.tokenId != Array(tokenBalances.values.prefix(3)).last?.tokenId {
                        Divider()
                    }
                }
                
                if tokenBalances.count > 3 {
                    Text("+ \(tokenBalances.count - 3) more tokens")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

struct TokenBalanceRow: View {
    let tokenBalance: TokenBalance
    
    var body: some View {
        HStack {
            Image(systemName: "circle.grid.hex.fill")
                .foregroundColor(.green)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(tokenBalance.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(tokenBalance.symbol)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(tokenBalance.formattedBalance)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(tokenBalance.formattedUSDValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Supporting Types

enum PortfolioTimeframe: CaseIterable {
    case day
    case week
    case month
    case year
    
    var displayName: String {
        switch self {
        case .day: return "1D"
        case .week: return "1W"
        case .month: return "1M"
        case .year: return "1Y"
        }
    }
}