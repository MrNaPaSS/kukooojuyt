import SwiftUI

/// Стиль B, выбор владельца 02.10.2026 («как Coucou»): мягкие тёмные карточки, цветное свечение
/// снизу, духи на виду, одно крупное число, остальное - цветными плитками и плашками.
enum DashTheme {
    static let money = Color(red: 0.19, green: 0.82, blue: 0.35)    // #30d158
    static let server = Color(red: 0.37, green: 0.62, blue: 1.0)    // #5e9eff
    static let trades = Color(red: 1.0, green: 0.62, blue: 0.04)    // #ff9f0a
    static let tasks = Color(red: 0.75, green: 0.35, blue: 0.95)    // #bf5af2
    static let up = money
    static let down = Color(red: 1.0, green: 0.36, blue: 0.40)
    static let warn = Color(red: 1.0, green: 0.74, blue: 0.27)
    static let ink = Color(red: 0.96, green: 0.96, blue: 0.97)      // #f5f6f8
    static let ink2 = Color(red: 0.85, green: 0.86, blue: 0.88)     // #d9dce1
    static let label = Color(red: 0.56, green: 0.58, blue: 0.61)    // #8e939c
    static let faint = Color(red: 0.44, green: 0.45, blue: 0.49)    // #6f747d
    static let base = Color(red: 0.07, green: 0.063, blue: 0.094)   // #121018
}

/// Страницы островка остались в данных (приложение их листает), вид теперь один - карточка.
enum DashPage: Int, CaseIterable, Codable {
    case agents, money, server, trades, tasks

    var title: String {
        switch self {
        case .agents: return "Агенты"
        case .money: return "Деньги"
        case .server: return "Сервер"
        case .trades: return "Сделки"
        case .tasks: return "Задачи и цели"
        }
    }
}

/// Подпись мелким серым.
struct Caption: View {
    let text: String
    var color: Color = DashTheme.label
    var size: CGFloat = 12.5
    var body: some View {
        Text(text).font(.system(size: size, weight: .medium)).foregroundStyle(color).lineLimit(1)
    }
}

/// Главное число карточки.
struct BigNumber: View {
    let text: String
    var size: CGFloat = 38
    var color: Color = DashTheme.ink
    var body: some View {
        Text(text).font(.system(size: size, weight: .bold)).tracking(-0.8).foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.5)
    }
}

/// Плитка-стекло: подпись и значение; цвет - только у пометки снизу (владелец 03.10.2026: без цветных плашек).
struct Tile: View {
    let label: String
    let value: String
    let tint: Color
    var note = ""
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Caption(text: label, size: compact ? 11 : 12)
            Text(value).font(.system(size: compact ? 16 : 19, weight: .semibold)).foregroundStyle(DashTheme.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            if !note.isEmpty { Caption(text: note, color: tint, size: 11) }
        }
        .padding(.horizontal, compact ? 10 : 13)
        .padding(.vertical, compact ? 8 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: compact ? 13 : 16, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

/// Плашка: значок слева, короткий текст.
struct Pill: View {
    let text: String
    let tint: Color
    let icon: String
    init(_ text: String, tint: Color, icon: String) {
        self.text = text
        self.tint = tint
        self.icon = icon
    }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(DashTheme.ink).lineLimit(1)
        }
        .padding(.leading, 8).padding(.trailing, 11).padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

/// Тонкая полоса прогресса.
struct Bar: View {
    let progress: Double
    let tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.09))
                Capsule().fill(tint).frame(width: max(4, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 4)
    }
}

/// Тревоги - красной плашкой.
struct AlertsBar: View {
    let alerts: [String]
    var body: some View {
        if let first = alerts.first {
            Pill(alerts.count > 1 ? "\(first) · ещё \(alerts.count - 1)" : first, tint: DashTheme.down,
                 icon: "exclamationmark.triangle.fill")
        }
    }
}

/// Карточка агента для островка и экрана блокировки: крупный дух, имя, статус, шаг, плашки сводки.
struct AgentCard: View {
    let state: IslandAttributes.ContentState
    var ghost: CGFloat = 46

