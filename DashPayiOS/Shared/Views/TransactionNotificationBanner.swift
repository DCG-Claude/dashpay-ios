import SwiftUI
import Combine

/// A banner that shows notifications for incoming transactions
struct TransactionNotificationBanner: View {
    let notification: TransactionNotification
    @Binding var isVisible: Bool
    
    @State private var offset: CGFloat = -100
    @State private var opacity: Double = 0
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: notification.type.icon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(notification.type.color)
                    .clipShape(Circle())
                
                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(notification.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(notification.message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Amount
                VStack(alignment: .trailing, spacing: 2) {
                    Text(notification.amountText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(notification.type.amountColor)
                    
                    if let status = notification.status {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Dismiss button
                Button(action: {
                    dismissBanner()
                }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal)
            
            Spacer()
        }
        .offset(y: offset)
        .opacity(opacity)
        .onAppear {
            showBanner()
            
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if isVisible {
                    dismissBanner()
                }
            }
        }
        .onTapGesture {
            // Allow tapping to dismiss early
            dismissBanner()
        }
    }
    
    private func showBanner() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            offset = 0
            opacity = 1
        }
    }
    
    private func dismissBanner() {
        withAnimation(.easeOut(duration: 0.3)) {
            offset = -100
            opacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isVisible = false
        }
    }
}

// MARK: - Transaction Notification Model

struct TransactionNotification: Identifiable {
    let id = UUID()
    let type: TransactionNotificationType
    let title: String
    let message: String
    let amountText: String
    let status: String?
    let txid: String
    let timestamp: Date
    
    static func fundsReceived(amount: Int64, txid: String, confirmed: Bool) -> TransactionNotification {
        let dashAmount = Double(amount) / 100_000_000
        let amountText = String(format: "+%.8g DASH", dashAmount)
        let statusText = confirmed ? "Confirmed" : "Unconfirmed"
        
        return TransactionNotification(
            type: .received,
            title: "Funds Received",
            message: "New transaction detected",
            amountText: amountText,
            status: statusText,
            txid: txid,
            timestamp: Date()
        )
    }
    
    static func transactionConfirmed(txid: String, amount: Int64) -> TransactionNotification {
        let dashAmount = Double(amount) / 100_000_000
        let amountText = String(format: "%.8g DASH", dashAmount)
        
        return TransactionNotification(
            type: .confirmed,
            title: "Transaction Confirmed",
            message: "Transaction has been confirmed",
            amountText: amountText,
            status: "Confirmed",
            txid: txid,
            timestamp: Date()
        )
    }
}

enum TransactionNotificationType {
    case received
    case sent
    case confirmed
    
    var icon: String {
        switch self {
        case .received:
            return "arrow.down.circle.fill"
        case .sent:
            return "arrow.up.circle.fill"
        case .confirmed:
            return "checkmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .received:
            return .green
        case .sent:
            return .blue
        case .confirmed:
            return .orange
        }
    }
    
    var amountColor: Color {
        switch self {
        case .received:
            return .green
        case .sent:
            return .red
        case .confirmed:
            return .primary
        }
    }
}

// MARK: - Transaction Notification Manager

@MainActor
class TransactionNotificationManager: ObservableObject {
    @Published var currentNotification: TransactionNotification?
    @Published var isShowingNotification = false
    
    private var notificationQueue: [TransactionNotification] = []
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        // Listen for funds received notifications
        NotificationCenter.default
            .publisher(for: NSNotification.Name("FundsReceived"))
            .sink { [weak self] notification in
                guard let userInfo = notification.userInfo,
                      let amount = userInfo["amount"] as? Int64,
                      let txid = userInfo["txid"] as? String,
                      let confirmed = userInfo["confirmed"] as? Bool else {
                    return
                }
                
                let transactionNotification = TransactionNotification.fundsReceived(
                    amount: amount,
                    txid: txid,
                    confirmed: confirmed
                )
                
                self?.showNotification(transactionNotification)
            }
            .store(in: &cancellables)
        
        // Listen for balance updates
        NotificationCenter.default
            .publisher(for: NSNotification.Name("BalanceUpdated"))
            .sink { [weak self] notification in
                // Could show balance update notifications here if desired
                print("💰 Balance update notification received")
            }
            .store(in: &cancellables)
    }
    
    func showNotification(_ notification: TransactionNotification) {
        // Add to queue if another notification is currently showing
        if isShowingNotification {
            notificationQueue.append(notification)
            return
        }
        
        currentNotification = notification
        isShowingNotification = true
        
        // When current notification is dismissed, show next in queue
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
            self.processNotificationQueue()
        }
    }
    
    func dismissCurrentNotification() {
        isShowingNotification = false
        currentNotification = nil
        
        // Process queue after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.processNotificationQueue()
        }
    }
    
    private func processNotificationQueue() {
        guard !notificationQueue.isEmpty, !isShowingNotification else { return }
        
        let nextNotification = notificationQueue.removeFirst()
        showNotification(nextNotification)
    }
}

// MARK: - Notification Overlay

struct TransactionNotificationOverlay: View {
    @StateObject private var notificationManager = TransactionNotificationManager()
    
    var body: some View {
        ZStack {
            if notificationManager.isShowingNotification,
               let notification = notificationManager.currentNotification {
                TransactionNotificationBanner(
                    notification: notification,
                    isVisible: $notificationManager.isShowingNotification
                )
                .zIndex(1000)
            }
        }
        .allowsHitTesting(notificationManager.isShowingNotification)
    }
}