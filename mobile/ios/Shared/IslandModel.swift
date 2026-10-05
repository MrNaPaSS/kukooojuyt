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
        var decision: Decision? = nil  // что ждёт решения владельца - показывается первым (03.10.2026)
    }

    /// Выкладка правки или вопрос агента с вариантами (pult_decision на сервере). На замке, в
    /// островке и в уведомлении - кнопки вариантов; сложный вопрос (simple = false) - «Открыть».
    struct Decision: Codable, Hashable {
        var kind: String     // deploy, choice
        var id: String
        var agent: String
        var title: String
        var text: String
        var options: [String]
        var simple: Bool
        var stage: String? = nil     // kind progress: queued, start, tests, push, restart, done, fail
        var failedAt: String? = nil  // на каком шаге встала выкладка

        /// Шаги выкладки по порядку - как их отмечает сервер (pult_deploystate).
        static let steps: [(id: String, label: String)] = [
            ("queued", "Заявка"), ("start", "Проверка"), ("tests", "Тесты"),
            ("push", "В main"), ("restart", "Запуск"), ("done", "Готово"),
        ]

        /// Номер текущего шага; у упавшей - шаг, где встала.
        var stepIndex: Int {
            let at = stage == "fail" ? (failedAt?.isEmpty == false ? failedAt! : "start") : (stage ?? "queued")
            return Self.steps.firstIndex { $0.id == at } ?? 0
        }

        /// Ключ для «уже показали уведомление»: новое решение - новый ключ.
        var key: String { "\(kind)|\(id)|\(stage ?? "")|\(text.prefix(40))" }
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
        var limw: String? = nil  // подпись длинного окна: «нед» у Claude, «мес» у Codex на Go (04.10.2026)
        var title: String? = nil  // имя добавленного агента (Server 2); у встроенных - nil
        var hex: String? = nil    // его цвет «#rrggbb»
    }

    struct Todo: Codable, Hashable {
        var t: String
        var s: Int       // 0 впереди, 1 в работе, 2 готово
        var b: Date?     // когда шаг взяли - из него живой таймер текущего
        var d: Int?      // сколько занял готовый, секунды
    }
}

extension IslandAttributes.Spirit {
    var name: String { title ?? GlassesAgents.name(id) }
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
        // Добавленные с ПК агенты (реестр pult_agents) - после встроенных, со своим именем и цветом.
        let registry = (state["agents"] as? [[String: Any]] ?? []).compactMap { a -> (String, String, String)? in
            guard let id = a["id"] as? String, !order.contains(id) else { return nil }
            return (id, a["name"] as? String ?? id, a["color"] as? String ?? "#8e939c")
        }
        let all = order + registry.map(\.0)
        let spirits = all.map { id -> IslandAttributes.Spirit in
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
                                           lim5: ((lim.first as? NSNumber)?.intValue).flatMap { $0 < 0 ? nil : $0 },
                                           lim7: ((lim.count > 2 ? lim[2] as? NSNumber : nil)?.intValue).flatMap { $0 < 0 ? nil : $0 },  // -1: тариф без процентов (Grok)
                                           limw: lim.count > 4 ? lim[4] as? String : nil,
                                           title: registry.first { $0.0 == id }?.1,
                                           hex: registry.first { $0.0 == id }?.2)
        }
        GlassesAgents.learn(spirits)
        return spirits
    }

    /// Что ждёт решения владельца: поле decision ответа агентов. Текст короче - у Live Activity
    /// 4 КБ на всё состояние.
    static func decision(from state: [String: Any]) -> IslandAttributes.Decision? {
        guard let d = state["decision"] as? [String: Any], let kind = d["kind"] as? String,
              let id = d["id"] as? String else { return nil }
        let options = (d["options"] as? [String] ?? []).prefix(4).map { String($0.prefix(24)) }
        return IslandAttributes.Decision(
            kind: kind, id: id, agent: d["agent"] as? String ?? "pc",
            title: String((d["title"] as? String ?? "").prefix(60)),
            text: String((d["text"] as? String ?? "").prefix(160)),
            options: options, simple: (d["simple"] as? Bool ?? false) && !options.isEmpty,
            stage: d["stage"] as? String, failedAt: d["failed_at"] as? String)
    }

    /// Последнее действие агента в ленте (строка «do»); у записей без агента - Claude Code на ПК.
    static func lastAction(_ chat: [[String: Any]], of id: String) -> String {
        let text = chat.last { ($0["who"] as? String) == "do" && (($0["agent"] as? String) ?? "pc") == id }?["text"]
        return String((text as? String ?? "").prefix(80))
    }

    /// Окно плана для островка: последний готовый шаг, текущий и следующие - всего до limit.
    ///
    /// Четыре строки: шесть не влезали - последняя обрезалась краем островка и
    /// замка (владелец 03.10.2026, снимок). Один готовый позади, текущий и два
    /// следующих - видно, где работа идёт и сколько осталось.
    static func window(_ todo: [IslandAttributes.Todo], limit: Int = 4) -> [IslandAttributes.Todo] {
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
