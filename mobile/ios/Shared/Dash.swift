import Foundation

/// Сводка пульта для островка и виджетов (GET /api/admin/agents/island, pult_island.py).
struct Dash: Codable, Hashable {
    struct Biz: Codable, Hashable {
        var c1: Double = 0, c7: Double = 0, day: Double = 0
        var rr: Double = 0, plan: Double = 0, goal: Double = 0
        var refs: Int = 0, ref30: Int = 0, subs: Int = 0, usdt30: Double = 0
    }
    struct Srv: Codable, Hashable {
        var cpu: Int = 0, ram: Int = 0, disk: Int = 0
        var down: [String] = []
        var err: Int = 0, fail: Int = 0, bk: Int = -1, up: Int = 0
    }
    /// Нагрузка сервера кольцами (pult_hosts.card): сервер терминала и сервер агентов (04.10.2026).
    struct Host: Codable, Hashable {
        var name: String = ""
        var online: Bool = false
        var cpu: Int?, ram: Int?, disk: Int?
        var cpu_note: String = "", ram_note: String = "", disk_note: String = ""
    }
    struct Trades: Codable, Hashable { var n: Int = 0, pnl: Double = 0, win: Int = 0, open: Int = 0 }
    struct People: Codable, Hashable { var online: Int = 0, total: Int = 0, day: Int = 0 }
    struct Tasks: Codable, Hashable { var w: Int = 0, q: Int = 0, a: Int = 0, d: Int = 0, now: String = "" }
    struct Goal: Codable, Hashable { var t: String, due: String }
    /// Напоминание Джарвис (pult_remind.notes): st - planned, said (ждёт ответа «сделал?»), done, waiting, repeat.
    struct Note: Codable, Hashable { var t: String, time: String, when: String, st: String }
    /// Сторож (pult_island._watch): сделки на сопровождении, биржи, пауза процессов, сайт и API.
    struct Watch: Codable, Hashable {
        struct Ex: Codable, Hashable { var n: String, ms: Int, worst: Int, err: Int, streams: Int, drops: Int
            var calls: Int { ms > 0 || worst > 0 ? 1 : 0 } }
        var open: Int = 0
        var ex: [Ex] = []
        var lag: Int = 0
        var lagRole: String = ""
        var api: Int = 0
        var site: Int = 0
    }

    var t: Double = 0
    var biz = Biz()
    var srv = Srv()
    var trades = Trades()
    var people = People()
    var tasks = Tasks()
    var goals: [Goal] = []
    var cal: [[String]] = []
    var alerts: [String] = []
    var notes: [Note] = []
    var watch = Watch()
    var hosts: [Host] = []

    static func decode(_ data: Data) -> Dash? { try? JSONDecoder().decode(Dash.self, from: data) }

    /// Комиссия сегодня против плана дня, 0...1+.
    var dayProgress: Double { biz.day > 0 ? biz.c1 / biz.day : 0 }
    /// Годовой темп против плана.
    var paceProgress: Double { biz.plan > 0 ? biz.rr / biz.plan : 0 }

    /// Демо и превью: выдуманные цифры, не с живого сервера (исходники приложения собираются в
    /// открытом репозитории - настоящих денег, целей и дел здесь быть не должно, 03.10.2026).
    static let sample = Dash(
        t: Date().timeIntervalSince1970,
        biz: Biz(c1: 12.40, c7: 86.10, day: 10, rr: 1800, plan: 3000, goal: 100_000, refs: 5, ref30: 1, subs: 1, usdt30: 20),
        srv: Srv(cpu: 53, ram: 42, disk: 31, down: [], err: 0, fail: 0, bk: 80, up: 70),
        trades: Trades(n: 3, pnl: 42.50, win: 2, open: 1),
        people: People(online: 2, total: 8, day: 2),
        tasks: Tasks(w: 1, q: 2, a: 1, d: 29, now: "Островок iPhone · виджеты"),
        goals: [Goal(t: "Цель года", due: "декабрь"), Goal(t: "Цель месяца", due: "конец месяца")],
        cal: [["10.10", "Встреча"], ["12.10", "Выкладка приложения"]],
        alerts: [],
        // Заметок в образце нет: пока нет данных с сервера, виджет пустой, без выдуманных дел (03.10.2026).
        notes: [],
        watch: Watch(open: 3, ex: [.init(n: "binance", ms: 0, worst: 0, err: 0, streams: 12, drops: 0),
                                   .init(n: "weex", ms: 262, worst: 422, err: 0, streams: 0, drops: 0)],
                     lag: 457, lagRole: "market", api: 200, site: 200),
        hosts: [Host(name: "Сервер терминала", online: true, cpu: 42, ram: 49, disk: 32,
                     cpu_note: "0.83 на 2 ядра", ram_note: "1.86 из 3.8 ГБ", disk_note: "11.9 из 37.7 ГБ"),
                Host(name: "Сервер агентов", online: true, cpu: 12, ram: 23, disk: 25,
                     cpu_note: "0.24 на 2 ядра", ram_note: "0.85 из 3.8 ГБ", disk_note: "9.3 из 37.7 ГБ")])
}

