import AppIntents
import SwiftUI
import WidgetKit

/// Виджет «Говорить» (просьба владельца 02.10.2026): три духа - Джарвис, Агент, Claude.
/// Нажал на духа - запись этому агенту, нажал ещё раз - отправлено. Удержание виджеты у Apple
/// не передают (только нажатия), поэтому «нажал - нажал». Запись ведёт приложение в фоне
/// (TalkIntent - AudioRecordingIntent), полоски громкости - в островке.
struct TalkEntry: TimelineEntry {
    let date: Date
    let recFor: String   // кому идёт запись; пусто - тишина
    let since: Date?
}

struct TalkProvider: TimelineProvider {
    func placeholder(in context: Context) -> TalkEntry { TalkEntry(date: Date(), recFor: "", since: nil) }
    func getSnapshot(in context: Context, completion: @escaping (TalkEntry) -> Void) { completion(Self.current()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TalkEntry>) -> Void) {
        completion(Timeline(entries: [Self.current()], policy: .never))  // обновляет приложение при старте и конце записи
    }

    static func current() -> TalkEntry {
        let state = SharedStore.load(TalkState.self, from: "talk.json")
        return TalkEntry(date: Date(), recFor: state?.recFor ?? "", since: state?.since)
    }
}

struct TalkWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TalkEntry
    var body: some View {
        let ids = family == .systemSmall ? ["jarvis"] : GlassesAgents.all
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.recFor.isEmpty ? "Голосовое" : "Запись: \(GlassesAgents.name(entry.recFor))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.recFor.isEmpty ? DashTheme.label : DashTheme.down)
                Spacer()
                if let since = entry.since, !entry.recFor.isEmpty {
                    Text(since, style: .timer).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(DashTheme.down).frame(maxWidth: 48, alignment: .trailing)
                }
            }
            HStack(spacing: 10) {
                ForEach(ids, id: \.self) { id in
                    let live = entry.recFor == id
                    // Кнопка - сам дух и цветное имя, без цветных кругов и обводок (владелец 03.10.2026).
                    Button(intent: TalkIntent(agent: id)) {
                        FullColor {
                            VStack(spacing: 6) {
                                SpiritView(id: id, busy: live, size: family == .systemSmall ? 58 : 44)
                                    .frame(height: family == .systemSmall ? 70 : 54)
                                HStack(spacing: 4) {
                                    if live { Circle().fill(DashTheme.down).frame(width: 6, height: 6) }
                                    Text(live ? "Отправить" : GlassesAgents.name(id)).font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(SpiritView.color(id))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .pultBackground()
    }
}

struct TalkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TalkState.kind, provider: TalkProvider()) { TalkWidgetView(entry: $0) }
            .configurationDisplayName("Говорить")
            .description("Нажми духа - голосовое Джарвис, агенту или Claude; нажми ещё раз - отправлено.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
