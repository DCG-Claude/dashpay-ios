import SwiftUI
import SwiftDashCoreSDK
import SwiftDashSDK

struct WatchStatusView: View {
    let status: WatchVerificationStatus
    
    var body: some View {
        HStack {
            switch status {
            case .unknown:
                EmptyView()
            case .verifying:
                ProgressView()
                    .scaleEffect(0.8)
                    .accessibilityLabel("Loading")
                    .accessibilityAddTraits(.updatesFrequently)
                Text("Verifying watched addresses...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Status: Verifying watched addresses")
            case .verified(let total, let watching):
                if total == watching {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .accessibilityLabel("Success")
                        .accessibilityAddTraits(.isStaticText)
                    Text("All \(total) addresses watched")
                        .font(.caption)
                        .accessibilityLabel("Status: All \(total) addresses successfully watched")
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .accessibilityLabel("Warning")
                        .accessibilityAddTraits(.isStaticText)
                    Text("\(watching)/\(total) addresses watched")
                        .font(.caption)
                        .accessibilityLabel("Status: \(watching) out of \(total) addresses watched, incomplete")
                }
            case .failed(let error):
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .accessibilityLabel("Error")
                    .accessibilityAddTraits(.isStaticText)
                Text("Verification failed: \(error)")
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .accessibilityLabel("Status: Verification failed with error: \(error)")
            }
        }
        .padding(.horizontal)
    }
}

struct WatchErrorsView: View {
    let errors: [WatchAddressError]
    let pendingCount: Int
    
    var body: some View {
        if !errors.isEmpty || pendingCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                if pendingCount > 0 {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.orange)
                            .accessibilityLabel("Pending")
                            .accessibilityAddTraits(.isStaticText)
                        Text("\(pendingCount) addresses pending retry")
                            .font(.caption)
                            .accessibilityLabel("Info: \(pendingCount) addresses pending retry")
                    }
                }
                
                ForEach(Array(errors.prefix(3).enumerated()), id: \.offset) { _, error in
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                            .accessibilityLabel("Error")
                            .accessibilityAddTraits(.isStaticText)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .lineLimit(2)
                            .accessibilityLabel("Error: \(error.localizedDescription)")
                    }
                }
                
                if errors.count > 3 {
                    Text("And \(errors.count - 3) more errors...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Info: And \(errors.count - 3) more errors not shown")
                }
            }
            .padding()
            .background(Color.red.opacity(0.3))
            .cornerRadius(8)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        WatchStatusView(status: .unknown)
        WatchStatusView(status: .verifying)
        WatchStatusView(status: .verified(total: 20, watching: 20))
        WatchStatusView(status: .verified(total: 20, watching: 15))
        WatchStatusView(status: .failed(error: "Network error"))
        
        WatchErrorsView(
            errors: [
                WatchAddressError.networkError("Connection timeout"),
                WatchAddressError.storageFailure("Disk full")
            ],
            pendingCount: 3
        )
    }
    .padding()
}