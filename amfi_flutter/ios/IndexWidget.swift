import WidgetKit
import SwiftUI

struct IndexEntry: Codable, Identifiable {
    let id = UUID()
    let name: String
    let last: String
    let change: String
    let isPositive: Bool
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), indices: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), indices: loadIndices())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entries = [SimpleEntry(date: Date(), indices: loadIndices())]
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

    private func loadIndices() -> [IndexEntry] {
        let prefs = UserDefaults(suiteName: "group.com.infin.trulite")
        guard let jsonString = prefs?.string(forKey: "indices_json"),
              let data = jsonString.data(using: .utf8) else {
            return []
        }

        do {
            return try JSONDecoder().decode([IndexEntry].self, from: data)
        } catch {
            return []
        }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let indices: [IndexEntry]
}

struct IndexWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Indices")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.white)
            }

            Divider().background(Color.white.opacity(0.3))

            if entry.indices.isEmpty {
                Spacer()
                Text("No bookmarks.\nOpen app to add.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(entry.indices.prefix(4)) { index in
                    HStack {
                        Text(index.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("₹\(index.last)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            Text("\(index.isPositive ? "+" : "")\(index.change)%")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(index.isPositive ? .green : .red)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Spacer()
            }
        }
        .padding()
        .background(Color(red: 26/255, green: 35/255, blue: 126/255)) // Indigo 900
    }
}

@main
struct IndexWidget: Widget {
    let kind: String = "IndexWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            IndexWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Market Indices")
        .description("View your bookmarked market indices.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
