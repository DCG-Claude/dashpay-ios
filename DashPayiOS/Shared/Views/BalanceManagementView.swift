import SwiftUI
import Charts

struct BalanceManagementView: View {
    @EnvironmentObject var unifiedState: UnifiedStateManager
    @State private var selectedTimeframe: Timeframe = .day
    @State private var showingTransferView = false
    @State private var showingPortfolioDetails = false
    @State private var isRefreshing = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Portfolio Overview Card
                    PortfolioOverviewCard(unifiedState: unifiedState)
                    
                    // Portfolio Breakdown Chart
                    PortfolioBreakdownCard(
                        breakdown: unifiedState.unifiedBalance.portfolioBreakdown,
                        totalValue: unifiedState.unifiedBalance.totalInUSD
                    )
                    
                    // Balance Details
                    BalanceDetailsSection(unifiedState: unifiedState)
                    
                    // Portfolio Performance
                    PortfolioPerformanceCard(
                        selectedTimeframe: $selectedTimeframe,
                        unifiedState: unifiedState
                    )
                    
                    // Quick Actions
                    QuickActionsCard(showingTransferView: $showingTransferView)
                    
                    // Identity Management
                    IdentityManagementCard(unifiedState: unifiedState)
                }
                .padding()
            }
            .navigationTitle("Balance Management")
            .refreshable {
                await refreshData()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Transfer") {
                        showingTransferView = true
                    }
                }
            }
            .sheet(isPresented: $showingTransferView) {
                CrossLayerTransferView()
            }
            .sheet(isPresented: $showingPortfolioDetails) {
                // TODO: Implement PortfolioDetailsView
                Text("Portfolio Details")
                    .navigationTitle("Portfolio Details")
            }
        }
    }
    
    private func refreshData() async {
        isRefreshing = true
        await unifiedState.refreshAllData()
        isRefreshing = false
    }
}

// MARK: - Portfolio Overview Card

struct PortfolioOverviewCard: View {
    let unifiedState: UnifiedStateManager
    
