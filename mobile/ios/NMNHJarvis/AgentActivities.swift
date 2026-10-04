import ActivityKit
import Foundation

/// Ведёт отдельные окна агентов (AgentAttributes) по ответу AgentActivityPlan: открывает, обновляет
/// только при изменении (таймер шага тикает сам) и закрывает с «готово» через 20 с.
@MainActor
final class AgentActivities {
    static let shared = AgentActivities()

    private var windows: [String: Activity<AgentAttributes>] = [:]
    private var order: [String] = []  // порядок открытия - он же порядок окон на замке
    private var shown: [String: AgentAttributes.ContentState] = [:]
    private var adopted = false

    /// Свежие духи из опроса агентов (GlassesVoice.pollJarvis).
    func sync(_ spirits: [IslandAttributes.Spirit]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        adopt()
        // Окно, которое iOS закрыла сама (8 часов, смахнули с замка), - больше не наше.
        for (id, activity) in windows where activity.activityState != .active { forget(id) }
        let byId = Dictionary(spirits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for step in AgentActivityPlan.plan(spirits: spirits, open: order) {
            switch step {
            case let .open(id): if let spirit = byId[id] { open(spirit) }
            case let .update(id): if let spirit = byId[id] { update(id, AgentAttributes.ContentState(spirit: spirit)) }
            case let .close(id): close(id)
            }
        }
    }

    /// Выключили режим очков - опроса больше нет, и окна без обновлений врали бы.
    func endAll() {
        for activity in Activity<AgentAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        windows = [:]; order = []; shown = [:]
        adopted = true  // только что закрыли всё - подбирать нечего
    }

    /// После перезапуска приложения окна ещё висят - берём их, дубли одного агента закрываем.
    private func adopt() {
        guard !adopted else { return }
        adopted = true
        for activity in Activity<AgentAttributes>.activities where activity.activityState == .active {
            let id = activity.attributes.agent
            if windows[id] == nil {
                windows[id] = activity
                order.append(id)
                shown[id] = activity.content.state
            } else {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }

    private func open(_ spirit: IslandAttributes.Spirit) {
        let state = AgentAttributes.ContentState(spirit: spirit)
        do {
            let activity = try Activity.request(attributes: AgentAttributes(agent: spirit.id),
                                                content: content(state), pushType: nil)
            windows[spirit.id] = activity
            order.append(spirit.id)
            shown[spirit.id] = state
        } catch {
            // Не открылось (лимит iOS) - попробуем на следующем опросе, общей карточке это не мешает.
        }
    }

    private func update(_ id: String, _ state: AgentAttributes.ContentState) {
        guard let activity = windows[id], shown[id] != state else { return }
        shown[id] = state
        let next = content(state)
        Task { await activity.update(next) }
    }

    private func close(_ id: String) {
        guard let activity = windows[id] else { return forget(id) }
        let last = shown[id]?.spirit ?? activity.content.state.spirit
        let final = ActivityContent(state: AgentActivityPlan.finished(last), staleDate: nil)
        // Закрывает iOS по времени - даже если приложение к тому моменту уснуло.
        let until = Date().addingTimeInterval(AgentActivityPlan.closeAfter)
        Task { await activity.end(final, dismissalPolicy: .after(until)) }
        forget(id)
    }

    private func forget(_ id: String) {
        windows[id] = nil
        shown[id] = nil
        order.removeAll { $0 == id }
    }

    /// Устаревает через 15 минут без обновлений: опрос встал - окно гаснет, а не показывает старое.
    private func content(_ state: AgentAttributes.ContentState) -> ActivityContent<AgentAttributes.ContentState> {
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(15 * 60))
    }
}
