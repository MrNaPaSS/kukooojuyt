import SwiftUI
import WidgetKit

/// Виджеты главного экрана и экрана блокировки в стиле B (выбор владельца 02.10.2026, «как Coucou»):
/// одно крупное число, духи на виду, остальное - цветными плитками; каждый виджет в трёх размерах.
///
/// Данные кладёт приложение в общую папку (SharedStore) при опросе сервера в фоне и просит
/// виджеты обновиться; сами виджеты в сеть не ходят.
struct PultEntry: TimelineEntry {
    let date: Date
    let dash: Dash
    let spirits: [IslandAttributes.Spirit]
    let fresh: Bool  // настоящие данные, а не образец
}

struct PultProvider: TimelineProvider {
    func placeholder(in context: Context) -> PultEntry { Self.sample }

    func getSnapshot(in context: Context, completion: @escaping (PultEntry) -> Void) {
        completion(Self.current() ?? Self.sample)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PultEntry>) -> Void) {
        let entry = Self.current() ?? Self.sample
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    static func current() -> PultEntry? {
        guard let dash = SharedStore.load(Dash.self, from: "dash.json") else { return nil }
        let spirits = SharedStore.load([IslandAttributes.Spirit].self, from: "spirits.json") ?? []
        return PultEntry(date: Date(), dash: dash, spirits: spirits, fresh: true)
    }

    static let sample = PultEntry(date: Date(), dash: .sample, spirits: [
        .init(id: "jarvis", busy: false, since: nil, done: 0, total: 0, step: ""),
        .init(id: "server", busy: true, since: Date().addingTimeInterval(-192), done: 2, total: 5, step: "Пишу тесты островка"),
        .init(id: "pc", busy: false, since: nil, done: 0, total: 0, step: ""),
    ], fresh: false)
}

// MARK: оформление

/// Код общий с приложением: там виджеты показывает галерея демо, без containerBackground.
let inWidget = Bundle.main.bundleURL.pathExtension == "appex"

/// Фон под новую iOS (владелец 03.10.2026): прозрачное стекло без цветного свечения -
/// цветными остаются только духи и имена. В режимах «Прозрачный» и «Тонированный» iOS этот фон
/// снимает и кладёт своё стекло сама.
struct CardBackground: View {
    var body: some View {
        ZStack {
            DashTheme.base.opacity(0.12)
            LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.03)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ContainerRelativeShape()
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.04)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
    }
}

extension View {
    @ViewBuilder func pultBackground() -> some View {
        if inWidget, #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { CardBackground() }
        } else {
            self.padding(16).background(CardBackground())
        }
    }

    @ViewBuilder func lockBackground() -> some View {
        if inWidget, #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { Color.clear }
        } else {
            self
        }
    }
}

/// Сколько назад пришли цифры - мелко, только если давно.
struct Freshness: View {
    let entry: PultEntry
    var body: some View {
        if !entry.fresh {
            Caption(text: "образец · открой приложение", color: DashTheme.faint, size: 10)
        } else if entry.dash.t > 0, Date().timeIntervalSince1970 - entry.dash.t > 20 * 60 {
            (Text("цифры ") + Text(Date(timeIntervalSince1970: entry.dash.t), style: .relative) + Text(" назад"))
                .font(.system(size: 10, weight: .medium)).foregroundStyle(DashTheme.faint).lineLimit(1)
        }
    }
}

/// Размер виджета: из WidgetKit или заданный галереей демо в приложении.
private struct Sized<Content: View>: View {
    @Environment(\.widgetFamily) private var envFamily
    var forced: WidgetFamily?
    let content: (WidgetFamily) -> Content
    var body: some View { content(forced ?? envFamily) }
}

/// Значок раздела в круге его цвета - вместо духа там, где речь не об агентах.
struct Badge: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: icon).font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(0.08)))
    }
}

private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

// MARK: Деньги

