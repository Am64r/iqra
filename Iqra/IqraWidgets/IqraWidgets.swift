import WidgetKit
import SwiftUI

struct IqraWidgetsEntry: TimelineEntry {
    let date: Date
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> IqraWidgetsEntry {
        IqraWidgetsEntry(date: Date())
    }
    
    func getSnapshot(in context: Context, completion: @escaping (IqraWidgetsEntry) -> Void) {
        completion(IqraWidgetsEntry(date: Date()))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<IqraWidgetsEntry>) -> Void) {
        let entry = IqraWidgetsEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct IqraWidgetsEntryView: View {
    var entry: Provider.Entry
    
    var body: some View {
        VStack {
            Image(systemName: "book.fill")
                .font(.largeTitle)
            Text("Iqra")
                .font(.headline)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct IqraWidgets: Widget {
    let kind: String = "IqraWidgets"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            IqraWidgetsEntryView(entry: entry)
        }
        .configurationDisplayName("Iqra")
        .description("Quick access to Iqra")
        .supportedFamilies([.systemSmall])
    }
}