// Codable с пропущенными полями: сервер старее приложения не должен ломать островок.
extension Dash.Biz { init(from d: Decoder) throws { let c = try d.container(keyedBy: K.self)
    c1 = (try? c.decode(Double.self, forKey: .c1)) ?? 0; c7 = (try? c.decode(Double.self, forKey: .c7)) ?? 0
    day = (try? c.decode(Double.self, forKey: .day)) ?? 0; rr = (try? c.decode(Double.self, forKey: .rr)) ?? 0
    plan = (try? c.decode(Double.self, forKey: .plan)) ?? 0; goal = (try? c.decode(Double.self, forKey: .goal)) ?? 0
    refs = (try? c.decode(Int.self, forKey: .refs)) ?? 0; ref30 = (try? c.decode(Int.self, forKey: .ref30)) ?? 0
    subs = (try? c.decode(Int.self, forKey: .subs)) ?? 0; usdt30 = (try? c.decode(Double.self, forKey: .usdt30)) ?? 0 }
    private enum K: String, CodingKey { case c1, c7, day, rr, plan, goal, refs, ref30, subs, usdt30 } }

extension Dash { init(from d: Decoder) throws { let c = try d.container(keyedBy: K.self)
    t = (try? c.decode(Double.self, forKey: .t)) ?? 0
    biz = (try? c.decode(Biz.self, forKey: .biz)) ?? Biz(); srv = (try? c.decode(Srv.self, forKey: .srv)) ?? Srv()
    trades = (try? c.decode(Trades.self, forKey: .trades)) ?? Trades(); people = (try? c.decode(People.self, forKey: .people)) ?? People()
    tasks = (try? c.decode(Tasks.self, forKey: .tasks)) ?? Tasks(); goals = (try? c.decode([Goal].self, forKey: .goals)) ?? []
    cal = (try? c.decode([[String]].self, forKey: .cal)) ?? []; alerts = (try? c.decode([String].self, forKey: .alerts)) ?? []
    notes = (try? c.decode([Note].self, forKey: .notes)) ?? []
    watch = (try? c.decode(Watch.self, forKey: .watch)) ?? Watch()
    hosts = (try? c.decode([Host].self, forKey: .hosts)) ?? [] }
    private enum K: String, CodingKey { case t, biz, srv, trades, people, tasks, goals, cal, alerts, notes, watch, hosts } }

/// Адрес сервера и ключ виджетов - в общей папке: по ним виджет сам забирает сводку (06.10.2026).
struct WidgetAuth: Codable {
    let base: String
    let key: String
}

/// Общая папка приложения и расширения (App Group): виджеты читают то, что приложение получило в фоне.
enum SharedStore {
    /// Установка через AltServer (бесплатный Apple ID) переписывает имя группы под учётку и кладёт настоящее в
    /// Info.plist ключом ALTAppGroups. По старому имени папка не находилась: приложение и виджеты писали каждое в
    /// свою, и виджеты экрана блокировки показывали образец ($12.40) вместо цифр (06.10.2026).
    static let group = (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.first
        ?? "group.trade.nmnh.jarvis"

    private static var folder: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static func save<T: Encodable>(_ value: T, as name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

enum Money {
    /// 12.4 -> «$12.40», 1800 -> «$1 800», 1000000 -> «$1 млн».
    static func text(_ v: Double) -> String {
        if abs(v) >= 1_000_000 { return "$\(trim(v / 1_000_000)) млн" }
        if abs(v) >= 1000 { return "$" + grouped(Int(v.rounded())) }
        return String(format: "$%.2f", v)
    }

    static func signed(_ v: Double) -> String { (v >= 0 ? "+" : "-") + text(abs(v)) }

    private static func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }
}
