import SwiftUI

struct MoreView: View {
    @State private var tapFeedback = 0

    private static let guideRows: [CareGuideRow.Model] = [
        .init(systemImage: "timer", title: "Two minutes", detail: "Twice daily", tint: .rinseBlue),
        .init(systemImage: "drop.fill", title: "Fluoride toothpaste", detail: "Use a pea-sized amount", tint: .sketchLavender),
        .init(systemImage: "leaf.fill", title: "Soft bristles", detail: "Gentle on the gumline", tint: .mintDeep),
        .init(systemImage: "angle", title: "Aim around 45°", detail: "Angle toward the gumline", tint: .achievementGold),
        .init(systemImage: "hand.raised.fill", title: "Light pressure", detail: "Use short, controlled strokes", tint: .coachCoral)
    ]

    private static let adaGuidance = URL(
        string: "https://www.ada.org/resources/ada-library/oral-health-topics/toothbrushes"
    )!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    CarePrinciplesCard()
                        .staggeredReveal(index: 0)

                    CompanionSectionHeader(title: "BRUSH WELL", detail: "A compact reference for the technique that matters.")
                        .staggeredReveal(index: 1)

                    guideCard
                        .staggeredReveal(index: 2)

                    CompanionSectionHeader(title: "RESOURCES", detail: "Guidance and tools, kept out of the daily flow.")
                        .staggeredReveal(index: 3)

                    Link(destination: Self.adaGuidance) {
                        ResourceRow(
                            title: "ADA brushing guidance",
                            detail: "Read the source behind BrushCoach's routine",
                            systemImage: "safari.fill"
                        )
                    }
                    .buttonStyle(TactileCardButtonStyle())
                    .simultaneousGesture(TapGesture().onEnded { tapFeedback += 1 })
                    .staggeredReveal(index: 4)

                    NavigationLink {
                        TraceInboxView()
                    } label: {
                        ResourceRow(
                            title: "Motion trace inbox",
                            detail: "Inspect transferred Watch sessions",
                            systemImage: "waveform.path.ecg"
                        )
                    }
                    .buttonStyle(TactileCardButtonStyle())
                    .simultaneousGesture(TapGesture().onEnded { tapFeedback += 1 })
                    .staggeredReveal(index: 5)

                    Text("BrushCoach supports a routine; it does not assess dental health or replace advice from a dental professional.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .staggeredReveal(index: 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .revealGroup()
            }
            .background(Color.enamelWash.ignoresSafeArea())
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
        }
        .sensoryFeedback(.selection, trigger: tapFeedback)
    }

    private var guideCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.guideRows.enumerated()), id: \.element.id) { index, model in
                if index > 0 {
                    Divider().padding(.leading, 58)
                }
                CareGuideRow(model: model)
            }
        }
        .padding(14)
        .premiumCard(cornerRadius: 24)
    }
}

private struct CarePrinciplesCard: View {
    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.mintFresh.opacity(0.34))
                Image(systemName: "sparkles")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(Color.deepInk)
            }
            .frame(width: 70, height: 70)

            VStack(alignment: .leading, spacing: 5) {
                Text("Small technique. Lasting rhythm.")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(Color.deepInk)
                Text("Everything here supports a simple twice-daily habit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .premiumCard(cornerRadius: 28)
    }
}

struct CareGuideRow: View {
    struct Model: Identifiable {
        let id = UUID()
        let systemImage: String
        let title: String
        let detail: String
        let tint: Color
    }

    let model: Model

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: model.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(model.tint)
                .frame(width: 38, height: 38)
                .background(model.tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.deepInk)
                Text(model.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 7)
    }
}
