import XCTest
@testable import NMNHJarvis

/// Окна агентов на замке: кому открыть, кому обновить, кому закрыть (AgentActivityPlan).
final class AgentActivityPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func spirit(_ id: String, busy: Bool = true, done: Int = 1, total: Int = 3,
                        began: TimeInterval = 0, title: String? = nil) -> IslandAttributes.Spirit {
        let todo = [IslandAttributes.Todo(t: "раз", s: 2, b: nil, d: 30),
                    IslandAttributes.Todo(t: "два", s: 1, b: now.addingTimeInterval(began), d: nil),
                    IslandAttributes.Todo(t: "три", s: 0, b: nil, d: nil)]
        return IslandAttributes.Spirit(id: id, busy: busy, since: now, done: done, total: total, step: "два",
                                       todo: total > 0 ? todo : nil, title: title)
    }

    func testOpensWindowForEveryoneWorkingByPlan() {
        let steps = AgentActivityPlan.plan(
            spirits: [spirit("jarvis", total: 0), spirit("server"), spirit("pc", busy: false),
                      spirit("codex", title: "Codex")],
            open: [])
        XCTAssertEqual(Set(steps), [.open("server"), .open("codex")])
    }

    func testUpdatesOpenAndClosesFinished() {
        let steps = AgentActivityPlan.plan(spirits: [spirit("server"), spirit("pc", busy: false)],
                                           open: ["server", "pc"])
        XCTAssertEqual(steps, [.close("pc"), .update("server")])
    }

    func testClosesAgentGoneFromRegistry() {
        XCTAssertEqual(AgentActivityPlan.plan(spirits: [], open: ["clawdbot"]), [.close("clawdbot")])
    }

    func testWorkingWithoutPlanStillGetsWindow() {
        // 05.10.2026: все работающие - на замке; без плана окно показывает текущий шаг. Джарвис - в общей карточке.
        XCTAssertEqual(AgentActivityPlan.plan(spirits: [spirit("server", total: 0)], open: ["server"]),
                       [.update("server")])
        XCTAssertEqual(AgentActivityPlan.plan(spirits: [spirit("jarvis", total: 0)], open: []), [])
    }

    func testLimitGivesPlacesToFreshestAndKeepsOpenOnes() {
        let max = AgentActivityPlan.maxWindows
        let open = (0..<max - 1).map { "a\($0)" }
        let spirits = open.map { spirit($0, began: -3600) }
            + [spirit("old", began: -600), spirit("new", began: -5)]
        let steps = AgentActivityPlan.plan(spirits: spirits, open: open)
        // Одно свободное место - тому, кто взял шаг последним; открытые не трогаем.
        XCTAssertEqual(steps.filter { if case .open = $0 { return true } else { return false } }, [.open("new")])
        XCTAssertEqual(steps.filter { if case .update = $0 { return true } else { return false } }.count, max - 1)
        XCTAssertFalse(steps.contains(.close("a0")))
    }

    func testClosedPlaceGoesToWaitingAgent() {
        let max = AgentActivityPlan.maxWindows
        let open = (0..<max).map { "a\($0)" }
        let spirits = open.dropFirst().map { spirit($0) } + [spirit("next")]
        let steps = AgentActivityPlan.plan(spirits: spirits, open: open)
        XCTAssertEqual(steps.first, .close("a0"))
        XCTAssertTrue(steps.contains(.open("next")))
    }

    func testFinishedStateShowsFullProgress() {
        let state = AgentActivityPlan.finished(spirit("server", done: 2, total: 3))
        XCTAssertTrue(state.finished)
        XCTAssertFalse(state.spirit.busy)
        XCTAssertEqual(state.spirit.done, 3)
        XCTAssertEqual(AgentActivityPlan.closeAfter, 20)
    }

    func testStepStartIsCurrentStep() {
        XCTAssertEqual(spirit("server", began: -42).stepStarted, now.addingTimeInterval(-42))
        XCTAssertNil(spirit("server", total: 0).stepStarted)
    }

    func testUpcomingLineFoldsStepsBeyondWindow() {
        // В окне плана виден один шаг впереди, всего их впереди пять.
        let line = AgentActivityPlan.upcomingLine(spirit("server", done: 1, total: 7))
        XCTAssertEqual(line, "Дальше: три · ещё 4")
        XCTAssertEqual(AgentActivityPlan.upcomingLine(spirit("server", done: 1, total: 3), names: 1), "Дальше: три")
        var last = spirit("server", done: 1, total: 1)
        last.todo = [IslandAttributes.Todo(t: "раз", s: 2, b: nil, d: 30)]
        XCTAssertNil(AgentActivityPlan.upcomingLine(last))
    }

    func testRegistryAgentKeepsColorAlongsideOthers() {
        GlassesAgents.extra = [.init(id: "clawdbot", name: "Clawdbot", hex: "#ffd60a")]
        var codex = spirit("codex", title: "Codex")
        codex.hex = "#30d158"
        GlassesAgents.remember(codex)
        GlassesAgents.remember(spirit("server"))  // встроенный - не в списке добавленных
        XCTAssertEqual(GlassesAgents.extra.map(\.id), ["clawdbot", "codex"])
        XCTAssertEqual(GlassesAgents.name("codex"), "Codex")
        GlassesAgents.extra = []
    }

    func testTerminalHostCarriesServices() {
        let agents = Dash.Host(name: "Сервер агентов", online: true)
        let terminal = Dash.Host(name: "Сервер терминала", online: true)
        XCTAssertTrue(HostRows.isTerminal(terminal, in: [agents, terminal]))
        XCTAssertFalse(HostRows.isTerminal(agents, in: [agents, terminal]))
        XCTAssertTrue(HostRows.isTerminal(agents, in: [agents]))
    }
}
