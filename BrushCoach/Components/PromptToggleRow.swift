import SwiftUI

struct PromptToggleRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: CompanionMetrics.rowSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: CompanionMetrics.rowIconSize, height: CompanionMetrics.rowIconSize)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.deepInk)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.mintDeep)
        }
        .frame(minHeight: 52)
        .sensoryFeedback(.selection, trigger: isOn)
    }
}
