import SwiftUI
import WebKit

/// Приложение «NMNH Джарвис»: окно на страницу голоса админки и нативный режим кнопки очков.
///
/// Вёрстка и вход - те же, что на сайте: выкладка сайта сразу обновляет приложение. Всё, что
/// должно жить в фоне (звук, касания очков, запись), - в GlassesVoice, страница только включает
/// режим и показывает его состояние.
@main
struct NMNHJarvisApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate  // уведомления с кнопками
    @StateObject private var theme = PageTheme.shared
    @State private var splash = true  // заставка - один раз за запуск

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-demo") {
                DemoView()  // облачный симулятор: скриншоты островка без сервера
            } else {
                ZStack {
                    // Во весь экран, под часами и островком тоже (владелец 03.10.2026: сверху была тёмная
                    // полоса). Страница сама отступает от них (env(safe-area-inset-top)), фон и цвет часов -
                    // по её теме: на белой странице часы тёмные.
                    WebShell(url: URL(string: "https://www.nmnh.trade/admin/voice")!)
                        .ignoresSafeArea()
                        .background(theme.light ? Color.white : Color.black)
                        .preferredColorScheme(theme.light ? .light : .dark)
                        .planSheet()  // касание островка - план агента (jarvis://plan?agent=...)
                        .pairSheet()  // QR с ПК - вход без пароля (jarvis://pair?code=...)
                    if splash { LaunchSplash(shown: $splash) }  // молния и дух в островок (03.10.2026)
                }
                .onChange(of: splash) { _, on in if !on { Pairing.shared.firstRun() } }
            }
        }
    }
}

/// Тема страницы голоса: она шлёт {cmd: "theme", light: true/false} при загрузке и переключении.
@MainActor
final class PageTheme: ObservableObject {
    static let shared = PageTheme()
    @Published var light = false
}

struct WebShell: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Bridge { Bridge() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Признак для страницы: она в приложении, кнопку очков ведёт натив (window.nmnhNative).
        let marker = WKUserScript(source: "window.nmnhNative = { version: 1 };", injectionTime: .atDocumentStart,
                                  forMainFrameOnly: true)
        config.userContentController.addUserScript(marker)
        config.userContentController.add(context.coordinator, name: "nmnh")
        let view = WKWebView(frame: .zero, configuration: config)
        view.uiDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear  // под страницей - фон окна по её теме (PageTheme)
        view.scrollView.backgroundColor = .clear
        // Отступ от часов и островка делает сама страница; иначе iOS добавит свой, и сверху снова полоса.
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = view
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Мост страница <-> натив. Страница шлёт window.webkit.messageHandlers.nmnh.postMessage({...}):
///   {cmd: "glasses", on: true, api: "https://...", token: "...", refresh: "..."} - включить режим;
///   {cmd: "glasses", on: false} - выключить; {cmd: "press"} - кнопка «говорить» в режиме;
///   {cmd: "tokens", token, refresh} - страница обновила вход.
/// Состояние режима натив отдаёт в window.nmnhGlasses(state, error), если страница его задала.
final class Bridge: NSObject, WKScriptMessageHandler, WKUIDelegate {
    weak var webView: WKWebView?

    override init() {
        super.init()
        Task { @MainActor in
            GlassesVoice.shared.onState = { [weak self] state, error in self?.push(state, error) }
            // Вход по QR: токены админа - в хранилище страницы, как после входа паролем.
            Pairing.shared.deliver = { [weak self] access, refresh in
                let pair = (try? JSONSerialization.data(withJSONObject: [access, refresh]))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                self?.webView?.evaluateJavaScript(
                    "(function(t){localStorage.setItem('nmnh_mentor',t[0]);localStorage.setItem('nmnh_mentor_refresh',t[1]);location.reload();})(\(pair))")
            }
            IslandController.shared.onProblem = { [weak self] text in
                let safe = text.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "'")
                self?.webView?.evaluateJavaScript("window.nmnhIsland && window.nmnhIsland(\"\(safe)\")")
            }
            GlassesVoice.shared.onVoice = { [weak self] agent, phase, heard in
                let event: [String: String] = ["agent": agent, "phase": phase, "heard": heard]
                guard let json = (try? JSONSerialization.data(withJSONObject: event)).flatMap({ String(data: $0, encoding: .utf8) })
                else { return }
                self?.webView?.evaluateJavaScript("window.nmnhVoice && window.nmnhVoice(\(json))")
            }
            GlassesVoice.shared.onLevels = { [weak self] levels in
                let list = levels.map { String(format: "%.2f", $0) }.joined(separator: ",")
                self?.webView?.evaluateJavaScript("window.nmnhLevels && window.nmnhLevels([\(list)])")
            }
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else { return }
        Task { @MainActor in
            let voice = GlassesVoice.shared
            switch cmd {
            case "glasses":
                if body["on"] as? Bool == true {
                    guard let raw = body["api"] as? String, let base = URL(string: raw.hasSuffix("/") ? raw : raw + "/"),
                          let token = body["token"] as? String else { return }
                    voice.enable(base: base, access: token, refresh: body["refresh"] as? String ?? "")
                } else {
                    voice.disable()
                }
            case "press":
                voice.press()
            case "play":
                voice.playFromPage(body["audio"] as? String ?? "")
            case "mute":
                let map = body["agents"] as? [String: Bool] ?? [:]
                voice.applyMute(Set(map.filter(\.value).map(\.key)))
            case "speak":
                voice.speakAgents = body["on"] as? Bool ?? false
            case "hold":
                voice.hold(body["agent"] as? String ?? "jarvis", down: body["down"] as? Bool ?? false)
            case "theme":
                PageTheme.shared.light = body["light"] as? Bool ?? false
            case "tokens":
                if voice.enabled, let raw = body["api"] as? String, let base = URL(string: raw.hasSuffix("/") ? raw : raw + "/"),
                   let token = body["token"] as? String {
                    voice.enable(base: base, access: token, refresh: body["refresh"] as? String ?? "")
                }
            default:
                break
            }
        }
    }

    /// Микрофон для записи прямо со страницы (когда режим очков выключен) - без лишнего вопроса.
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host.hasSuffix("nmnh.trade") ? .grant : .prompt)
    }

    private func push(_ state: String, _ error: String) {
        let payload = (try? JSONSerialization.data(withJSONObject: [state, error])).flatMap { String(data: $0, encoding: .utf8) }
            ?? "[\"off\",\"\"]"
        webView?.evaluateJavaScript("window.nmnhGlasses && window.nmnhGlasses(...\(payload))")
    }
}
