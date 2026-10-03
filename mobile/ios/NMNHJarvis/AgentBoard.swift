import Foundation

/// Планы и работа агентов для экрана плана (касание островка, владелец 03.10.2026).
/// Наполняется тем же опросом GET /api/admin/agents, что и островок.
struct AgentPlan: Equatable {
    struct Step: Equatable, Identifiable {
        let id: Int
        let t: String
        let s: Int  // 0 впереди, 1 в работе, 2 готово
    }

    var name: String
    var steps: [Step]

    var done: Int { steps.filter { $0.s == 2 }.count }
    var current: Step? { steps.first { $0.s == 1 } ?? steps.first { $0.s == 0 } }
    var progress: Double { steps.isEmpty ? 0 : Double(done) / Double(steps.count) }
}

struct AgentWork: Equatable {
    var busy: Bool
    var since: Date?
}

@MainActor
final class AgentBoard: ObservableObject {
    static let shared = AgentBoard()

    @Published private(set) var plans: [String: AgentPlan] = [:]
    @Published private(set) var work: [String: AgentWork] = [:]
    /// Чей план открыт; nil - экран закрыт.
    @Published var focus: String?

    func apply(_ state: [String: Any], now: Date) {
        let parsed = Self.parse(state, now: now)
        if parsed.plans != plans { plans = parsed.plans }
        if parsed.work != work { work = parsed.work }
    }

    /// Показать как образец (демо на симуляторе, без сервера).
    func show(plans: [String: AgentPlan], work: [String: AgentWork]) {
        self.plans = plans
        self.work = work
    }

    /// jarvis://plan?agent=server - открыть план этого агента.
    func open(_ url: URL) {
        guard url.scheme == "jarvis", url.host == "plan" else { return }
        let agent = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "agent" }?.value ?? ""
        focus = GlassesAgents.all.contains(agent) ? agent : Self.busiest(plans: plans, work: work)
    }

    /// Кого показать, если агент не задан: того, у кого план в работе, иначе занятого, иначе агента.
    nonisolated static func busiest(plans: [String: AgentPlan], work: [String: AgentWork]) -> String {
        GlassesAgents.all.first { work[$0]?.busy == true && !(plans[$0]?.steps.isEmpty ?? true) }
            ?? GlassesAgents.all.first { work[$0]?.busy == true }
            ?? GlassesAgents.all.first { !(plans[$0]?.steps.isEmpty ?? true) }
            ?? "server"
    }

    /// Разбор ответа сервера. Чистая функция - её проверяют тесты.
    nonisolated static func parse(_ state: [String: Any], now: Date) -> (plans: [String: AgentPlan], work: [String: AgentWork]) {
        let rawPlans = state["plans"] as? [String: [String: Any]] ?? [:]
        let rawWork = state["work"] as? [String: [String: Any]] ?? [:]
        var plans: [String: AgentPlan] = [:]
        for (id, raw) in rawPlans {
            let steps = (raw["steps"] as? [[String: Any]] ?? []).enumerated().map { i, step in
                AgentPlan.Step(id: i, t: step["t"] as? String ?? "", s: (step["s"] as? NSNumber)?.intValue ?? 0)
            }
            let name = (raw["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? raw["title"] as? String ?? ""
            plans[id] = AgentPlan(name: name, steps: steps)
        }
        var work: [String: AgentWork] = [:]
        for (id, raw) in rawWork {
            let busy = raw["busy"] as? Bool ?? false
            let secs = (raw["secs"] as? NSNumber)?.doubleValue ?? 0
            work[id] = AgentWork(busy: busy, since: busy ? now.addingTimeInterval(-secs) : nil)
        }
        return (plans, work)
    }
}
