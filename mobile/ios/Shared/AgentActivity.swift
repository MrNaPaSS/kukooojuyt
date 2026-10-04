import ActivityKit
import Foundation

/// Окно одного агента на замке и в островке (владелец 04.10.2026): у каждого, кто работает по плану,
/// своя Live Activity под общей карточкой - дух, текущий шаг с таймером, «N/M», дальше свёрнуто.
/// Общий файл приложения и расширения JarvisIsland.
struct AgentAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var spirit: IslandAttributes.Spirit
        var finished = false  // план кончился - окно показывает «готово» и закрывается через ~20 с
    }

    var agent: String  // id агента из реестра: server, pc, clawdbot, codex и будущие
}

extension IslandAttributes.Spirit {
    /// Когда взят текущий шаг: из него таймер окна и порядок «кто свежее».
    var stepStarted: Date? { todo?.first { $0.s == 1 }?.b }

    /// Работает по плану - значит, ему положено отдельное окно.
    /// План выполнен целиком - окно тоже закрывается, даже если агент ещё занят.
    var wantsWindow: Bool { busy && total > 0 && done < total }
}

/// Кому открыть окно, кому обновить, кому закрыть. Чистая функция - её проверяют тесты
/// (NMNHJarvisTests/AgentActivityPlanTests), а AgentActivities только исполняет ответ.
enum AgentActivityPlan {
    /// iOS даёт приложению до 5 Live Activity, одна из них - общая карточка Джарвиса.
    static let maxWindows = 4
    /// Сколько окно закончившего агента ещё висит с «готово».
    static let closeAfter: TimeInterval = 20

    enum Step: Hashable {
        case open(String)
        case update(String)
        case close(String)
    }

    /// spirits - свежие духи из опроса; open - у кого окно уже открыто (по порядку открытия).
    ///
    /// Закрываем раньше, чем открываем: место освободившегося сразу занимает следующий. Если
    /// работающих больше, чем окон, места получают те, кто взял шаг последним; уже открытое окно
    /// не отбираем - иначе окна прыгали бы при каждом новом шаге.
    static func plan(spirits: [IslandAttributes.Spirit], open: [String]) -> [Step] {
        let wanted = spirits.filter(\.wantsWindow)
        let wantedIds = Set(wanted.map(\.id))
        var steps: [Step] = open.filter { !wantedIds.contains($0) }.map { Step.close($0) }
        var kept = open.filter { wantedIds.contains($0) }
        steps += kept.map { Step.update($0) }
        let fresh = wanted.filter { !kept.contains($0.id) }
            .sorted { ($0.stepStarted ?? .distantPast) > ($1.stepStarted ?? .distantPast) }
        for spirit in fresh where kept.count < maxWindows {
            kept.append(spirit.id)
            steps.append(.open(spirit.id))
        }
        return steps
    }

    /// Состояние окна, которое закрывается: последний вид агента с «готово».
    static func finished(_ last: IslandAttributes.Spirit) -> AgentAttributes.ContentState {
        var spirit = last
        spirit.busy = false
        if spirit.total > 0 { spirit.done = spirit.total }
        return AgentAttributes.ContentState(spirit: spirit, finished: true)
    }

    /// Следующие шаги после текущего - одной свёрнутой строкой: «Дальше: тесты · выкладка · ещё 2».
    /// names - сколько назвать по имени; остальные - числом. Впереди ничего - nil.
    static func upcomingLine(_ spirit: IslandAttributes.Spirit, names: Int = 2) -> String? {
        let ahead = (spirit.todo ?? []).filter { $0.s == 0 }.map(\.t)
        let current = spirit.todo?.contains { $0.s == 1 } == true ? 1 : 0
        // В окне плана (IslandBuilder.window) не все шаги - остальные знаем только числом.
        let count = max(ahead.count, spirit.total - spirit.done - current)
        guard count > 0 else { return nil }
        let named = Array(ahead.prefix(names))
        let rest = count - named.count
        let parts = named + (rest > 0 ? ["ещё \(rest)"] : [])
        return "Дальше: " + parts.joined(separator: " · ")
    }
}