    var body: some View {
        let spirit = lead(state)
        HStack(alignment: .top, spacing: 14) {
            SpiritView(id: spirit.id, busy: spirit.busy || state.mode != .quiet, size: ghost)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(spirit.name).font(.system(size: 16, weight: .bold)).foregroundStyle(DashTheme.ink)
                    Caption(text: status(spirit))
                }
                Text(doing(spirit)).font(.system(size: 15, weight: .medium)).foregroundStyle(DashTheme.ink2).lineLimit(2)
                pills.padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var pills: some View {
        if let dash = state.dash {
            HStack(spacing: 7) {
                if dash.alerts.isEmpty {
                    Pill("\(Money.text(dash.biz.c1)) сегодня", tint: DashTheme.money, icon: "dollarsign.circle.fill")
                } else {
                    AlertsBar(alerts: dash.alerts)
                }
                Pill("CPU \(dash.srv.cpu)%", tint: DashTheme.server, icon: "cpu")
            }
        }
    }

    private func status(_ s: IslandAttributes.Spirit) -> String {
        switch state.mode {
        case .recording: return "слушает"
        case .thinking: return "думает"
        case .speaking: return "говорит"
        case .working where s.busy:
            // Без слова «работает»: оно ничего не добавляет к духу и таймеру
            // рядом (владелец 03.10.2026). Говорим то, чего на экране нет.
            return s.total > 0 ? "план \(s.done)/\(s.total)" : "без плана"
        default: return "все ждут"
        }
    }

    private func doing(_ s: IslandAttributes.Spirit) -> String {
        switch state.mode {
        case .recording, .thinking, .speaking: return state.line
        case .working where !s.step.isEmpty: return s.step
        default: return state.line.isEmpty ? "Коснись очков, чтобы сказать Джарвис" : state.line
        }
    }
}

/// Главный дух: при записи и голосе - Джарвис, иначе первый занятый.
func lead(_ s: IslandAttributes.ContentState) -> IslandAttributes.Spirit {
    if s.mode == .recording, let target = s.spirits.first(where: { $0.id == s.recFor }) {
        return target  // запись идёт этому агенту
    }
    if s.mode == .speaking, let voice = s.spirits.first(where: { $0.id == s.speaker }) {
        return voice  // говорит не обязательно Джарвис: ответ агента или Claude озвучивается его духом
    }
    let voice: [IslandAttributes.Mode] = [.recording, .thinking, .speaking]
    if voice.contains(s.mode), let j = s.spirits.first(where: { $0.id == "jarvis" }) {
        return j
    }
    return freshest(s.spirits.filter(\.busy)) ?? s.spirits.first
        ?? IslandAttributes.Spirit(id: "jarvis", busy: false, since: nil, done: 0, total: 0, step: "")
}

/// Из работающих - тот, кто последним взял шаг (агент с планом, Джарвис последней). Раньше брали первого по
/// порядку, и Codex с Clawdbot в конце списка на островке не появлялись никогда (владелец 04.10.2026).
func freshest(_ busy: [IslandAttributes.Spirit]) -> IslandAttributes.Spirit? {
    func began(_ s: IslandAttributes.Spirit) -> Date {
        s.todo?.first { $0.s == 1 }?.b ?? s.since ?? .distantPast
    }
    let agents = busy.filter { $0.id != "jarvis" }
    let planned = agents.filter { $0.total > 0 }
    return (planned.isEmpty ? agents : planned).max { began($0) < began($1) } ?? busy.first
}


/// Страница сводки для островка и экрана блокировки (стиль B): заголовок и три плитки.
/// Островок листает их по очереди (приложение меняет page раз в 10 с); при записи и голосе - агент.
struct IslandPage: View {
    let state: IslandAttributes.ContentState
    var body: some View {
        let voice: [IslandAttributes.Mode] = [.recording, .thinking, .speaking]
        if voice.contains(state.mode) || state.page == .agents || state.dash == nil {
            if state.mode == .recording { RecordingCard(state: state) } else { AgentCard(state: state) }
        } else if let d = state.dash {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(state.page.title).font(.system(size: 14, weight: .bold)).foregroundStyle(DashTheme.ink)
                    Spacer()
                    if !d.alerts.isEmpty { AlertsBar(alerts: d.alerts) }
                }
                HStack(spacing: 8) { tiles(d) }
            }
        }
    }

    @ViewBuilder private func tiles(_ d: Dash) -> some View {
        switch state.page {
        case .money:
            Tile(label: "Сегодня", value: Money.text(d.biz.c1), tint: DashTheme.money, compact: true)
            Tile(label: "План дня", value: Money.text(d.biz.day), tint: DashTheme.money, compact: true)
            Tile(label: "Темп", value: Money.text(d.biz.rr), tint: DashTheme.trades, compact: true)
        case .server:
            Tile(label: "CPU", value: "\(d.srv.cpu)%", tint: DashTheme.server, compact: true)
            Tile(label: "Память", value: "\(d.srv.ram)%", tint: DashTheme.tasks, compact: true)
            Tile(label: "Службы", value: d.srv.down.isEmpty ? "все ✓" : "стоит \(d.srv.down.count)",
                 tint: d.srv.down.isEmpty ? DashTheme.money : DashTheme.down, compact: true)
        case .trades:
            Tile(label: "Итог дня", value: Money.signed(d.trades.pnl), tint: DashTheme.trades, compact: true)
            Tile(label: "Сделок", value: "\(d.trades.n)", tint: DashTheme.trades, compact: true)
            Tile(label: "В терминале", value: "\(d.people.online) из \(d.people.total)", tint: DashTheme.server, compact: true)
        default:
            let next = d.notes.first { $0.st != "done" }
            Tile(label: "Заметка", value: next?.t ?? "дел нет", tint: DashTheme.warn,
                 note: next.map { $0.time.isEmpty ? NoteStyle($0.st).label : $0.time } ?? "", compact: true)
            Tile(label: "Задачи агенту", value: "\(d.tasks.w) в деле", tint: DashTheme.tasks, compact: true)
        }
    }
}
