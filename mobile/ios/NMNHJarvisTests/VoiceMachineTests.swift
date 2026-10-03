import XCTest
@testable import NMNHJarvis

final class VoiceMachineTests: XCTestCase {
    func testFirstPressRecordsSecondSends() {
        var m = VoiceMachine()
        XCTAssertEqual(m.press(at: 100), .startRecording)
        XCTAssertEqual(m.label, "rec")
        XCTAssertEqual(m.press(at: 105), .stopAndSend)
        XCTAssertEqual(m.label, "wait")
    }

    func testBounceIsIgnored() {
        var m = VoiceMachine()
        XCTAssertEqual(m.press(at: 100), .startRecording)
        XCTAssertEqual(m.press(at: 100.3), .ignore)  // дребезг кнопки, не второе нажатие
        XCTAssertEqual(m.label, "rec")
    }

    func testPressWhileWaitingIsIgnored() {
        var m = VoiceMachine()
        _ = m.press(at: 100)
        _ = m.press(at: 102)
        XCTAssertEqual(m.press(at: 110), .ignore)
        m.finished()
        XCTAssertEqual(m.press(at: 111), .startRecording)
    }

    func testLongRecordingSendsItself() {
        var m = VoiceMachine()
        _ = m.press(at: 0)
        XCTAssertEqual(m.tick(at: 59), .ignore)
        XCTAssertEqual(m.tick(at: 60), .stopAndSend)
        XCTAssertEqual(m.label, "wait")
    }

    func testFailedStartReturnsToIdle() {
        var m = VoiceMachine()
        _ = m.press(at: 0)
        m.failed()
        XCTAssertEqual(m.state, .idle)
    }
}

final class TonesTests: XCTestCase {
    func testSilenceIsValidWav() {
        let data = Tones.silence(seconds: 1, rate: 8000)
        XCTAssertEqual(data.count, 44 + 8000 * 2)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
    }

    func testChimeLength() {
        let data = Tones.chime([(440, 0.1), (880, 0.1)], rate: 10_000)
        XCTAssertEqual(data.count, 44 + 2000 * 2)
    }
}

final class IslandBuilderTests: XCTestCase {
    private let state: [String: Any] = [
        "work": ["server": ["busy": true, "secs": 90], "pc": ["busy": false, "secs": 0]],
        "plans": ["server": ["name": "Кнопка очков", "steps": [["t": "тесты", "s": 2], ["t": "выкладка", "s": 1], ["t": "отчёт", "s": 0]]]],
    ]

    func testSpiritsFromAgentsState() {
        let now = Date(timeIntervalSince1970: 1000)
        let spirits = IslandBuilder.spirits(from: state, now: now)
        XCTAssertEqual(spirits.map(\.id), ["jarvis", "server", "pc"])
        let agent = spirits[1]
        XCTAssertTrue(agent.busy)
        XCTAssertEqual(agent.since, Date(timeIntervalSince1970: 910))
        XCTAssertEqual(agent.done, 1)
        XCTAssertEqual(agent.total, 3)
        XCTAssertEqual(agent.step, "выкладка")
        XCTAssertFalse(spirits[2].busy)
    }

    func testModePriority() {
        let spirits = IslandBuilder.spirits(from: state, now: Date())
        XCTAssertEqual(IslandBuilder.mode(voice: "rec", speaking: true, spirits: spirits), .recording)
        XCTAssertEqual(IslandBuilder.mode(voice: "wait", speaking: false, spirits: spirits), .thinking)
        XCTAssertEqual(IslandBuilder.mode(voice: "idle", speaking: true, spirits: spirits), .speaking)
        XCTAssertEqual(IslandBuilder.mode(voice: "idle", speaking: false, spirits: spirits), .working)
        XCTAssertEqual(IslandBuilder.mode(voice: "idle", speaking: false, spirits: []), .quiet)
    }

