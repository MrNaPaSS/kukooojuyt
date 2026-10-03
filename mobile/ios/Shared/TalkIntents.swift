import AppIntents
import Foundation

/// Команды «говорить агенту» (просьба владельца 02.10.2026):
/// - кнопки духов в островке: нажал - запись этому агенту, нажал ещё раз - отправлено;
/// - «Сказать Джарвис» для касания задней панели (Настройки → Универсальный доступ → Касание).
/// Островок у Apple понимает только нажатия, удержание туда не передаётся.
/// Файл общий с расширением островка: там команда только объявлена (флаг WIDGET),
/// выполняет её приложение (LiveActivityIntent работает в процессе приложения).
@available(iOS 18.0, *)
struct TalkIntent: LiveActivityIntent, AudioRecordingIntent {
    static var title: LocalizedStringResource = "Говорить агенту"
    static var description = IntentDescription("Начать или отправить голосовое Джарвис, агенту на сервере или Claude.")
    static var openAppWhenRun = false

    @Parameter(title: "Кому") var agent: String

    init() { agent = "jarvis" }
    init(agent: String) { self.agent = agent }

    func perform() async throws -> some IntentResult {
        #if !WIDGET
        await GlassesVoice.shared.talk(to: agent)
        #endif
        return .result()
    }
}

/// Кнопка решения в островке и на замке: выкладка («Выложить» / «Отклонить») или вариант ответа
/// агенту (владелец 03.10.2026). Выполняет приложение - POST /api/admin/agents/decide.
@available(iOS 18.0, *)
struct DecideIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Ответить агенту"
    static var description = IntentDescription("Выложить правку или выбрать вариант ответа агенту.")
    static var openAppWhenRun = false

    @Parameter(title: "Что") var kind: String
    @Parameter(title: "Номер") var id: String
    @Parameter(title: "Вариант") var pick: Int

    init() {
        kind = ""
        id = ""
        pick = 0
    }

    init(kind: String, id: String, pick: Int) {
        self.kind = kind
        self.id = id
        self.pick = pick
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET
        await GlassesVoice.shared.decide(kind: kind, id: id, pick: pick)
        #endif
        return .result()
    }
}

@available(iOS 18.0, *)
struct SpeakJarvisIntent: AudioRecordingIntent {
    static var title: LocalizedStringResource = "Сказать Джарвис"
    static var description = IntentDescription("Первое касание - запись Джарвис, второе - отправить.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        #if !WIDGET
        await GlassesVoice.shared.talk(to: "jarvis")
        #endif
        return .result()
    }
}

#if !WIDGET
/// Команда видна в приложении «Команды» без настройки - её и ставят на касание задней панели.
@available(iOS 18.0, *)
struct JarvisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SpeakJarvisIntent(), phrases: ["Сказать \(.applicationName)"],
                    shortTitle: "Сказать Джарвис", systemImageName: "mic.fill")
    }
}
#endif
