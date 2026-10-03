import UIKit
import UserNotifications

/// Настоящие уведомления iPhone (владелец 03.10.2026: «как у айфона приходят с приложения»).
///
/// Без APNs: их ставит само приложение, пока живёт в фоне на тихом звуке (режим очков). Решение -
/// с кнопками: «Выложить» / «Отклонить» у выкладки, варианты у вопроса агента. Нажатие кнопки
/// отвечает на сервер, не открывая приложение. Ещё - агент закончил работу.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    nonisolated static let deployCategory = "deploy"
    nonisolated static let choicePrefix = "choice-"
    nonisolated static let pickPrefix = "pick-"

    private var asked = false
    private var shownDecision = ""

    /// Разрешение и делегат - при запуске приложения (иначе кнопки в фоне некому принять).
    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        guard !asked else { return }
        asked = true
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Новое решение - уведомление с кнопками. То же решение второй раз не показываем;
    /// решение ушло (ответили на ПК или пульте) - убираем его уведомление.
    func show(_ decision: IslandAttributes.Decision?) {
        let center = UNUserNotificationCenter.current()
        guard let decision else {
            if !shownDecision.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ["decision"])
                shownDecision = ""
            }
            return
        }
        guard decision.key != shownDecision else { return }
        shownDecision = decision.key
        let category = Self.category(for: decision)
        center.getNotificationCategories { known in
            var all = known.filter { !$0.identifier.hasPrefix(Self.choicePrefix) && $0.identifier != Self.deployCategory }
            all.insert(category)
            center.setNotificationCategories(all)
            let content = UNMutableNotificationContent()
            content.title = decision.title
            content.body = decision.text
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = category.identifier
            content.userInfo = ["kind": decision.kind, "id": decision.id, "agent": decision.agent]
            center.add(UNNotificationRequest(identifier: "decision", content: content, trigger: nil))
        }
    }

    /// Агент закончил работу - короткое уведомление без кнопок.
    func finished(agent: String, step: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(GlassesAgents.name(agent)) \(agent == "jarvis" ? "закончила" : "закончил")"
        content.body = step.isEmpty ? "Работа завершена" : step
        content.sound = .default
        content.userInfo = ["agent": agent]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "done-\(agent)", content: content, trigger: nil))
    }

    /// Кнопки: у выкладки две постоянные, у простого вопроса - его варианты, у сложного - нет
    /// (касание открывает приложение).
    nonisolated static func category(for decision: IslandAttributes.Decision) -> UNNotificationCategory {
        let options = decision.simple ? decision.options : []
        let actions = options.enumerated().map { index, label in
            UNNotificationAction(identifier: "\(pickPrefix)\(index)", title: label,
                                 options: decision.kind == "deploy" && index == 1 ? [.destructive] : [])
        }
        let id = decision.kind == "deploy" ? deployCategory : "\(choicePrefix)\(decision.id)"
        return UNNotificationCategory(identifier: id, actions: actions, intentIdentifiers: [], options: [])
    }

    /// Номер варианта из кнопки уведомления: «pick-1» - 1; не кнопка - nil.
    nonisolated static func pick(from action: String) -> Int? {
        guard action.hasPrefix(pickPrefix) else { return nil }
        return Int(action.dropFirst(pickPrefix.count))
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Приложение открыто - баннер всё равно показать.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler done: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let kind = info["kind"] as? String ?? ""
        let id = info["id"] as? String ?? ""
        let agent = info["agent"] as? String ?? ""
        let pick = Self.pick(from: response.actionIdentifier)
        Task { @MainActor in
            if let pick, !kind.isEmpty {
                await GlassesVoice.shared.decide(kind: kind, id: id, pick: pick)
            } else if let url = URL(string: "jarvis://plan?agent=\(agent)") {
                AgentBoard.shared.open(url)  // касание уведомления - план агента
            }
            done()
        }
    }
}

/// Делегат приложения: уведомления должны быть готовы до первого нажатия кнопки, даже если iOS
/// подняла приложение ради него.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { Notifier.shared.start() }
        return true
    }
}
