import ActivityKit
import SwiftUI
import WidgetKit

/// Окно одного агента (AgentAttributes): на замке - под общей карточкой, в том же стекле; в островке -
/// компактно дух и «N/M», раскрыто - имя, текущий шаг с таймером и прогресс (владелец 04.10.2026).
struct AgentWindowWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentAttributes.self) { context in
            AgentWindowCard(state: context.state, stale: context.isStale)
                .padding(14)
                .widgetURL(agentURL(context.attributes.agent))
                .activityBackgroundTint(DashTheme.base.opacity(0.45))  // как у общей карточки
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let spirit = context.state.spirit
            let _ = GlassesAgents.remember(spirit)
            let tint = SpiritView.color(spirit.id)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    AgentWindowCard(state: context.state, stale: context.isStale, island: true)
                        .padding(.horizontal, 6).padding(.bottom, 2)
                }
            } compactLeading: {
                SpiritView(id: spirit.id, busy: !context.state.finished, size: 16)
            } compactTrailing: {
                AgentProgressText(state: context.state)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            } minimal: {
                SpiritView(id: spirit.id, busy: !context.state.finished, size: 16)
            }
            .keylineTint(tint)
            .widgetURL(agentURL(spirit.id))
        }
    }
}

/// Касание окна - план этого агента.
private func agentURL(_ id: String) -> URL {
    URL(string: "jarvis://plan?agent=\(id)") ?? URL(fileURLWithPath: "/")
}
