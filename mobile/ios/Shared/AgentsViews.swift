import SwiftUI

/// Духи агентов рядком и строка духа (стиль B) - общие для островка, экрана блокировки и виджетов.
struct Spirits: View {
    let spirits: [IslandAttributes.Spirit]
    let size: CGFloat
    var body: some View {
        HStack(spacing: -size * 0.18) {
            ForEach(spirits) { SpiritView(id: $0.id, busy: $0.busy, size: size) }
        }
    }
}

/// Строка духа: дух, имя его цветом, чем занят (серым, если ждёт), прогресс плана.
struct SpiritRow: View {
    let spirit: IslandAttributes.Spirit
    var mode: IslandAttributes.Mode = .quiet
    var size: CGFloat = 22

    /// Джарвис не «работает»: она слушает, думает или говорит.
    private var doing: String {
        if spirit.id == "jarvis" {
            switch mode {
            case .recording: return "слушает"
            case .thinking: return "думает"
            case .speaking: return "говорит"
            default: break
            }
        }
        guard spirit.busy else { return "ждёт" }
        // Пустое «работает» заменено шагом или счётом плана (владелец 03.10.2026):
        // что дух занят, видно по нему самому, а вот чем - нет.
        let step = spirit.step.isEmpty ? (spirit.total > 0 ? "" : "без плана") : spirit.step
        if spirit.total > 0 {
            return step.isEmpty ? "план \(spirit.done)/\(spirit.total)" : "\(step) · \(spirit.done)/\(spirit.total)"
        }
        return step
    }

    var body: some View {
        HStack(spacing: 9) {
            FullColor {
                HStack(spacing: 9) {
                    SpiritView(id: spirit.id, busy: spirit.busy, size: size)
                    Text(spirit.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(SpiritView.color(spirit.id))
                }
            }
            Text(doing).font(.system(size: 14, weight: .medium))
                .foregroundStyle(spirit.busy || mode != .quiet ? DashTheme.ink2 : DashTheme.faint).lineLimit(1)
            Spacer(minLength: 4)
            // Лимит подписки тут же в строке (владелец 03.10.2026): он смотрит
            // на духов, чтобы понять, кто чем занят, - и сразу видит, у кого
            // сколько хода осталось.
            LimitChip(spirit: spirit, size: 11)
        }
    }
}

/// Все духи строками.
struct AgentsPage: View {
    let spirits: [IslandAttributes.Spirit]
    var mode: IslandAttributes.Mode = .quiet
    var size: CGFloat = 22
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(spirits) { SpiritRow(spirit: $0, mode: mode, size: size) }
        }
    }
}
