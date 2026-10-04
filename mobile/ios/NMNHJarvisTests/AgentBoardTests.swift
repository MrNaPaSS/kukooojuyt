import XCTest
@testable import NMNHJarvis

final class AgentBoardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let state: [String: Any] = [
        "work": ["server": ["busy": true, "secs": 90], "pc": ["busy": false, "secs": 0]],
        "plans": ["server": ["name": "Островок", "steps": [["t": "раз", "s": 2], ["t": "два", "s": 1], ["t": "три", "s": 0]]]],
    ]

    func testParsesPlanAndWork() {
        let parsed = AgentBoard.parse(state, now: now)
        let plan = try? XCTUnwrap(parsed.plans["server"])
        XCTAssertEqual(plan?.name, "Островок")
        XCTAssertEqual(plan?.done, 1)
        XCTAssertEqual(plan?.steps.count, 3)
        XCTAssertEqual(plan?.current?.t, "два")
        XCTAssertEqual(parsed.work["server"]?.since, now.addingTimeInterval(-90))
        XCTAssertNil(parsed.work["pc"]?.since)
    }

    func testBusiestPrefersAgentWithPlan() {
        let parsed = AgentBoard.parse(state, now: now)
        XCTAssertEqual(AgentBoard.busiest(plans: parsed.plans, work: parsed.work), "server")
        XCTAssertEqual(AgentBoard.busiest(plans: [:], work: [:]), "server")
    }

    @MainActor func testLinkOpensNamedAgentOrBusiest() {
        let board = AgentBoard()
        board.open(URL(string: "jarvis://plan?agent=pc")!)
        XCTAssertEqual(board.focus, "pc")
        board.focus = nil
        board.open(URL(string: "jarvis://plan?agent=")!)
        XCTAssertEqual(board.focus, "server")
        board.focus = nil
        board.open(URL(string: "https://nmnh.trade")!)
        XCTAssertNil(board.focus)
    }

    func testIslandTodoWindowKeepsCurrentStep() {
        let todo = (0..<10).map { IslandAttributes.Todo(t: "шаг \($0)", s: $0 < 5 ? 2 : $0 == 5 ? 1 : 0) }
        let shown = IslandBuilder.window(todo)
        // Четыре строки вокруг текущего: один сделанный позади, текущий и два
        // следующих - больше не влезает в островок (владелец 03.10.2026).
        XCTAssertEqual(shown.map(\.t), ["шаг 4", "шаг 5", "шаг 6", "шаг 7"])
        XCTAssertEqual(IslandBuilder.window(Array(todo.prefix(3))).count, 3)
    }

    func testDecisionParsedForIsland() {
        let state: [String: Any] = ["decision": ["kind": "deploy", "id": "deploy", "agent": "server",
                                                 "title": "Server PC просит выложить правку", "text": "fix: x",
                                                 "options": ["Выложить", "Отклонить"], "simple": true]]
        let d = IslandBuilder.decision(from: state)
        XCTAssertEqual(d?.options, ["Выложить", "Отклонить"])
        XCTAssertEqual(d?.simple, true)
        XCTAssertNil(IslandBuilder.decision(from: [:]))
    }

    func testAddedAgentsFromRegistry() {
        let state: [String: Any] = ["agents": [["id": "jarvis", "name": "Джарвис", "color": "#ee4dd9"],
                                               ["id": "server2", "name": "Server 2", "color": "#3ddc97"]],
                                    "work": ["server2": ["busy": true, "secs": 30]]]
        let spirits = IslandBuilder.spirits(from: state, now: Date())
        XCTAssertEqual(spirits.map(\.id), ["jarvis", "server", "pc", "server2"])
        XCTAssertEqual(spirits.last?.name, "Server 2")
        XCTAssertEqual(spirits.last?.busy, true)
        XCTAssertEqual(GlassesAgents.name("server2"), "Server 2")
        XCTAssertEqual(GlassesAgents.short("server2"), "S2")
        GlassesAgents.learn([])
    }

    func testPairLinkParsed() {
        let link = Pairing.parse(URL(string: "jarvis://pair?code=AB12-CD_x9&api=https%3A%2F%2Fapi.example.com")!)
        XCTAssertEqual(link?.code, "AB12-CD_x9")
        XCTAssertEqual(link?.api?.host, "api.example.com")
        XCTAssertNil(Pairing.parse(URL(string: "jarvis://plan?agent=pc")!))
        XCTAssertNil(Pairing.parse(URL(string: "jarvis://pair?code=x'%3B")!)?.code)  // мусор - не код
        XCTAssertNil(Pairing.parse(URL(string: "jarvis://pair?code=ABCD&api=http://evil")!)?.api)  // только https
    }

    @MainActor func testDecisionVoiceLine() {
        let base = IslandAttributes.Decision(kind: "progress", id: "deploy", agent: "server", title: "Выкладка: идут тесты",
                                             text: "", options: [], simple: false, stage: "tests")
        XCTAssertNil(GlassesVoice.voiceLine(base))  // ход - молча, только итог
        var done = base
        done.stage = "done"
        XCTAssertEqual(GlassesVoice.voiceLine(done), "Выложено.")
    }

    func testDeployProgressStep() {
        let state: [String: Any] = ["decision": ["kind": "progress", "id": "deploy", "agent": "server",
                                                 "title": "Выкладка: идут тесты", "text": "", "options": [],
                                                 "simple": false, "stage": "fail", "failed_at": "tests"]]
        let d = IslandBuilder.decision(from: state)
        XCTAssertEqual(d?.stepIndex, 2)
        XCTAssertEqual(d?.simple, false)
    }

    /// Время шага доезжает с сервера: у готового - сколько занял, у текущего - когда взяли.
    func testIslandStepsCarryTheirTime() {
        let now = Date(timeIntervalSince1970: 2_000)
        let state: [String: Any] = [
            "work": ["pc": ["busy": true, "secs": 300]],
            "plans": ["pc": ["steps": [
                ["t": "Прочитать код", "s": 2, "b": 1_700, "d": 120],
                ["t": "Написать тест", "s": 1, "b": 1_900],
                ["t": "Выложить", "s": 0],
            ]]],
        ]

        let pc = IslandBuilder.spirits(from: state, now: now).first { $0.id == "pc" }
        let todo = pc?.todo ?? []

        XCTAssertEqual(todo.count, 3)
        XCTAssertEqual(todo[0].d, 120)
        XCTAssertEqual(todo[1].b, Date(timeIntervalSince1970: 1_900))
        XCTAssertNil(todo[2].b, "у шага впереди времени нет")
    }

    /// Лимит подписки доезжает до островка вместе с работой агента.
    func testIslandCarriesSubscriptionLimits() {
        let state: [String: Any] = [
            "work": ["pc": ["busy": true, "secs": 10]],
            "plans": [:],
            "limits": ["pc": [86, 1_800, 61, 90_000]],
        ]

        let pc = IslandBuilder.spirits(from: state, now: Date()).first { $0.id == "pc" }

        XCTAssertEqual(pc?.lim5, 86)
        XCTAssertEqual(pc?.lim7, 61)
        XCTAssertNil(IslandBuilder.spirits(from: ["work": [:], "plans": [:]], now: Date()).first?.lim5)
    }

    /// Лимит пишется двумя окнами, а неполный - тем, что есть.
    func testLimitTextShowsBothWindows() {
        XCTAssertEqual(LimitChip.text(five: 90, week: 55), "5ч 90% · нед 55%")
        XCTAssertEqual(LimitChip.text(five: 90, week: nil), "5ч 90%")
        XCTAssertEqual(LimitChip.text(five: nil, week: nil), "")
    }

    /// Подпись времени у готового шага - короткая: это край строки, а не отчёт.
    func testSpentReadsShort() {
        XCTAssertEqual(TodoLine.spent(0), "1 с")
        XCTAssertEqual(TodoLine.spent(45), "45 с")
        XCTAssertEqual(TodoLine.spent(120), "2 мин")
        XCTAssertEqual(TodoLine.spent(3_600), "1 ч")
        XCTAssertEqual(TodoLine.spent(5_400), "1 ч 30 м")
    }

    func testStepWithoutPlanIsLastAction() {
        let state: [String: Any] = [
            "work": ["pc": ["busy": true, "secs": 10]],
            "chat": [["who": "do", "agent": "pc", "text": "Read: page.tsx"],
                     ["who": "do", "agent": "server", "text": "Bash: тесты"],
                     ["who": "do", "agent": "pc", "text": "Bash: Check the PC's public IP"]],
        ]
        let spirits = IslandBuilder.spirits(from: state, now: Date())
        XCTAssertEqual(spirits.first { $0.id == "pc" }?.step, "Bash: Check the PC's public IP")
        XCTAssertEqual(spirits.first { $0.id == "server" }?.step, "")  // не работает - шага нет
    }

    func testIslandLinkPointsAtWorkingAgent() {
        let spirits = [
            IslandAttributes.Spirit(id: "jarvis", busy: true, since: nil, done: 0, total: 0, step: ""),
            IslandAttributes.Spirit(id: "server", busy: false, since: nil, done: 0, total: 0, step: ""),
            IslandAttributes.Spirit(id: "pc", busy: true, since: nil, done: 1, total: 3, step: "пишу"),
        ]
        XCTAssertEqual(planURL(spirits).absoluteString, "jarvis://plan?agent=pc")
    }
}
