import AppIntents
import SwiftUI

/// Полоски громкости голоса (стиль B): высота - громкость, цвет - агент, кому идёт запись.
struct LevelBars: View {
    let levels: [Double]
    let tint: Color
    var count = 12
    var height: CGFloat = 26
    var body: some View {
        // Волна занимает всю отведённую ширину и в тишине (владелец 03.10.2026:
        // «линия смещена в сторону»): пустые места - ровная линия слева, а не
        // пустота, из-за которой волна жалась к краю.
        let shown = Array((Array(repeating: 0.0, count: max(0, count - levels.count)) + levels).suffix(count))
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, level in
                Capsule().fill(tint)
                    .frame(width: 4, height: max(3, height * CGFloat(level)))
                    .opacity(0.3 + 0.7 * level)
                    // Короткое сглаживание между замерами: шаг 1/16 секунды,
                    // и без него соседние кадры видны как мелкая дрожь.
                    .animation(.linear(duration: 0.06), value: level)
            }
        }
        .frame(height: height)
    }
}

/// Духи-кнопки в развёрнутом островке: нажал - запись этому агенту, нажал ещё раз - отправлено.
struct TalkButtons: View {
    let state: IslandAttributes.ContentState
    var body: some View {
        if #available(iOS 18.0, *) {
            HStack(spacing: 10) {
                ForEach(GlassesAgents.all, id: \.self) { id in
                    let live = state.mode == .recording && state.recFor == id
                    Button(intent: TalkIntent(agent: id)) {
                        HStack(spacing: 6) {
                            SpiritView(id: id, busy: live, size: 20)
                            if live { Circle().fill(DashTheme.down).frame(width: 6, height: 6) }
                            Text(live ? "Отправить" : GlassesAgents.name(id))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SpiritView.color(id))
                        }
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Карточка записи: дух адресата, кому, таймер, полоски голоса.
struct RecordingCard: View {
    let state: IslandAttributes.ContentState
    var body: some View {
        let tint = SpiritView.color(state.recFor)
        HStack(spacing: 14) {
            SpiritView(id: state.recFor, busy: true, size: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text("Голосовое: \(GlassesAgents.name(state.recFor))").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DashTheme.ink)
                    if let since = state.recSince {
                        Text(timerInterval: since...since.addingTimeInterval(3600), countsDown: false)
                            .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(DashTheme.down)
                    }
                }
                LevelBars(levels: state.levels, tint: tint)
                Caption(text: "Нажми духа ещё раз - отправлю")
            }
            Spacer(minLength: 0)
        }
    }
}

/// Кому идёт запись - для виджета «Говорить» (пишет приложение, читает виджет).
struct TalkState: Codable {
    static let kind = "nmnh.talk"
    var recFor: String
    var since: Date?
}

enum GlassesAgents {
    static let all = ["jarvis", "server", "pc"]
    static func name(_ id: String) -> String {
        switch id {
        case "jarvis": return "Джарвис"
        case "server": return "Server PC"
        default: return "Local PC"
        }
    }
}
