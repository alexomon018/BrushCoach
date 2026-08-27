import SwiftUI
import WidgetKit

private struct BrushEntry: TimelineEntry {
    let date: Date
}

private struct BrushProvider: TimelineProvider {
    func placeholder(in context: Context) -> BrushEntry { BrushEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (BrushEntry) -> Void) {
        completion(BrushEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BrushEntry>) -> Void) {
        completion(Timeline(entries: [BrushEntry(date: .now)], policy: .never))
    }
}

private struct BrushComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("Start 2-minute brush", systemImage: "toothbrush.fill")
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: "toothbrush.fill")
                        .font(.title2)
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Brush now").font(.headline)
                        Text("2 min · 6 zones").font(.caption2)
                    }
                }
            case .accessoryCorner:
                Image(systemName: "toothbrush.fill")
                    .font(.headline)
                    .widgetAccentable()
                    .widgetLabel { Text(periodLabel) }
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "toothbrush.fill")
                        .font(.title2.weight(.semibold))
                        .widgetAccentable()
                }
            }
        }
        .widgetURL(URL(string: "brushcoach://start"))
        .containerBackground(for: .widget) { Color.clear }
    }

    private var periodLabel: String {
        Calendar.current.component(.hour, from: .now) < 15 ? "Morning brush" : "Evening brush"
    }
}

@main
struct BrushCoachQuickStartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BrushCoachQuickStart", provider: BrushProvider()) { _ in
            BrushComplicationView()
        }
        .configurationDisplayName("Quick Brush")
        .description("Start a two-minute six-zone brushing session.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}
