import ActivityKit
import SwiftUI
import WidgetKit

/// Островок iPhone и виджеты: агенты-духи и сводка пульта (ТЗ docs/tz/glasses-ios-app-tz.md, этап 6).
@main
struct JarvisIslandBundle: WidgetBundle {
    var body: some Widget {
        JarvisIslandWidget()
        TalkWidget()
        NotesWidget()
        MoneyWidget()
        ServerWidget()
        AgentsWidget()
        TasksWidget()
        PultWidget()
        LockMoneyWidget()
        LockServerWidget()
        HostWidgets().body  // больше 10 в одном списке WidgetBundle не берёт
    }
}

/// Нагрузка двух серверов кольцами и окна агентов (04.10.2026) - отдельной группой: список
/// бандла упёрся в 10.
struct HostWidgets: WidgetBundle {
    var body: some Widget {
        HostMainWidget()
        HostAgentsWidget()
        HostsWidget()
        AgentWindowWidget()  // отдельная Live Activity на каждого, кто работает по плану
    }
}

struct JarvisIslandWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IslandAttributes.self) { context in
            // Процесс островка свой: имена и цвета добавленных агентов (Codex, Clawdbot) - из духов состояния.
            let _ = GlassesAgents.learn(context.state.spirits)
            LockCard(state: context.state, stale: context.isStale)
                .padding(14)
                .widgetURL(planURL(context.state.spirits))
                .activityBackgroundTint(DashTheme.base.opacity(0.45))  // сквозь подложку видно размытые обои
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            GlassesAgents.learn(s.spirits)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    IslandMetrics(state: s, stale: context.isStale)  // агенты-кнопки, сервер, сторож - без прибыли
                        .padding(.horizontal, 6).padding(.bottom, 2)
                }
            } compactLeading: {
                if !quiet(s) { Compact(state: s) }  // тихо - островок как обычный, без наших значков
            } compactTrailing: {
                if let d = s.decision, !(context.isStale && d.kind == "progress") {  // ждёт решения - знак вопроса цвета агента, раскрыть - кнопки
                    Image(systemName: DecisionCard.icon(d))
                        .foregroundStyle(SpiritView.color(d.agent))
                } else if !quiet(s) {
                    Trailing(state: s).font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            } minimal: {
                if !quiet(s) { SpiritView(id: lead(s).id, busy: lead(s).busy, size: 16) }
            }
            .keylineTint(SpiritView.color(lead(s).id))
            .widgetURL(planURL(s.spirits))  // нажал на островок - план агента с его «1/3»
        }
    }
}

/// Тихо: никто не работает, не говорит, не пишет голосовое, нет итога отправки и тревог -
/// островок выглядит как обычный системный (просьба владельца 02.10.2026). Метрики - по долгому нажатию.
func quiet(_ s: IslandAttributes.ContentState) -> Bool {
    s.mode == .quiet && s.done.isEmpty && s.decision == nil && (s.dash?.alerts.isEmpty ?? true)
}

private struct Compact: View {
    let state: IslandAttributes.ContentState
    var body: some View {
        switch state.mode {
        case .recording:
            HStack(spacing: 5) {
                SpiritView(id: state.recFor, busy: true, size: 16)
                LevelBars(levels: state.levels, tint: SpiritView.color(state.recFor), count: 5, height: 14)
            }
        case .thinking:
            SpiritView(id: state.recFor, busy: true, size: 18)  // кому отправляем
        case .speaking:
            SpiritView(id: state.speaker, busy: true, size: 18)
        case .working, .quiet:
            Spirits(spirits: state.spirits.filter { $0.busy || state.mode == .quiet }.prefix(2).map { $0 }, size: 16)
        }
    }
}

private struct Trailing: View {
    let state: IslandAttributes.ContentState
    var body: some View {
        switch state.mode {
        case .recording:
            if let since = state.recSince {
                Text(timerInterval: since...since.addingTimeInterval(3600), countsDown: false)
                    .monospacedDigit().foregroundStyle(.red).frame(maxWidth: 44)
            }
        case .thinking:
            Image(systemName: "ellipsis").foregroundStyle(SpiritView.color(state.recFor))
        case .speaking:
            Image(systemName: "waveform").foregroundStyle(SpiritView.color(state.speaker))
        case .working:
            let busy = lead(state)
            if busy.total > 0 {
                Text("\(busy.done)/\(busy.total)").foregroundStyle(SpiritView.color(busy.id))
            } else if let since = busy.since {
                Text(timerInterval: since...since.addingTimeInterval(36000), countsDown: false)
                    .monospacedDigit().foregroundStyle(SpiritView.color(busy.id)).frame(maxWidth: 44)
            }
        case .quiet where !state.done.isEmpty:
            Image(systemName: state.doneOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(state.doneOK ? DashTheme.money : DashTheme.down)
        case .working where !state.done.isEmpty:
            Image(systemName: state.doneOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(state.doneOK ? DashTheme.money : DashTheme.down)
        case .quiet:
            if let dash = state.dash, !dash.alerts.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DashTheme.down)
            } else if let dash = state.dash {
                Text("\(dash.srv.cpu)%").foregroundStyle(dash.srv.cpu >= 80 ? DashTheme.warn : DashTheme.server)
                    .lineLimit(1).frame(maxWidth: 48)
            } else {
                Image(systemName: "eyeglasses").foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

/// Экран блокировки: та же карточка агента и духи всех троих.
private struct LockCard: View {
    let state: IslandAttributes.ContentState
    var stale = false
    var body: some View {
        IslandMetrics(state: state, stale: stale)
    }
}
