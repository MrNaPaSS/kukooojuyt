import Foundation

/// Что делать по нажатию кнопки очков. Чистая логика без звука и сети - её проверяют тесты.
///
/// Нажатие на очках приходит как кнопка плеера. Первое - начать запись, второе - отправить.
/// Пока ждём ответа Джарвис, нажатия не принимаются. Дребезг кнопки отсекается.
struct VoiceMachine {
    enum State: Equatable {
        case idle
        case recording(since: TimeInterval)
        case sending
    }

    enum Action: Equatable {
        case startRecording
        case stopAndSend
        case ignore
    }

    static let debounce: TimeInterval = 0.6   // как DEBOUNCE_MS в webapp/lib/headsetButton.ts
    static let maxRecording: TimeInterval = 60

    private(set) var state: State = .idle
    private var lastAccepted: TimeInterval?

    mutating func press(at now: TimeInterval) -> Action {
        if let last = lastAccepted, now - last < Self.debounce { return .ignore }
        switch state {
        case .idle:
            lastAccepted = now
            state = .recording(since: now)
            return .startRecording
        case .recording:
            lastAccepted = now
            state = .sending
            return .stopAndSend
        case .sending:
            return .ignore
        }
    }

    /// Запись дольше предела отправляется сама.
    mutating func tick(at now: TimeInterval) -> Action {
        if case let .recording(since) = state, now - since >= Self.maxRecording {
            state = .sending
            return .stopAndSend
        }
        return .ignore
    }

    /// Ответ пришёл (или не пришёл) - снова ждём нажатия.
    mutating func finished() { state = .idle }

    /// Запись не началась (нет микрофона) - назад в ожидание.
    mutating func failed() { state = .idle }

    var label: String {
        switch state {
        case .idle: return "idle"
        case .recording: return "rec"
        case .sending: return "wait"
        }
    }
}
