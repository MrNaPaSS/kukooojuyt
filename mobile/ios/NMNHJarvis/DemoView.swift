import SwiftUI
import WidgetKit

/// Демо без сервера и входа (запуск с аргументом -demo): для облачного симулятора,
/// где снимаются скриншоты островка, его страниц и виджетов до установки на телефон.
/// Кнопки переключают островок так же, как его переключает настоящая работа.
struct DemoView: View {
    @State private var mode: IslandAttributes.Mode = .quiet
    @State private var page: DashPage = .agents
    @State private var gallery = false
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSince(start)
            ScrollView {
                VStack(spacing: 16) {
                    Text("Джарвис · демо").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    HStack(spacing: 26) {
                        ForEach(["jarvis", "server", "pc"], id: \.self) { id in
                            VStack(spacing: 8) {
                                SpiritView(id: id, busy: busy(id), size: 56, phase: phase + Double(id.count))
                                Text(name(id)).font(.system(size: 14, weight: .semibold)).foregroundStyle(SpiritView.color(id))
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    section("Состояние")
                    ForEach(Self.modes, id: \.0) { item in
                        chip(item.1, on: mode == item.0, id: "demo-\(item.0.rawValue)") { mode = item.0; show() }
                    }
                    section("Страница островка")
                    ForEach(DashPage.allCases, id: \.rawValue) { item in
                        chip(item.title, on: page == item, id: "page-\(item.rawValue)") { page = item; show() }
                    }
                    chip("Виджеты", on: false, id: "demo-widgets") { gallery = true }
                    chip("План агента (касание островка)", on: false, id: "demo-plan") { openPlan() }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .onAppear { show() }
        .fullScreenCover(isPresented: $gallery) { WidgetGallery(close: { gallery = false }) }
        .planSheet()
    }

    static let modes: [(IslandAttributes.Mode, String)] = [
        (.quiet, "Тихо"), (.working, "Агент работает"), (.recording, "Запись с очков"),
        (.thinking, "Джарвис думает"), (.speaking, "Джарвис говорит"),
    ]

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ title: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .accessibilityIdentifier(id)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(on ? Color.white.opacity(0.18) : Color.white.opacity(0.07)))
            .foregroundStyle(.white)
    }

    private func busy(_ id: String) -> Bool {
        switch mode {
        case .working: return id == "server" || id == "pc"
        case .recording, .thinking, .speaking: return id == "jarvis"
        case .quiet: return false
        }
    }

    private func name(_ id: String) -> String {
        IslandAttributes.Spirit(id: id, busy: false, since: nil, done: 0, total: 0, step: "").name
    }

    private func openPlan() {
        let now = Date()
        AgentBoard.shared.show(plans: [
            "server": AgentPlan(name: "Островок: план по касанию", steps: [
                .init(id: 0, t: "Прочитать островок и страницу голоса", s: 2),
                .init(id: 1, t: "Экран плана агента со стеклом", s: 1),
                .init(id: 2, t: "Виджеты под новую iOS", s: 0),
            ]),
            "pc": AgentPlan(name: "Посты канала", steps: [
                .init(id: 0, t: "Собрать новости", s: 2), .init(id: 1, t: "Написать пост", s: 2),
            ]),
        ], work: ["server": AgentWork(busy: true, since: now.addingTimeInterval(-192)),
                  "pc": AgentWork(busy: false, since: nil)])
        AgentBoard.shared.focus = "server"
    }

    private func show() {
        IslandController.shared.show(Self.state(mode, page: page), force: true)
    }

    static func state(_ mode: IslandAttributes.Mode, page: DashPage = .agents) -> IslandAttributes.ContentState {
        let now = Date()
        let working = mode == .working
        let spirits = [
            IslandAttributes.Spirit(id: "jarvis", busy: mode == .recording || mode == .thinking || mode == .speaking, since: now,
                                    done: 0, total: 0, step: ""),
            // Шесть шагов со временем - так владелец и видит работу на замке
            // (03.10.2026): что сделано и за сколько, что идёт сейчас, что впереди.
            IslandAttributes.Spirit(id: "server", busy: working, since: now.addingTimeInterval(-192), done: 2, total: 6,
                                    step: "Пишу тесты островка",
                                    todo: working ? [.init(t: "Прочитать код островка", s: 2, b: nil, d: 95),
                                                     .init(t: "Карточка агента на экране блокировки", s: 2, b: nil, d: 420),
                                                     .init(t: "Пишу тесты островка", s: 1, b: now.addingTimeInterval(-75), d: nil),
                                                     .init(t: "Виджеты на стекло", s: 0),
                                                     .init(t: "Снимки для владельца", s: 0),
                                                     .init(t: "Выложить и обновить стол", s: 0)] : nil,
                                    lim5: 42, lim7: 18),
            IslandAttributes.Spirit(id: "pc", busy: working, since: now.addingTimeInterval(-75), done: 1, total: 3,
                                    step: "Собираю посты канала", lim5: 86, lim7: 61),
        ]
        let said = "Агент закончил кнопку очков, тесты зелёные. Выложить?"
        return IslandAttributes.ContentState(mode: mode, spirits: spirits, recSince: mode == .recording ? now : nil,
                                             line: IslandBuilder.line(mode: mode, spirits: spirits, said: said),
                                             page: page, dash: .sample, recFor: "server",
                                             levels: mode == .recording ? [0.15, 0.4, 0.75, 0.55, 0.9, 0.6, 0.3, 0.7, 0.95, 0.5, 0.35, 0.6] : [])
    }
}

/// Все виджеты во всех размерах - для скриншотов: на симуляторе виджет на экран
/// программно не поставить, а вид здесь тот же код, что у настоящих виджетов.
struct WidgetGallery: View {
    let close: () -> Void
    private let entry = PultEntry(date: Date(), dash: .sample, spirits: DemoView.state(.working).spirits, fresh: true)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Виджеты").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    Button("Закрыть", action: close).accessibilityIdentifier("gallery-close").foregroundStyle(.white)
                }
                ForEach(Self.kinds, id: \.0) { kind in
                    Text(kind.0).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                        .accessibilityIdentifier("gallery-\(kind.0)")
                    HStack(alignment: .top, spacing: 12) {
                        tile(kind.1, .systemSmall)
                        Spacer(minLength: 0)
                    }
                    tile(kind.1, .systemMedium)
                    tile(kind.1, .systemLarge)
                }
            }
            .padding(16)
        }
        .background(LinearGradient(colors: [Color(red: 0.25, green: 0.12, blue: 0.35), Color(red: 0.06, green: 0.05, blue: 0.15)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    static let kinds: [(String, Int)] = [("Заметки", 5), ("Деньги", 0), ("Сервер", 1), ("Агенты", 2), ("Задачи и цели", 3),
                                         ("Пульт", 4)]

    @ViewBuilder private func tile(_ kind: Int, _ family: WidgetFamily) -> some View {
        let size: CGSize = family == .systemSmall ? CGSize(width: 170, height: 170)
            : family == .systemMedium ? CGSize(width: 364, height: 170) : CGSize(width: 364, height: 382)
        Group {
            switch kind {
            case 0: MoneyWidgetView(entry: entry, forced: family)
            case 1: ServerWidgetView(entry: entry, forced: family)
            case 2: AgentsWidgetView(entry: entry, forced: family)
            case 3: TasksWidgetView(entry: entry, forced: family)
            case 5: NotesWidgetView(entry: entry, forced: family)
            default: PultWidgetView(entry: entry, forced: family)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