struct MoneyWidgetView: View {
    let entry: PultEntry
    var forced: WidgetFamily?
    var body: some View {
        let b = entry.dash.biz, d = entry.dash
        Sized(forced: forced) { family in
            VStack(alignment: .leading, spacing: 0) {
                switch family {
                case .systemSmall:
                    Badge(icon: "dollarsign", tint: DashTheme.money)
                    Spacer(minLength: 0)
                    Caption(text: "Комиссия сегодня")
                    BigNumber(text: Money.text(b.c1), size: 34)
                    Caption(text: "\(percent(d.dayProgress)) плана дня", color: DashTheme.money, size: 12)
                case .systemMedium:
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 0) {
                            Badge(icon: "dollarsign", tint: DashTheme.money)
                            Spacer(minLength: 0)
                            Caption(text: "Комиссия сегодня")
                            BigNumber(text: Money.text(b.c1), size: 34)
                            Caption(text: "\(percent(d.dayProgress)) плана дня", color: DashTheme.money, size: 12)
                        }
                        VStack(spacing: 8) {
                            Tile(label: "Годовой темп", value: Money.text(b.rr), tint: DashTheme.money, compact: true)
                            Tile(label: "Рефералы", value: "\(b.refs) · +\(b.ref30)", tint: DashTheme.tasks, compact: true)
                        }
                        .frame(width: 140)
                    }
                default:
                    HStack {
                        Badge(icon: "dollarsign", tint: DashTheme.money)
                        Spacer()
                        Caption(text: "цель \(Money.text(b.goal))")
                    }
                    Spacer(minLength: 10)
                    Caption(text: "Комиссия сегодня")
                    BigNumber(text: Money.text(b.c1), size: 46)
                    Bar(progress: d.dayProgress, tint: DashTheme.money).padding(.vertical, 8)
                    Caption(text: "план дня \(Money.text(b.day)) · сделано \(percent(d.dayProgress))", color: DashTheme.money, size: 12)
                    Spacer(minLength: 12)
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Tile(label: "За 7 дней", value: Money.text(b.c7), tint: DashTheme.money)
                            Tile(label: "Годовой темп", value: Money.text(b.rr), tint: DashTheme.trades, note: "\(percent(d.paceProgress)) плана")
                        }
                        HStack(spacing: 8) {
                            Tile(label: "Рефералы", value: "\(b.refs)", tint: DashTheme.tasks, note: "+\(b.ref30) за 30 дней")
                            Tile(label: "Подписки", value: "\(b.subs)", tint: DashTheme.server, note: Money.text(b.usdt30))
                        }
                    }
                    Freshness(entry: entry).padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pultBackground()
    }
}

// MARK: Сервер