    var body: some View {
        VStack(spacing: 16) {
            // Total Value
            VStack(spacing: 4) {
                Text("Total Portfolio Value")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text(unifiedState.unifiedBalance.formattedTotalUSD)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(unifiedState.unifiedBalance.formattedTotal)
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            // 24h Change
            HStack {
                let change = unifiedState.unifiedBalance.portfolioChange24h
                
                Image(systemName: change.isPositive ? "arrow.up.right" : "arrow.down.right")
                    .foregroundColor(Color(change.color))
                
                Text(change.formattedChangeUSD)
                    .fontWeight(.medium)
                    .foregroundColor(Color(change.color))
                
                Text("(\(change.formattedChangePercent))")
                    .foregroundColor(Color(change.color))
                
                Text("24h")
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
            
            // DASH Price
            HStack {
                Text("DASH Price:")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(unifiedState.unifiedBalance.priceData.formattedDashPrice)
                    .fontWeight(.medium)
                
                Text(unifiedState.unifiedBalance.priceData.formattedDashChange)
                    .foregroundColor(unifiedState.unifiedBalance.priceData.dashChange24h >= 0 ? .green : .red)
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

// MARK: - Portfolio Breakdown Card

struct PortfolioBreakdownCard: View {
    let breakdown: PortfolioBreakdown
    let totalValue: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Portfolio Breakdown")
                .font(.headline)
            
            if totalValue > 0 {
                // Pie Chart (iOS 16+ Chart API)
                Chart(portfolioData, id: \.category) { item in
                    SectorMark(
                        angle: .value("Value", item.percentage),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(item.color)
                    .opacity(0.8)
                }
                .frame(height: 200)
                
                // Legend
                VStack(spacing: 8) {
                    ForEach(portfolioData, id: \.category) { item in
                        HStack {
                            Circle()
                                .fill(item.color)
                                .frame(width: 12, height: 12)
                            
                            Text(item.category)
                                .font(.subheadline)
                            
                            Spacer()
                            
                            Text(item.formattedPercentage)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                }
            } else {
                Text("No portfolio data available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private var portfolioData: [PortfolioItem] {
        [
            PortfolioItem(
                category: "Core DASH",
                percentage: breakdown.corePercentage,
                color: .blue,
                formattedPercentage: breakdown.formattedCore
            ),
            PortfolioItem(
                category: "Platform Credits",
                percentage: breakdown.platformPercentage,
                color: .purple,
                formattedPercentage: breakdown.formattedPlatform
            ),
            PortfolioItem(
                category: "Tokens",
                percentage: breakdown.tokensPercentage,
                color: .orange,
                formattedPercentage: breakdown.formattedTokens
            )
        ].filter { $0.percentage > 0 }
    }
}

struct PortfolioItem {
    let category: String
    let percentage: Double
    let color: Color
    let formattedPercentage: String
}

// MARK: - Balance Details Section

struct BalanceDetailsSection: View {
    let unifiedState: UnifiedStateManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Balance Details")
                .font(.headline)
            
            VStack(spacing: 12) {
                // Core Balance
                BalanceRow(
                    icon: "bitcoinsign.circle.fill",
                    iconColor: .orange,
                    title: "Core DASH",
                    amount: unifiedState.unifiedBalance.formattedCoreBalance,
                    usdValue: unifiedState.unifiedBalance.formattedCoreBalanceUSD
                )
                
                Divider()
                
                // Platform Credits
                BalanceRow(
                    icon: "cloud.circle.fill",
                    iconColor: .purple,
                    title: "Platform Credits",
                    amount: unifiedState.unifiedBalance.formattedCredits,
                    usdValue: unifiedState.unifiedBalance.formattedCreditsUSD
                )
                
                // Token Balances
                if !unifiedState.unifiedBalance.tokenBalances.isEmpty {
                    Divider()
                    
                    ForEach(Array(unifiedState.unifiedBalance.tokenBalances.values), id: \.tokenId) { tokenBalance in
                        BalanceRow(
                            icon: "circle.grid.hex.fill",
                            iconColor: .green,
                            title: tokenBalance.symbol,
                            amount: tokenBalance.formattedBalance,
                            usdValue: tokenBalance.formattedUSDValue
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

struct BalanceRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let amount: String
    let usdValue: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(usdValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(amount)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Portfolio Performance Card

struct PortfolioPerformanceCard: View {
    @Binding var selectedTimeframe: Timeframe
    let unifiedState: UnifiedStateManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Portfolio Performance")
                    .font(.headline)
                
                Spacer()
                
                Picker("Timeframe", selection: $selectedTimeframe) {
                    ForEach(Timeframe.allCases, id: \.self) { timeframe in
                        Text(timeframe.displayName).tag(timeframe)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            
            // Performance chart would go here
            if let historyService = unifiedState.getTransactionHistory() {
                Text("Portfolio history chart would be displayed here")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                Text("Loading portfolio data...")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

// MARK: - Quick Actions Card

struct QuickActionsCard: View {
    @Binding var showingTransferView: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ActionButton(
                    title: "Cross-Layer Transfer",
                    icon: "arrow.left.arrow.right.circle",
                    color: .blue
                ) {
                    showingTransferView = true
                }
                
                ActionButton(
                    title: "Create Identity",
                    icon: "person.badge.plus",
                    color: .purple
                ) {
                    // TODO: Handle identity creation
                }
                
                ActionButton(
                    title: "Batch Operations",
                    icon: "square.stack.3d.up",
                    color: .orange
                ) {
                    // TODO: Handle batch operations
                }
                
                ActionButton(
                    title: "Sync Balances",
                    icon: "arrow.clockwise.circle",
                    color: .green
                ) {
                    // TODO: Handle balance sync
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

struct ActionButton: View {
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
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Identity Management Card

struct IdentityManagementCard: View {
    let unifiedState: UnifiedStateManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Platform Identities")
                .font(.headline)
            
            if unifiedState.identities.isEmpty {
                Text("No identities created yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(unifiedState.identities, id: \.id) { identity in
                    BalanceIdentityRow(identity: identity)
                    
                    if identity.id != unifiedState.identities.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

struct BalanceIdentityRow: View {
    let identity: Identity
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .foregroundColor(.purple)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(identity.id.prefix(16) + "...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(identity.balance) credits")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Manage") {
                // TODO: Handle identity management
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Supporting Types

enum Timeframe: CaseIterable {
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
    
    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }
}