import AVFoundation
import MediaPlayer
import WidgetKit

/// Режим «Кнопка очков» в фоне (ТЗ docs/tz/glasses-ios-app-tz.md, этапы 2-4).
///
/// Пока режим включён, приложение - «плеер»: тишина играет в цикле, поэтому iOS не усыпляет
/// его и отдаёт ему нажатия кнопки плеера. Очки Oakley Meta шлют касание как такую кнопку.
/// Касание - запись с микрофона очков (HFP), второе - отправка Джарвис, ответ играет в очках
/// (A2DP). Новые реплики Джарвис из ленты тоже звучат, раз в 20 секунд.
@MainActor
final class GlassesVoice: NSObject, AVAudioPlayerDelegate {
    static let shared = GlassesVoice()

    /// Состояние для страницы: idle, rec, wait, off и текст ошибки.
    var onState: ((String, String) -> Void)?
    /// Голосовое для чата страницы: кому, sending / sent / failed, что расслышано. Страница сразу
    /// рисует свой пузырь и «агент думает» (владелец 03.10.2026: в чате было пусто до ответа).
    var onVoice: ((String, String, String) -> Void)?

    private(set) var enabled = false
    private var api: ServerAPI?
    private var machine = VoiceMachine()
    private var silence: AVAudioPlayer?
    private var voice: AVAudioPlayer?
    private var chimePlayer: AVAudioPlayer?
    private var recorder: AVAudioRecorder?
    private var ticker: Timer?
    private var poller: Timer?
    private var seenJarvis = -1
    private var spirits: [IslandAttributes.Spirit] = []
    private var said = ""
    private var dash: Dash?
    private var page = DashPage.agents
    private var widgetsAt = Date.distantPast
    private var target = "jarvis"          // кому уйдёт текущая запись
    private var levels: [Double] = []      // громкость для полосок в островке и на странице
    private var shownLevel: Double = 0     // сглаженная громкость: за голосом успевает, на щелчки нет

    /// Как часто меряем громкость и сколько полосок держим в волне.
    /// Двадцать четыре полоски при шаге 1/16 с - это полторы секунды речи:
    /// видно фразу, а не последний слог.
    static let meterStep = 1.0 / 16
    static let waveBars = 24
    /// Через сколько замеров обновлять островок: раз в секунду.
    static let islandEvery = 16
    private var meter: Timer?
    private var samples = 0
    /// Озвучивать ответы агента и Claude (переключатель звука на странице; Джарвис звучит всегда).
    /// Страница в WKWebView звук в фоне не играет - поэтому озвучка здесь (02.10.2026).
    var speakAgents = UserDefaults.standard.bool(forKey: "speakAgents") {
        didSet {
            UserDefaults.standard.set(speakAgents, forKey: "speakAgents")
            if !speakAgents { hush() }
        }
    }
    private var hushes = 0  // номер «замолчи»: озвучка, начатая до него, уже не играет

    /// Кнопка «без звука»: голос обрывается сразу, очередь кусков и готовящийся кусок - в мусор
    /// (владелец 03.10.2026: звук выключался, а фраза дочитывалась до конца).
    func hush() {
        hushes += 1
        voice?.stop()
        voice = nil
        chunks = []
        nextAudio?.cancel()
        nextAudio = nil
        pumping = false
        refreshIsland()
    }
    private var seenAgents = -1
    private var lastHer = ""      // последняя реплика Джарвис (ключ): новая - озвучить
    private var lastTheirs = ""   // последняя реплика агента или Claude
    private var polls = 0
    private var chunks: [(text: String, by: String)] = []   // что ещё дочитать
    private var nextAudio: Task<Data?, Never>?             // следующий кусок готовится, пока звучит этот
    private var pumping = false
    private var doneNote = ""         // «Отправлено: Агент ✓» - в островке на 3 с после отправки
    private var doneOK = true
    private var voiceCut = false      // голос прервало оповещение или звонок - продолжить
    private var glassesWere = false
    private var skipHer = false   // ответ Джарвис уже прозвучал (голосом или на текст со страницы)
    private var polling = false
    private var speaker = "jarvis"  // чей голос сейчас звучит - его дух в островке
    static let agents = ["jarvis", "server", "pc"]
    private let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent("glasses.m4a")

