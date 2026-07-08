import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), cpuTemp: 45.0, fanSpeed: "2000 RPM", memory: "45%", aiMessage: "System is healthy.")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), cpuTemp: 55.0, fanSpeed: "3000 RPM", memory: "60%", aiMessage: "Heavy load detected.")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var entries: [SimpleEntry] = []
        let currentDate = Date()
        
        // In a real app, you'd read from UserDefaults(suiteName: "group.com.coolcumber") here
        let entry = SimpleEntry(date: currentDate, cpuTemp: 50.0, fanSpeed: "2000 RPM", memory: "50%", aiMessage: "AI Copilot active.")
        entries.append(entry)

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let cpuTemp: Double
    let fanSpeed: String
    let memory: String
    let aiMessage: String
}

struct CoolCumberWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "fanblades.fill")
                    .foregroundColor(.cyan)
                Text("CoolCumber")
                    .font(.headline)
                    .bold()
                Spacer()
                Text(String(format: "%.1f°C", entry.cpuTemp))
                    .foregroundColor(entry.cpuTemp > 80 ? .red : .orange)
                    .bold()
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Fan")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(entry.fanSpeed)
                        .font(.caption)
                        .bold()
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("RAM")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(entry.memory)
                        .font(.caption)
                        .bold()
                }
            }
            
            Spacer(minLength: 4)
            
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                    .font(.caption)
                Text(entry.aiMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
    }
}

@main
struct CoolCumberWidget: Widget {
    let kind: String = "CoolCumberWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CoolCumberWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("CoolCumber Monitor")
        .description("View Mac thermals and AI diagnostics.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
