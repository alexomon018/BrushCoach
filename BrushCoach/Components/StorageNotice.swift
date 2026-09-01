import SwiftUI

/// Says out loud that saving went wrong.
///
/// The app is careful to report an uncertain motion reading as "couldn't check"
/// rather than as zero. Persistence deserves the same treatment: a brush that
/// failed to save, or history running on fallback storage, used to be recorded
/// only in a property nothing displayed.
struct StorageNotice: View {
    let message: String
    /// Fallback storage is a degraded-but-working state, not a failure. It reads
    /// as a caution; a failed write reads as an error.
    var isDegradedRatherThanFailed = false

    private var tint: Color { isDegradedRatherThanFailed ? .achievementGold : .coachCoral }

    private var symbol: String {
        isDegradedRatherThanFailed ? "exclamationmark.triangle.fill" : "xmark.octagon.fill"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(isDegradedRatherThanFailed ? "Using backup storage" : "Couldn't save")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.deepInk)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.1))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.3), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