struct ServerWidgetView: View {
    let entry: PultEntry
    var forced: WidgetFamily?
    var body: some View {
        let s = entry.dash.srv
        let ok = s.down.isEmpty && entry.dash.alerts.isEmpty
        Sized(forced: forced) { family in
            VStack(alignment: .leading, spacing: 0) {
                switch family {
                case .systemSmall:
                    HStack {
                        Badge(icon: "server.rack", tint: DashTheme.server)
                        Spacer()
                        Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(ok ? DashTheme.money : DashTheme.down)
                    }
                    Spacer(minLength: 0)
                    Caption(text: "Процессор")
                    BigNumber(text: "\(s.cpu)%", size: 34)
                    Caption(text: "RAM \(s.ram)% · диск \(s.disk)%", size: 12)
                case .systemMedium:
                    HStack {
                        Badge(icon: "server.rack", tint: DashTheme.server)
                        Text("Сервер").font(.system(size: 15, weight: .semibold)).foregroundStyle(DashTheme.ink)
                        Spacer()
                        Caption(text: ok ? "всё работает" : "есть сбой", color: ok ? DashTheme.money : DashTheme.down)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        Tile(label: "Процессор", value: "\(s.cpu)%", tint: DashTheme.server)
                        Tile(label: "Память", value: "\(s.ram)%", tint: DashTheme.tasks)
                        Tile(label: "Диск", value: "\(s.disk)%", tint: DashTheme.trades)
                    }
                default:
                    HStack {
                        Badge(icon: "server.rack", tint: DashTheme.server)
                        Text("Сервер").font(.system(size: 15, weight: .semibold)).foregroundStyle(DashTheme.ink)
                        Spacer()
                        Caption(text: ok ? "всё работает" : "есть сбой", color: ok ? DashTheme.money : DashTheme.down)
                    }
                    Spacer(minLength: 10)
                    Caption(text: "Процессор")
                    BigNumber(text: "\(s.cpu)%", size: 46)
                    Bar(progress: Double(s.cpu) / 100, tint: DashTheme.server).padding(.vertical, 8)
                    Spacer(minLength: 10)
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Tile(label: "Память", value: "\(s.ram)%", tint: DashTheme.tasks)
                            Tile(label: "Диск", value: "\(s.disk)%", tint: DashTheme.trades)
                        }
                        HStack(spacing: 8) {
                            Tile(label: "Копия базы", value: s.bk >= 0 ? "\(s.bk) мин" : "нет", tint: DashTheme.money)
                            Tile(label: "Ошибки 15 мин", value: "\(s.err)", tint: s.err > 0 ? DashTheme.down : DashTheme.server)
                        }
                    }
                    if !entry.dash.alerts.isEmpty { AlertsBar(alerts: entry.dash.alerts).padding(.top, 8) }
                    Freshness(entry: entry).padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pultBackground()
    }
}

// MARK: Агенты

struct AgentsWidgetView: View {
    let entry: PultEntry
    var forced: WidgetFamily?
    var body: some View {
        let busy = entry.spirits.filter(\.busy)
        let first = busy.first
        Sized(forced: forced) { family in
            VStack(alignment: .leading, spacing: 0) {
                switch family {
                case .systemSmall:
                    FullColor { Spirits(spirits: entry.spirits, size: 30) }
                    Spacer(minLength: 0)
                    Caption(text: busy.isEmpty ? "Агенты" : "Работает")
                    if let first {
                        FullColor { BigNumber(text: first.name, size: 30, color: SpiritView.color(first.id)) }
                    } else {
                        BigNumber(text: "все ждут", size: 24)
                    }
                    if let first {
                        // Шаг, а если его нет - лимит подписки: и то и другое
                        // полезнее слова «работает» (владелец 03.10.2026).
                        let fallback = LimitChip.text(five: first.lim5, week: first.lim7)
                        Caption(text: first.step.isEmpty ? fallback : first.step, color: DashTheme.ink2, size: 12)
                    }
                case .systemMedium:
                    AgentsPage(spirits: entry.spirits, size: 24)
                        .frame(maxHeight: .infinity)
                default:
                    HStack {
                        FullColor { Spirits(spirits: entry.spirits, size: 34) }
                        Spacer()
                        Caption(text: busy.isEmpty ? "все ждут" : "\(busy.count) работают")
                    }
                    Spacer(minLength: 14)
                    VStack(spacing: 10) {
                        ForEach(entry.spirits) { spirit in
                            VStack(alignment: .leading, spacing: 8) {
                                SpiritRow(spirit: spirit, size: 24)
                                if spirit.busy, spirit.total > 0 {
                                    Bar(progress: Double(spirit.done) / Double(spirit.total), tint: SpiritView.color(spirit.id))
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(spirit.busy ? 0.08 : 0.04)))  // стекло, без цвета агента
                        }
                    }
                    Spacer(minLength: 0)
                    Freshness(entry: entry)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pultBackground()
        .widgetURL(planURL(entry.spirits))  // нажал - план того, кто работает
    }
}

// MARK: Задачи и цели

struct TasksWidgetView: View {
    let entry: PultEntry
    var forced: WidgetFamily?
    var body: some View {
        let k = entry.dash.tasks, goals = entry.dash.goals
        Sized(forced: forced) { family in
            VStack(alignment: .leading, spacing: 0) {
                switch family {
                case .systemSmall:
                    Badge(icon: "target", tint: DashTheme.tasks)
                    Spacer(minLength: 0)
                    Caption(text: "Задачи агенту")
                    BigNumber(text: "\(k.w) в деле", size: 28)
                    Caption(text: k.a > 0 ? "ждут Y: \(k.a)" : "очередь \(k.q) · готово \(k.d)",
                            color: k.a > 0 ? DashTheme.warn : DashTheme.label, size: 12)
                case .systemMedium:
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 0) {
                            Badge(icon: "target", tint: DashTheme.tasks)
                            Spacer(minLength: 0)
                            Caption(text: "Задачи агенту")
                            BigNumber(text: "\(k.w) в деле", size: 26)
                            Caption(text: k.a > 0 ? "ждут Y: \(k.a)" : "очередь \(k.q)", color: k.a > 0 ? DashTheme.warn : DashTheme.label, size: 12)
                        }
                        VStack(spacing: 8) {
                            ForEach(Array(goals.prefix(2).enumerated()), id: \.offset) { _, g in
                                Tile(label: "Цель", value: g.t, tint: DashTheme.tasks, note: g.due, compact: true)
                            }
                        }
                        .frame(width: 170)
                    }
                default:
                    HStack {
                        Badge(icon: "target", tint: DashTheme.tasks)
                        Text("Задачи и цели").font(.system(size: 15, weight: .semibold)).foregroundStyle(DashTheme.ink)
                        Spacer()
                        Caption(text: "готово \(k.d)")
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        Tile(label: "В деле", value: "\(k.w)", tint: DashTheme.tasks)
                        Tile(label: "Очередь", value: "\(k.q)", tint: DashTheme.server)
                        Tile(label: "Ждут Y", value: "\(k.a)", tint: k.a > 0 ? DashTheme.warn : DashTheme.money)
                    }
                    if !k.now.isEmpty {
                        Text(k.now).font(.system(size: 14, weight: .medium)).foregroundStyle(DashTheme.ink2).lineLimit(1).padding(.top, 10)
                    }
                    Spacer(minLength: 10)
                    VStack(spacing: 8) {
                        ForEach(Array(goals.prefix(3).enumerated()), id: \.offset) { _, g in
                            Tile(label: g.due.isEmpty ? "Цель" : "Цель · \(g.due)", value: g.t, tint: DashTheme.tasks, compact: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Freshness(entry: entry)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pultBackground()
    }
}

// MARK: Пульт - всё сразу

struct PultWidgetView: View {
    let entry: PultEntry
    var forced: WidgetFamily?
    var body: some View {
        let d = entry.dash
        let busy = entry.spirits.filter(\.busy).count
        Sized(forced: forced) { family in
            VStack(alignment: .leading, spacing: 0) {
                switch family {
                case .systemSmall:
                    Spirits(spirits: entry.spirits, size: 26)
                    Spacer(minLength: 0)
                    Caption(text: "Комиссия сегодня")
                    BigNumber(text: Money.text(d.biz.c1), size: 32)
                    Caption(text: d.alerts.isEmpty ? "всё спокойно" : "тревог: \(d.alerts.count)",
                            color: d.alerts.isEmpty ? DashTheme.money : DashTheme.down, size: 12)
                case .systemMedium:
                    HStack {
                        Spirits(spirits: entry.spirits, size: 26)
                        Spacer()
                        Caption(text: busy == 0 ? "все ждут" : "\(busy) работают")
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        Tile(label: "Комиссия", value: Money.text(d.biz.c1), tint: DashTheme.money)
                        Tile(label: "Сделки", value: Money.signed(d.trades.pnl), tint: DashTheme.trades)
                        Tile(label: "Сервер", value: "CPU \(d.srv.cpu)%", tint: DashTheme.server)
                    }
                default:
                    HStack {
                        Spirits(spirits: entry.spirits, size: 30)
                        Spacer()
                        Caption(text: busy == 0 ? "все ждут" : "\(busy) работают")
                    }
                    Spacer(minLength: 12)
                    VStack(spacing: 8) {
                        if !d.alerts.isEmpty { AlertsBar(alerts: d.alerts).frame(maxWidth: .infinity, alignment: .leading) }
                        Tile(label: "Комиссия сегодня", value: Money.text(d.biz.c1), tint: DashTheme.money,
                             note: "\(percent(d.dayProgress)) плана дня", compact: true)
                        Tile(label: "Сервер", value: "CPU \(d.srv.cpu)% · \(d.srv.down.isEmpty ? "всё ✓" : "сбой")", tint: DashTheme.server,
                             compact: true)
                        Tile(label: "Сделки", value: "\(Money.signed(d.trades.pnl)) · \(d.trades.n)", tint: DashTheme.trades,
                             note: "в терминале \(d.people.online) из \(d.people.total)", compact: true)
                        if let goal = d.goals.first {
                            Tile(label: "Цель", value: goal.t, tint: DashTheme.tasks, note: goal.due, compact: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Freshness(entry: entry)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pultBackground()
    }
}

// MARK: Заметки - напоминания Джарвис со статусом

/// Как выглядит статус заметки: значок, цвет, подпись.
struct NoteStyle {
    let icon: String
    let tint: Color
    let label: String

    init(_ st: String) {
        switch st {
        case "done": (icon, tint, label) = ("checkmark.circle.fill", DashTheme.money, "выполнено")
        case "said": (icon, tint, label) = ("bell.badge.fill", DashTheme.warn, "ждёт ответа")
        case "waiting": (icon, tint, label) = ("hourglass", DashTheme.trades, "в ожидании")
        case "repeat": (icon, tint, label) = ("arrow.clockwise", DashTheme.server, "повтор")
        default: (icon, tint, label) = ("circle", DashTheme.label, "запланировано")
        }
    }
}

/// Строка заметки: значок статуса, время, текст (выполненное - зачёркнуто и тише).
struct NoteRow: View {
    let note: Dash.Note
    var big = false
    var body: some View {
        let style = NoteStyle(note.st)
        let done = note.st == "done"
        HStack(spacing: 9) {
            Image(systemName: style.icon).font(.system(size: big ? 15 : 13, weight: .semibold)).foregroundStyle(style.tint)
                .frame(width: big ? 18 : 16)
            Text(note.when.isEmpty ? note.time : "\(note.when) \(note.time)")
                .font(.system(size: big ? 13 : 12, weight: .semibold)).foregroundStyle(DashTheme.label)
                .frame(minWidth: big ? 44 : 38, alignment: .leading)
            Text(note.t).font(.system(size: big ? 15 : 14, weight: .medium))
                .foregroundStyle(done ? DashTheme.faint : DashTheme.ink).strikethrough(done, color: DashTheme.faint).lineLimit(1)
            Spacer(minLength: 0)
            if big && note.st != "planned" && note.st != "done" {
                Caption(text: style.label, color: style.tint, size: 11)
            }
        }
    }
}

struct NotesWidgetView: View {
    let entry: PultEntry
    var forced: WidgetFamily?
    var body: some View {
        let notes = entry.dash.notes
        let open = notes.filter { $0.st != "done" }
        let next = open.first
        let ask = notes.filter { $0.st == "said" }.count
        Sized(forced: forced) { family in
            VStack(alignment: .leading, spacing: 0) {
                switch family {
                case .systemSmall:
                    HStack {
                        Badge(icon: "bell.fill", tint: DashTheme.warn)
                        Spacer()
                        if ask > 0 { Caption(text: "ждут \(ask)", color: DashTheme.warn, size: 12) }
                    }
                    Spacer(minLength: 0)
                    if let next {
                        Caption(text: next.time.isEmpty ? NoteStyle(next.st).label : "\(next.when) \(next.time)")
                        Text(next.t).font(.system(size: 19, weight: .bold)).foregroundStyle(DashTheme.ink).lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Caption(text: open.count > 1 ? "ещё \(open.count - 1)" : NoteStyle(next.st).label,
                                color: NoteStyle(next.st).tint, size: 12)
                    } else {
                        BigNumber(text: "всё", size: 30)
                        Caption(text: "дел нет · скажи Джарвис", size: 12)
                    }
                case .systemMedium:
                    HStack {
                        Badge(icon: "bell.fill", tint: DashTheme.warn, size: 26)
                        Text("Заметки").font(.system(size: 15, weight: .semibold)).foregroundStyle(DashTheme.ink)
                        Spacer()
                        Caption(text: ask > 0 ? "ждут ответа: \(ask)" : "\(open.count) открыто", color: ask > 0 ? DashTheme.warn : DashTheme.label)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(notes.prefix(3).enumerated()), id: \.offset) { _, n in NoteRow(note: n) }
                    }
                    if notes.isEmpty { Caption(text: "Скажи: «Джарвис, напомни в 18:00 позвонить…»") }
                default:
                    HStack {
                        Badge(icon: "bell.fill", tint: DashTheme.warn)
                        Text("Заметки").font(.system(size: 16, weight: .semibold)).foregroundStyle(DashTheme.ink)
                        Spacer()
                        Caption(text: "\(notes.filter { $0.st == "done" }.count) из \(notes.count) сделано")
                    }
                    Spacer(minLength: 14)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(notes.prefix(7).enumerated()), id: \.offset) { _, n in
                            NoteRow(note: n, big: true)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(n.st == "done" ? 0.03 : 0.07)))
                        }
                    }
                    Spacer(minLength: 0)
                    Caption(text: "Скажи Джарвис: «напомни…», «сделал», «позже»", color: DashTheme.faint, size: 11)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .pultBackground()
    }
}

// MARK: Экран блокировки

struct LockMoneyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PultEntry
    var body: some View {
        let d = entry.dash
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: min(1, d.dayProgress)) {
                    Text("$")
                } currentValueLabel: {
                    Text(String(Int(d.biz.c1.rounded())))
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryInline:
                Text("NMNH \(Money.text(d.biz.c1)) из \(Money.text(d.biz.day))")
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Text("NMNH · комиссия").font(.system(size: 11, weight: .semibold))
                    Text(Money.text(d.biz.c1)).font(.system(size: 20, weight: .bold))
                    Text("план дня \(Money.text(d.biz.day)) · \(d.alerts.isEmpty ? "всё ок" : "⚠ \(d.alerts.count)")")
                        .font(.system(size: 11))
                }
            }
        }
        .widgetAccentable()
        .lockBackground()
    }
}

struct LockServerView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PultEntry
    var body: some View {
        let s = entry.dash.srv
        Group {
            if family == .accessoryCircular {
                Gauge(value: Double(min(100, s.cpu)) / 100) {
                    Text("CPU")
                } currentValueLabel: {
                    Text("\(s.cpu)")
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Сервер · \(s.down.isEmpty ? "всё работает" : "стоит \(s.down.count)")").font(.system(size: 11, weight: .semibold))
                    Text("CPU \(s.cpu)%  RAM \(s.ram)%").font(.system(size: 15, weight: .bold))
                    Text("диск \(s.disk)% · копия \(s.bk >= 0 ? "\(s.bk) мин" : "нет")").font(.system(size: 11))
                }
            }
        }
        .widgetAccentable()
        .lockBackground()
    }
}