    func testLineDoesNotRepeatSpirits() {
        let spirits = IslandBuilder.spirits(from: state, now: Date())
        XCTAssertEqual(IslandBuilder.line(mode: .working, spirits: spirits, said: ""), "")  // без повтора строк духов
        XCTAssertEqual(IslandBuilder.line(mode: .speaking, spirits: spirits, said: "Готово"), "Готово")
    }
}

final class DashTests: XCTestCase {
    func testDecodesServerDigest() throws {
        let json = """
        {"t": 1790962513, "biz": {"c1": 12.4, "c7": 86.1, "day": 5, "rr": 1800, "plan": 3000, "goal": 100000,
         "refs": 5, "ref30": 1, "subs": 1, "usdt30": 20},
         "srv": {"cpu": 53, "ram": 42, "disk": 31, "down": [], "err": 0, "fail": 0, "bk": 80, "up": 70},
         "trades": {"n": 3, "pnl": 42.5, "win": 2, "open": 1}, "people": {"online": 2, "total": 8, "day": 2},
         "tasks": {"w": 0, "q": 0, "a": 0, "d": 29, "now": ""},
         "goals": [{"t": "цель года", "due": "декабрь"}], "cal": [], "alerts": []}
        """
        let dash = try XCTUnwrap(Dash.decode(Data(json.utf8)))
        XCTAssertEqual(dash.biz.c1, 12.4)
        XCTAssertEqual(dash.srv.cpu, 53)
        XCTAssertEqual(dash.goals.first?.due, "декабрь")
        XCTAssertTrue(dash.notes.isEmpty)  // сервер без заметок - пусто, не ошибка
        XCTAssertGreaterThan(dash.dayProgress, 2)  // 12.4 из 5
    }

    func testOlderServerWithoutSomeParts() throws {
        let dash = try XCTUnwrap(Dash.decode(Data(#"{"biz": {"c1": 3}}"#.utf8)))
        XCTAssertEqual(dash.biz.c1, 3)
        XCTAssertEqual(dash.srv.cpu, 0)
        XCTAssertTrue(dash.alerts.isEmpty)
    }

    func testMoneyText() {
        XCTAssertEqual(Money.text(12.4), "$12.40")
        XCTAssertEqual(Money.text(1800), "$1 800")
        XCTAssertEqual(Money.text(1_000_000), "$1 млн")
        XCTAssertEqual(Money.signed(-5), "-$5.00")
    }

    func testIslandStateFitsActivityLimit() throws {
        // У iOS предел 4 КБ на состояние Live Activity.
        let state = IslandAttributes.ContentState(mode: .working, spirits: [], recSince: nil, line: "", page: .money, dash: .sample)
        XCTAssertLessThan(try JSONEncoder().encode(state).count, 4096)
    }
}


@MainActor
final class SpeechPickTests: XCTestCase {
    func testKeyChangesWithNewReplyEvenWhenCountIsSame() {
        let a: [String: Any] = ["agent": "pc", "at": "21:40", "text": "Готово"]
        let b: [String: Any] = ["agent": "pc", "at": "21:41", "text": "Готово"]
        XCTAssertNotEqual(GlassesVoice.key(a), GlassesVoice.key(b))
        XCTAssertEqual(GlassesVoice.key(nil), "")
    }

    func testPiecesCoverWholeText() {
        let long = String(repeating: "Первое предложение длинное. ", count: 40)
        let parts = GlassesVoice.pieces(long)
        XCTAssertGreaterThan(parts.count, 2)
        XCTAssertTrue(parts.allSatisfy { $0.count <= 350 })
        XCTAssertEqual(parts.joined(separator: " ").filter { $0 == "." }.count, 40)  // ничего не потеряли
    }

    func testSpokenCutsAtSentence() {
        let long = String(repeating: "Первое предложение длинное. ", count: 30)
        let out = GlassesVoice.spoken(long)
        XCTAssertLessThanOrEqual(out.count, 351)
        XCTAssertTrue(out.hasSuffix("."))
        XCTAssertEqual(GlassesVoice.spoken("Коротко."), "Коротко.")
    }
}