    // MARK: включение

    func enable(base: URL, access: String, refresh: String) {
        if let api {
            api.update(access: access, refresh: refresh)
        } else {
            api = ServerAPI(base: base, access: access, refresh: refresh)
        }
        if !refresh.isEmpty { Keychain.save(refresh, as: "refresh") }
        Keychain.save(base.absoluteString, as: "base")
        guard !enabled else { return report(""); }
        enabled = true
        machine = VoiceMachine()
        do {
            try idleSession()
            try startSilence()
        } catch {
            enabled = false
            return report("Звук не включился: \(error.localizedDescription)")
        }
        bindRemote()
        observeInterruptions()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
        // Чат - каждые 3 с: озвучка отставала от ПК на 10 с и больше (владелец 02.10.2026).
        poller = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollJarvis() }
        }
        Task { await pollJarvis() }  // запомнить, что уже было, без озвучки
        report("")
    }

    func disable() {
        enabled = false
        ticker?.invalidate(); ticker = nil
        poller?.invalidate(); poller = nil
        recorder?.stop(); recorder = nil
        meter?.invalidate(); meter = nil
        silence?.stop(); silence = nil
        unbindRemote()
        NotificationCenter.default.removeObserver(self)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        IslandController.shared.end()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onState?("off", "")
    }

    // MARK: аудиосессия

    /// Подключены ли Bluetooth-очки (или любая Bluetooth-гарнитура).
    private var glassesConnected: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType)
        }
    }

    /// Ожидание: только вывод (A2DP - качество лучше).
    /// Очки подключены - приложение «плеер»: только так iOS отдаёт ему касание очков, и на экране
    /// блокировки виден плеер. Очков нет - звук «смешиваемый»: фон жив, а плеера на экране нет
    /// (просьба владельца 02.10.2026: стандартный аудиовиджет без очков не нужен).
    private func idleSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: sessionOptions)
        try session.setActive(true)
        updateNowPlaying()
    }

    /// Сразу «запись и воспроизведение»: нажатие в островке и виджете включает микрофон без смены
    /// категории. Звук - в динамик (не в разговорный), очки - по Bluetooth; без очков - смешиваемый.
    /// Без HFP (.allowBluetooth): с ним iOS гнал голос в очки или наушники «как звонок», и при
    /// снятых очках озвучку было не слышно (02.10.2026). HFP - только на время записи с очков.
    private var sessionOptions: AVAudioSession.CategoryOptions {
        var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothA2DP]
        if !glassesConnected { options.insert(.mixWithOthers) }
        return options
    }

    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = enabled && glassesConnected ? [
            MPMediaItemPropertyTitle: "Джарвис: коснись очков, чтобы сказать",
            MPMediaItemPropertyArtist: "NMNH",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ] : nil
    }

    /// Запись: микрофон очков по HFP (или телефона). Категория та же, что в ожидании, - в фоне
    /// iOS не даёт её сменить, и запись из островка была тишиной (02.10.2026); меняем только вход.
    private func recordSession() throws {
        let session = AVAudioSession.sharedInstance()
        if glassesConnected {
            // Микрофон очков - только по HFP; в фоне iOS может не дать сменить настройку - тогда пишем
            // встроенным микрофоном, но запись всё равно идёт.
            try? session.setCategory(.playAndRecord, mode: .default, options: sessionOptions.union(.allowBluetooth))
        } else if session.category != .playAndRecord {
            try session.setCategory(.playAndRecord, mode: .default, options: sessionOptions)
        }
        try session.setActive(true)
        if let glasses = session.availableInputs?.first(where: { $0.portType == .bluetoothHFP }) {
            try? session.setPreferredInput(glasses)
        }
    }

    private func startSilence() throws {
        let player = try AVAudioPlayer(data: Tones.silence())
        player.numberOfLoops = -1
        player.play()
        silence = player
        updateNowPlaying()
    }

    private func chime(_ data: Data) {
        chimePlayer = try? AVAudioPlayer(data: data)
        chimePlayer?.play()
    }

    // MARK: кнопка очков

    private func bindRemote() {
        let center = MPRemoteCommandCenter.shared()
        for command in [center.togglePlayPauseCommand, center.playCommand, center.pauseCommand,
                        center.nextTrackCommand, center.previousTrackCommand] {
            command.isEnabled = true
            command.addTarget { [weak self] _ in
                Task { @MainActor in self?.press() }
                return .success
            }
        }
    }

    private func unbindRemote() {
        let center = MPRemoteCommandCenter.shared()
        for command in [center.togglePlayPauseCommand, center.playCommand, center.pauseCommand,
                        center.nextTrackCommand, center.previousTrackCommand] {
            command.removeTarget(nil)
        }
    }

    /// Режим не включён (приложение выгрузили, а нажали кнопку в островке или стук по крышке):
    /// включить по сохранённому входу - свежий токен сервер выдаст по refresh.
    @discardableResult
    func ensureEnabled() -> Bool {
        if enabled { return true }
        guard let raw = Keychain.load("base"), let base = URL(string: raw),
              let refresh = Keychain.load("refresh"), !refresh.isEmpty else { return false }
        enable(base: base, access: "", refresh: refresh)
        return enabled
    }

    /// Кнопка духа в островке и «Сказать Джарвис»: нажал - запись этому агенту, ещё раз - отправить.
    func talk(to agent: String) {
        guard ensureEnabled(), Self.agents.contains(agent) else { return }
        if machine.state == .idle { target = agent }
        press(keepTarget: true)
    }

    /// Удержание кнопки агента на странице: прижал - запись, отпустил - отправлено.
    func hold(_ agent: String, down: Bool) {
        guard ensureEnabled(), Self.agents.contains(agent) else { return }
        switch (down, machine.state) {
        case (true, .idle):
            target = agent
            press(keepTarget: true)
        case (false, .recording):
            press(keepTarget: true)
        default:
            break
        }
    }

    /// Нажатие очков или кнопки «говорить» на странице - одно и то же (очки - всегда Джарвис).
    func press(keepTarget: Bool = false) {
        guard enabled else { return }
        if !keepTarget, machine.state == .idle { target = "jarvis" }
        switch machine.press(at: Date().timeIntervalSince1970) {
        case .startRecording: startRecording()
        case .stopAndSend: stopAndSend()
        case .ignore: break
        }
    }

    private func onTick() {
        if machine.tick(at: Date().timeIntervalSince1970) == .stopAndSend { stopAndSend() }
    }

    // MARK: запись и ответ

    private func startRecording() {
        do {
            try recordSession()
            chime(Tones.listen)
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000,
                                           AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
            let rec = try AVAudioRecorder(url: recordURL, settings: settings)
            rec.isMeteringEnabled = true
            // Сигнал «слушаю» не должен попасть в запись.
            rec.record(atTime: rec.deviceCurrentTime + 0.3)
            recorder = rec
            levels = Array(repeating: 0, count: GlassesVoice.waveBars)
            shownLevel = 0
            talkWidget(target, since: Date())
            // Шестнадцать замеров в секунду: при полусекундном шаге волна шла
            // ступеньками и отставала от голоса (владелец 03.10.2026). Островку
            // при этом по-прежнему достаётся не чаще раза в секунду - его iOS
            // душит, и частые обновления ставили «Отправить» в очередь.
            meter = Timer.scheduledTimer(withTimeInterval: GlassesVoice.meterStep, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.sampleLevel() }
            }
            report("")
        } catch {
            machine.failed()
            talkWidget("", since: nil)
            try? idleSession()
            chime(Tones.error)
            report("Микрофон не включился: \(error.localizedDescription)")
        }
    }

    /// Громкость голоса: 0 - тишина, 1 - громко; последние WAVE_BARS замеров - полоски.
    ///
    /// Три вещи, без которых волна не похожа на голос (владелец 03.10.2026 -
    /// «дёрганная и не под голос»):
    ///
    /// 1. Децибелы - шкала логарифмическая, и обычная речь в ней жмётся к
    ///    верхнему краю. Берём корень, чтобы тихое было видно, а громкое не
    ///    упиралось в полку.
    /// 2. Мгновенное значение скачет на каждом слоге. Сглаживаем: вверх почти
    ///    сразу, вниз мягко - так ухо и слышит затухание.
    /// 3. Полосок всегда одно и то же число, пустые - нулями. Иначе первые
    ///    секунды волна растёт из ничего и выглядит смещённой.
    private func sampleLevel() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let db = Double(recorder.averagePower(forChannel: 0))  // -160...0
        let raw = max(0, min(1, (db + 55) / 55))
        let loud = min(1, sqrt(raw) * 1.15)
        shownLevel = loud > shownLevel ? shownLevel + (loud - shownLevel) * 0.55
                                       : shownLevel + (loud - shownLevel) * 0.15
        if levels.count < GlassesVoice.waveBars {
            levels = Array(repeating: 0, count: GlassesVoice.waveBars - levels.count) + levels
        }
        levels = Array((levels + [shownLevel]).suffix(GlassesVoice.waveBars))
        onLevels?(levels)
        // Островку - по-прежнему раз в секунду, хотя меряем мы в шестнадцать раз
        // чаще: iOS душит частые обновления Live Activity, и «Отправить» вставало
        // в очередь за полосками - таймер записи шёл дальше после отправки
        // (владелец 03.10.2026). Экран приложения получает каждый замер: там
        // ограничений нет, и волна там живая.
        samples += 1
        if samples % GlassesVoice.islandEvery == 0 { refreshIsland() }
    }

    /// Уровни громкости для страницы (волна при записи).
    var onLevels: (([Double]) -> Void)?

    /// Виджет «Говорить»: кому идёт запись (пусто - тишина).
    private func talkWidget(_ agent: String, since: Date?) {
        SharedStore.save(TalkState(recFor: agent, since: since), as: "talk.json")
        WidgetCenter.shared.reloadTimelines(ofKind: TalkState.kind)
    }

    private func stopAndSend() {
        onVoice?(target, "sending", "")
        talkWidget("", since: nil)
        meter?.invalidate(); meter = nil
        recorder?.stop()
        recorder = nil
        try? idleSession()
        chime(Tones.sent)
        report("")
        Task { await send() }
    }

    private func send() async {
        defer { machine.finished(); report("") }
        guard let api, let audio = try? Data(contentsOf: recordURL), !audio.isEmpty else {
            onVoice?(target, "failed", "")
            chime(Tones.error)
            return report("Запись пустая")
        }
        do {
            let reply = try await api.sendVoice(audio, to: target)
            onVoice?(target, reply.heard.isEmpty ? "failed" : "sent", reply.heard)
            if reply.heard.isEmpty {  // сервер не расслышал слов - ничего не отправил
                flashDone("Не расслышал слов", ok: false)
                chime(Tones.error)
            } else {
                flashDone("Отправлено: \(GlassesAgents.name(target)) ✓", ok: true)
            }
            if let mp3 = Data(base64Encoded: reply.audio), !mp3.isEmpty { play(mp3, by: target) }
            if target == "jarvis" { skipHer = true }  // её ответ попадёт в ленту - не озвучивать его второй раз
        } catch ServerAPI.Failure.unauthorized {
            onVoice?(target, "failed", "")
            chime(Tones.error)
            flashDone("Не отправилось: вход устарел", ok: false)
            report("Вход устарел: открой приложение и войди заново")
            disable()
        } catch {
            onVoice?(target, "failed", "")
            chime(Tones.error)
            flashDone("Не отправилось: сервер не отвечает", ok: false)
            report("Сервер не отвечает")
        }
    }

    /// Итог отправки в островке на 3 секунды, потом обычный вид.
    private func flashDone(_ text: String, ok: Bool) {
        doneNote = text
        doneOK = ok
        refreshIsland(alert: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.doneNote == text else { return }
            self.doneNote = ""
            self.refreshIsland(alert: true)
        }
    }

    /// Звук со страницы (ответ Джарвис на текст): WKWebView при фоновой сессии молчит - играем здесь.
    func playFromPage(_ base64: String) {
        guard let mp3 = Data(base64Encoded: base64), !mp3.isEmpty else { return }
        if !enabled { try? idleSession() }
        skipHer = true
        play(mp3, by: "jarvis")
    }

    private func play(_ mp3: Data, by agent: String = "jarvis") {
        let starts = !(voice?.isPlaying ?? false) || speaker != agent
        speaker = agent
        voice = try? AVAudioPlayer(data: mp3)
        voice?.delegate = self
        voice?.play()
        refreshIsland(alert: starts)  // заговорил - в островке сразу его дух и волна (без задержки 5 с)
    }

    /// Прочитать ответ целиком: куски по предложениям, первый звучит сразу, следующий готовится заранее.
    private func speak(_ text: String, by agent: String) {
        let parts = Self.pieces(text)
        guard !parts.isEmpty else { return }
        said = text
        chunks += parts.map { (text: $0, by: agent) }
        if !pumping { pump() }
    }

    private func pump() {
        guard let api, !chunks.isEmpty else {
            pumping = false
            nextAudio = nil
            refreshIsland()  // дочитала - островок складывается
            return
        }
        pumping = true
        let current = chunks.removeFirst()
        let ready = nextAudio
        nextAudio = nil
        let round = hushes
        Task {
            let audio: Data?
            if let ready { audio = await ready.value } else {
                audio = try? await api.speech(current.text, jarvis: current.by == "jarvis")
            }
            guard round == hushes else { return }  // пока готовился кусок, нажали «без звука»
            if let next = chunks.first {
                nextAudio = Task { try? await api.speech(next.text, jarvis: next.by == "jarvis") }
            }
            if let audio, !audio.isEmpty {
                play(audio, by: current.by)
            } else {
                pump()  // кусок не озвучился - дальше
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard player === self.voice else { return }
            if self.pumping { self.pump() } else { self.refreshIsland() }
        }
    }

    /// Куски для озвучки: по предложениям, не длиннее limit знаков.
    static func pieces(_ text: String, limit: Int = 350) -> [String] {
        var out: [String] = []
        var current = ""
        for sentence in text.split(omittingEmptySubsequences: true, whereSeparator: { "\n".contains($0) })
            .flatMap({ $0.split(separator: ".", omittingEmptySubsequences: true).map { $0 + "." } }) {
            let piece = sentence.trimmingCharacters(in: .whitespaces)
            if piece.count <= 1 { continue }
            if current.count + piece.count + 1 > limit, !current.isEmpty {
                out.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : " ") + piece
            while current.count > limit {
                out.append(String(current.prefix(limit)))
                current = String(current.dropFirst(limit))
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Островок: духи агентов, запись, голос Джарвис (IslandController сам гасит частые обновления).
    private func refreshIsland(alert: Bool = false) {
        guard enabled else { return }
        let speaking = voice?.isPlaying ?? false
        let mode = IslandBuilder.mode(voice: machine.label, speaking: speaking, spirits: spirits)
        var recSince: Date?
        if case let .recording(since) = machine.state { recSince = Date(timeIntervalSince1970: since) }
        // Пока отправляем: Джарвис думает, агенту - «Отправляю Агенту…».
        let line = mode == .thinking && target != "jarvis" ? "Отправляю: \(GlassesAgents.name(target))…"
            : IslandBuilder.line(mode: mode, spirits: spirits, said: said)
        IslandController.shared.show(IslandAttributes.ContentState(
            mode: mode, spirits: spirits, recSince: recSince, line: line, page: page, dash: dash,
            recFor: target, levels: mode == .recording ? levels : [], speaker: speaker,
            done: doneNote, doneOK: doneOK),
            force: mode == .recording || alert)  // без оповещения-раскрытия: оно обрывало голос
    }

    // MARK: реплики Джарвис по её инициативе

    private func pollJarvis() async {
        guard enabled, let api, machine.state == .idle, !polling else { return }
        polling = true
        defer { polling = false }
        guard let state = try? await api.agents(), let chat = state["chat"] as? [[String: Any]] else { return }
        spirits = IslandBuilder.spirits(from: state, now: Date())
        AgentBoard.shared.apply(state, now: Date())
        polls += 1
        if polls % 5 == 1, let fresh = try? await api.island() { dash = fresh }  // сводка - раз в 15 с
        // Островок и экран блокировки листают страницы: агенты, деньги, сервер, сделки, задачи.
        if dash != nil { page = DashPage(rawValue: (page.rawValue + 1) % DashPage.allCases.count) ?? .agents }
        if let dash { SharedStore.save(dash, as: "dash.json") }
        SharedStore.save(spirits, as: "spirits.json")
        // Виджеты - не чаще раза в 5 минут: у iOS дневной бюджет их обновлений.
        if Date().timeIntervalSince(widgetsAt) > 300 {
            widgetsAt = Date()
            WidgetCenter.shared.reloadAllTimelines()
        }
        let hers = chat.filter { ($0["agent"] as? String) == "jarvis" && ($0["who"] as? String) == "ai" }
        let theirs = chat.filter { ($0["agent"] as? String) != "jarvis" && ($0["who"] as? String) == "ai" }
        said = hers.last?["text"] as? String ?? said
        // Новое - по последней реплике, а не по числу: сервер держит 80 реплик на агента,
        // и в полном чате число не растёт - озвучка замолкала (02.10.2026).
        let herKey = Self.key(hers.last), theirKey = Self.key(theirs.last)
        let firstPass = seenJarvis < 0
        defer { seenJarvis = hers.count; seenAgents = theirs.count; lastHer = herKey; lastTheirs = theirKey; refreshIsland() }
        guard !firstPass else { return }  // первый проход - запомнить, что уже было, без озвучки
        if herKey != lastHer, !herKey.isEmpty, skipHer {
            skipHer = false  // это её ответ, уже сказанный
        } else if herKey != lastHer, !herKey.isEmpty, let last = hers.last?["text"] as? String {
            speak(last, by: "jarvis")
        } else if speakAgents, theirKey != lastTheirs, !theirKey.isEmpty, let last = theirs.last?["text"] as? String {
            let who = theirs.last?["agent"] as? String == "server" ? "server" : "pc"
            speak(last, by: who)  // целиком, как на ПК
        }
    }

    /// Открыли план агента (касание островка) - свежие шаги сразу, не ждать опроса.
    func refreshBoard() async {
        guard let api, let state = try? await api.agents() else { return }
        AgentBoard.shared.apply(state, now: Date())
    }

    /// Ключ реплики: кто, когда, начало текста.
    static func key(_ item: [String: Any]?) -> String {
        guard let item else { return "" }
        let text = item["text"] as? String ?? ""
        return "\(item["agent"] as? String ?? "")|\(item["at"] as? String ?? "")|\(text.count)|\(text.prefix(60))"
    }

    /// Что читать вслух: первые предложения, до ~350 знаков - звук стартует почти сразу.
    static func spoken(_ text: String, limit: Int = 350) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        if let end = head.lastIndex(where: { ".!?".contains($0) }), head.distance(from: head.startIndex, to: end) > limit / 3 {
            return String(head[...end])
        }
        return head + "…"
    }

    // MARK: звонки, Meta AI, музыка

    private func observeInterruptions() {
        // Очки подключили или сняли - переключить «плеер» (касание очков) и тихий фон. Только при
        // настоящей смене очков и не посреди голоса: перенастройка звука рвала озвучку (02.10.2026).
        glassesWere = glassesConnected
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.enabled, self.recorder == nil else { return }
                let now = self.glassesConnected
                guard now != self.glassesWere, !(self.voice?.isPlaying ?? false) else { return }
                self.glassesWere = now
                try? self.idleSession()
                self.silence?.play()
            }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                               queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let kind = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                guard let self, self.enabled else { return }
                if kind == .began {
                    self.voiceCut = self.voice?.isPlaying ?? false || self.pumping
                    return
                }
                // Прерывание кончилось (звонок, оповещение островка, Siri) - голос дочитывает дальше.
                try? AVAudioSession.sharedInstance().setActive(true)
                self.silence?.play()  // вернуть приложению роль плеера
                if self.voiceCut {
                    self.voiceCut = false
                    if let voice = self.voice, voice.currentTime < voice.duration { voice.play() } else if self.pumping { self.pump() }
                }
            }
        }
    }

    private func report(_ error: String) {
        onState?(enabled ? machine.label : "off", error)
        refreshIsland()
    }
}
