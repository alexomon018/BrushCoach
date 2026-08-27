import SwiftUI

struct DentalArchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    let completedZones: Int
    var dark = false

    private static let barHeights: [CGFloat] = [46, 68, 82, 82, 68, 46]

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(Array(Self.barHeights.enumerated()), id: \.offset) { index, height in
                bar(index: index, height: height)
            }
        }
        .onAppear { revealed = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completedZones) of 6 zones complete")
    }

    private func bar(index: Int, height: CGFloat) -> some View {
        let completed = index < completedZones
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(completed ? Color.mintFresh : (dark ? .white.opacity(0.14) : Color.rinseBlue.opacity(0.12)))
            .frame(height: height)
            .scaleEffect(y: revealed ? 1 : 0.25, anchor: .bottom)
            .opacity(revealed ? 1 : 0)
            .overlay {
                if completed {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(Color.deepInk)
                        .symbolEffect(.bounce, value: completedZones)
                }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.7).delay(Double(index) * 0.055),
                value: revealed
            )
    }
}
