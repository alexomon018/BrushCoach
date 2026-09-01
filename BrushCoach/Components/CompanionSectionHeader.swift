import SwiftUI

struct CompanionSectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.companionEyebrow)
                .tracking(1.35)
                .foregroundStyle(Color.rinseBlue)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Keeps a section heading and its contents on the same vertical rhythm. This
/// replaces screen-specific top padding and one-off header-to-card gaps.
struct CompanionSection<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    init(title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CompanionSectionHeader(title: title, detail: detail)
            content
        }
    }
}
