import SwiftUI

struct ResourceRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: CompanionMetrics.rowSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.rinseBlue)
                .frame(width: CompanionMetrics.rowIconSize, height: CompanionMetrics.rowIconSize)
                .background(Color.rinseBlue.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(Color.deepInk)
                Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .companionCard()
    }
}
