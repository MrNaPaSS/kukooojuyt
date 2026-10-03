import ActivityKit
import Foundation

/// Ведёт Live Activity островка: заводит, обновляет при изменении (не чаще раза в 5 с) и
/// заводит заново, когда iOS её закрыла (живёт до 8 часов).
@MainActor
final class IslandController {
    static let shared = IslandController()
    static let minGap: TimeInterval = 5

    private var activity: Activity<IslandAttributes>?
    private var last: IslandAttributes.ContentState?
    private var lastAt = Date.distantPast
    private var pending: IslandAttributes.ContentState?
    /// Обновления уходят в iOS по одному, последнее побеждает: раньше каждое шло своей задачей,
    /// и запоздавшее «идёт запись» затирало «отправлено» - таймер в островке тикал дальше.
    private var queued: (content: ActivityContent<IslandAttributes.ContentState>, alert: AlertConfiguration?)?
    private var pushing = false

    var available: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Почему островка нет - словами для страницы (пусто - всё в порядке). Владелец 02.10.2026:
    /// «островок не работает» - без этого не понять, выключен он в настройках или iOS отказала.
    private(set) var problem = ""
    var onProblem: ((String) -> Void)?

    private func setProblem(_ text: String) {
        guard text != problem else { return }
        problem = text
        onProblem?(text)
    }

    /// alert - развернуть островок на время (так iOS показывает оповещение Live Activity):
    /// заговорил агент - островок сам раскрывается на его духа и складывается после.
    func show(_ state: IslandAttributes.ContentState, force: Bool = false, alert: Bool = false) {
        guard available else {
            return setProblem("Островок выключен: Настройки → Jarvis → «Live Activity» - включи оба переключателя")
        }
        guard state != last || alert else { return }
        // Во время записи - каждые полсекунды (полоски громкости), иначе не чаще раза в 5 с.
        let now = Date()
        // Смена состояния (запись → отправка → «Отправлено ✓» → обычный вид) - сразу: иначе после
        // «Отправить» островок молчал до 5 с, будто ничего не ушло (владелец 02.10.2026).
        let changed = last.map { $0.mode != state.mode || $0.done != state.done || $0.recFor != state.recFor
            || $0.speaker != state.speaker } ?? true
        if !force, !alert, !changed, now.timeIntervalSince(lastAt) < Self.minGap {
            pending = state  // догоним через паузу
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.minGap) { [weak self] in
                guard let self, let next = self.pending else { return }
                self.pending = nil
                self.show(next, force: true)
            }
            return
        }
        last = state
        lastAt = now
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(15 * 60))
        // После перезапуска приложения старая Live Activity ещё висит - берём её, лишние закрываем
        // (иначе островок показывал прежнюю, а обновлялась новая; снимки 02.10.2026).
        if activity == nil {
            let alive = Activity<IslandAttributes>.activities
            activity = alive.first
            for extra in alive.dropFirst() { Task { await extra.end(nil, dismissalPolicy: .immediate) } }
        }
        if let activity, activity.activityState == .active {
            var config: AlertConfiguration?
            if alert {
                let who = GlassesAgents.name(state.speaker)
                // Беззвучно: голос агента и так звучит; silence.wav лежит в приложении.
                config = AlertConfiguration(title: "\(who)", body: "\(String(state.line.prefix(80)))",
                                            sound: .named("silence.wav"))
            }
            push(content, alert: config, to: activity)
            return
        }
        do {
            activity = try Activity.request(attributes: IslandAttributes(), content: content, pushType: nil)
            setProblem("")
        } catch {
            activity = nil
            last = nil  // повторить при следующем обновлении
            setProblem("iOS не запустила островок: \(error.localizedDescription)")
        }
    }

    private func push(_ content: ActivityContent<IslandAttributes.ContentState>, alert: AlertConfiguration?,
                      to activity: Activity<IslandAttributes>) {
        // Оповещение из очереди не теряем: новое состояние заменяет содержимое, но не раскрытие.
        queued = (content, alert ?? queued?.alert)
        guard !pushing else { return }
        pushing = true
        Task { @MainActor in
            while let next = self.queued {
                self.queued = nil
                await activity.update(next.content, alertConfiguration: next.alert)
            }
            self.pushing = false
        }
    }

    /// Поменять одно поле в том, что островок показывает сейчас, - даже когда режим очков выключен
    /// и опроса нет (владелец 04.10.2026: ответил на решение с замка - карточка так и висела).
    func patch(_ change: (inout IslandAttributes.ContentState) -> Void) {
        let alive = activity ?? Activity<IslandAttributes>.activities.first
        guard var state = last ?? alive?.content.state else { return }
        change(&state)
        show(state, force: true)
    }

    func end() {
        queued = nil
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
        last = nil
    }
}
