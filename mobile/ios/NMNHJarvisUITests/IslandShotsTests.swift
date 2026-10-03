import XCTest

/// Скриншоты для владельца до установки на телефон: островок в каждом состоянии и на каждой
/// странице сводки, плюс галерея виджетов всех размеров. Папка - переменная SHOTS_DIR
/// (xcodebuild передаёт её как TEST_RUNNER_SHOTS_DIR); симулятор пишет прямо на диск Mac.
final class IslandShotsTests: XCTestCase {
    private let modes = ["quiet", "working", "recording", "thinking", "speaking"]
    private let pages = ["1-money", "2-server", "3-trades", "4-tasks"]
    private lazy var dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory()
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = true
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        app.launchArguments = ["-demo"]
        app.launch()
    }

    func testIslandStates() throws {
        for (i, mode) in modes.enumerated() {
            tap("demo-\(mode)")
            tap("page-0")
            save("a\(i + 1)-\(mode)-app")
            islandShots("a\(i + 1)-\(mode)")
        }
    }

    func testIslandPages() throws {
        tap("demo-working")
        for page in pages {
            let parts = page.split(separator: "-")
            tap("page-\(parts[0])")
            islandShots("b\(page)")
        }
    }

    func testPlanSheet() throws {
        tap("demo-plan")
        sleep(2)
        save("d1-plan-server")
        tap("plan-pc")
        save("d2-plan-pc")
        tap("plan-jarvis")
        save("d3-plan-empty")
    }

    /// Решение владельца первым: выкладка, вопрос, ход выкладки, сбой - в островке.
    func testDecisionScenes() throws {
        tap("demo-working")
        for (i, scene) in ["deploy", "choice", "progress", "fail"].enumerated() {
            tap("demo-\(scene)")
            islandShots("e\(i + 1)-\(scene)")
        }
        tap("demo-nodecision")
    }

    /// Экран блокировки во всех сценах (та же вёрстка, что у Live Activity на замке).
    func testLockGallery() throws {
        tap("demo-lock")
        sleep(2)
        for i in 1...4 {
            save(String(format: "f%02d-lock", i))
            app.swipeUp(velocity: .slow)
            sleep(1)
        }
    }

    /// Заставка: молнии, дух в центре, полёт в островок, выглядывает и машет.
    func testSplash() throws {
        tap("demo-splash")
        for (i, wait) in [0.3, 0.9, 0.9, 1.0].enumerated() {
            Thread.sleep(forTimeInterval: wait)
            save("g\(i + 1)-splash")
        }
    }

    func testConnectSheet() throws {
        tap("demo-connect")
        sleep(2)
        save("h1-connect")
    }

    func testWidgetGallery() throws {
        tap("demo-widgets")
        sleep(2)
        for i in 1...14 {
            save(String(format: "c%02d-widgets", i))
            app.swipeUp(velocity: .slow)
            sleep(1)
        }
    }

    private func tap(_ id: String) {
        app.activate()
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 10), id)
        button.tap()
        sleep(1)
    }

    /// Свёрнутый островок на рабочем столе и развёрнутый долгим нажатием.
    private func islandShots(_ name: String) {
        XCUIDevice.shared.press(.home)
        sleep(3)
        save("\(name)-island")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.2)
        sleep(2)
        save("\(name)-expanded")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
        sleep(1)
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
