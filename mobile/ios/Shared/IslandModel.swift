import ActivityKit
import Foundation

/// Островок (Live Activity): агенты-духи, как островок Coucou на ПК.
/// Общий файл приложения и расширения JarvisIsland.
struct IslandAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var mode: Mode
        var spirits: [Spirit]
        var recSince: Date?
        var line: String  // одна строка снизу: что сказала Джарвис или шаг агента
        var page: DashPage = .agents  // какую страницу сводки показать (листается приложением)
        var dash: Dash?               // сводка пульта: деньги, сервер, сделки, задачи, цели
        var recFor = "jarvis"         // кому идёт запись: jarvis, server, pc
        var levels: [Double] = []     // громкость голоса за последние секунды, 0...1 - полоски в островке
        var speaker = "jarvis"        // кто сейчас говорит голосом: jarvis, server, pc
        var done = ""                 // итог отправки голосового на 3 с: «Отправлено: Агент ✓» или ошибка
        var doneOK = true
    }

    enum Mode: String, Codable, Hashable {
        case recording  // идёт запись с очков
        case thinking   // Джарвис думает над голосовым
        case speaking   // Джарвис говорит
        case working    // кто-то из агентов работает
        case quiet      // всё тихо
    }

    struct Spirit: Codable, Hashable, Identifiable {
        var id: String      // jarvis, server, pc
        var busy: Bool
        var since: Date?    // начало работы - для живого таймера без обновлений
        var done: Int       // план: готово
        var total: Int      // план: всего
        var step: String    // шаг в работе
        var todo: [Todo]? = nil  // до 6 шагов плана вокруг текущего - экран блокировки (03.10.2026)
        // Лимит подписки Claude: сколько съедено за 5 часов и за неделю, в
        // процентах. Нужен рядом с работающим (владелец 03.10.2026): вопрос
        // «успеет ли он доделать» возникает именно тогда, когда он занят.
        var lim5: Int? = nil
        var lim7: Int? = nil
    }

    struct Todo: Codable, Hashable {
        var t: String
        var s: Int       // 0 впереди, 1 в работе, 2 готово
        var b: Date?     // когда шаг взяли - из него живой таймер текущего
        var d: Int?      // сколько занял готовый, секунды
    }
}

extension IslandAttributes.Spirit {
    var name: String {
        switch id {
        case "jarvis": return "Джарвис"
        case "server": return "Домашний"
        default: return "Claude Code"
        }
    }
}

/// Касание островка - план того, кто работает (сначала агент с планом, потом любой занятый).
func planURL(_ spirits: [IslandAttributes.Spirit]) -> URL {
    let id = spirits.first { $0.busy && $0.total > 0 }?.id ?? spirits.first { $0.busy && $0.id != "jarvis" }?.id ?? ""
    return URL(string: "jarvis://plan?agent=\(id)") ?? URL(fileURLWithPath: "/")
}

/// Сборка состояния островка из ответа GET /api/admin/agents. Чистая функция - её проверяют тесты.
enum IslandBuilder {
    static let order = ["jarvis", "server", "pc"]

    static func spirits(from state: [String: Any], now: Date) -> [IslandAttributes.Spirit] {
        let work = state["work"] as? [String: [String: Any]] ?? [:]
        let plans = state["plans"] as? [String: [String: Any]] ?? [:]
        // [% за 5 часов, секунд до обновления, % за неделю, секунд] - pult_limits.brief.
        let limits = state["limits"] as? [String: [Any]] ?? [:]
        // Последнее действие каждого агента («Bash: …») - шаг, когда плана нет (владелец 03.10.2026:
        // на замке было «план не заявлен», а в чате видно, чем он занят).
        let chat = state["chat"] as? [[String: Any]] ?? []
        return order.map { id in
            let entry = work[id] ?? [:]
            let busy = entry["busy"] as? Bool ?? false
            let secs = (entry["secs"] as? NSNumber)?.doubleValue ?? 0
            let steps = plans[id]?["steps"] as? [[String: Any]] ?? []
            let states = steps.map { ($0["s"] as? NSNumber)?.intValue ?? 0 }
            let current = steps.first { ($0["s"] as? NSNumber)?.intValue == 1 }?["t"] as? String
            let todo = steps.map { step -> IslandAttributes.Todo in
                let began = (step["b"] as? NSNumber)?.doubleValue ?? 0
                return IslandAttributes.Todo(
                    t: String((step["t"] as? String ?? "").prefix(60)),
                    s: (step["s"] as? NSNumber)?.intValue ?? 0,
                    b: began > 0 ? Date(timeIntervalSince1970: began) : nil,
                    d: (step["d"] as? NSNumber)?.intValue)
            }
            let lim = limits[id] ?? []
            return IslandAttributes.Spirit(id: id, busy: busy, since: busy ? now.addingTimeInterval(-secs) : nil,
                                           done: states.filter { $0 == 2 }.count, total: steps.count,
                                           step: current ?? (busy ? lastAction(chat, of: id) : ""),
                                           todo: busy ? window(todo) : nil,
                                           lim5: (lim.first as? NSNumber)?.intValue,
                                           lim7: (lim.count > 2 ? lim[2] as? NSNumber : nil)?.intValue)
        }
    }

    /// Последнее действие агента в ленте (строка «do»); у записей без агента - Claude Code на ПК.
    static func lastAction(_ chat: [[String: Any]], of id: String) -> String {
        let text = chat.last { ($0["who"] as? String) == "do" && (($0["agent"] as? String) ?? "pc") == id }?["text"]
        return String((text as? String ?? "").prefix(80))
    }

    /// Окно плана для островка: последний готовый шаг, текущий и следующие - всего до limit.
    ///
    /// Шесть, а не четыре (владелец 03.10.2026): он смотрит на островок, чтобы
    /// понять, где работа встала, и для этого нужен хвост плана, а не один шаг.
    /// Выше поднимать нельзя - у Live Activity 4 КБ на всё состояние, и туда же
    /// идут духи, сводка и уровни голоса.
    static func window(_ todo: [IslandAttributes.Todo], limit: Int = 6) -> [IslandAttributes.Todo] {
        guard todo.count > limit else { return todo }
        let current = todo.firstIndex { $0.s == 1 } ?? todo.firstIndex { $0.s == 0 } ?? todo.count - 1
        let start = min(max(0, current - 1), todo.count - limit)
        return Array(todo[start..<start + limit])
    }

    /// Что показать: запись важнее всего, потом голос Джарвис, потом работа агентов.
    static func mode(voice: String, speaking: Bool, spirits: [IslandAttributes.Spirit]) -> IslandAttributes.Mode {
        if voice == "rec" { return .recording }
        if voice == "wait" { return .thinking }
        if speaking { return .speaking }
        return spirits.contains { $0.busy } ? .working : .quiet
    }

    static func line(mode: IslandAttributes.Mode, spirits: [IslandAttributes.Spirit], said: String) -> String {
        switch mode {
        case .recording: return "Слушаю… коснись очков ещё раз, чтобы отправить"
        case .thinking: return "Джарвис думает"
        case .speaking: return String(said.prefix(140))
        case .working:
            return ""  // строки духов уже говорят, кто чем занят
        case .quiet: return "Коснись очков, чтобы сказать Джарвис"
        }
    }
}
