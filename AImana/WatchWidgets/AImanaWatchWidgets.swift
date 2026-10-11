import AImanaCore
import SwiftUI
import WidgetKit

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let payload: WatchPayload?

    var content: ComplicationContent { ComplicationContent(date: date, payload: payload) }
}

/// Reads the payload the watch app saved from the iPhone. No network: the iPhone pushes new readings through
/// WatchConnectivity and the watch app reloads these timelines when one lands.
struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, payload: Self.placeholderPayload)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        let saved = WatchPayloadStore.shared().load()
        completion(ComplicationEntry(date: .now, payload: saved ?? (context.isPreview ? Self.placeholderPayload : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        completion(Self.timeline(payload: WatchPayloadStore.shared().load(), now: .now))
    }

    /// Entries every 15 minutes for four hours keep the countdown and the reading's age honest between pushes, plus
    /// one just after each reset so a passed reset is flagged on time.
    static func timeline(payload: WatchPayload?, now: Date) -> Timeline<ComplicationEntry> {
        let ticks = (0...16).map { now.addingTimeInterval(Double($0) * 15 * 60) }
        let resets = (payload?.providers ?? []).flatMap(\.lanes).compactMap(\.resetsAt)
            .map { $0.addingTimeInterval(1) }.filter { $0 > now && $0 < ticks.last! }
        let entries = Set(ticks + resets).sorted().map { ComplicationEntry(date: $0, payload: payload) }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// Shown in the face gallery before any reading arrives.
    static var placeholderPayload: WatchPayload {
        WatchPayload(sentAt: .now, mode: .used, providers: [
            .init(id: "claude", name: "Claude Code", updatedAt: .now,
                  lanes: [.init(kind: .session, used: 42, minutes: 300, resetsAt: .now.addingTimeInterval(7800))],
                  issue: nil),
        ])
    }
}

struct AImanaComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AImanaComplication", provider: ComplicationProvider()) { entry in
            ComplicationView(content: entry.content)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("AI·mana")
        .description(WatchStrings.text("Your fullest session quota, with its reset."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}

@main
struct AImanaWatchWidgets: WidgetBundle {
    var body: some Widget {
        AImanaComplication()
    }
}
