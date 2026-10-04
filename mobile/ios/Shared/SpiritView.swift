import SwiftUI

/// Дух агента: светящийся призрачок с волнистым краем. Свой рисунок, не персонаж Coucou
/// (его Mochi под отдельной лицензией - LICENSE-ASSETS.md в их репозитории).
struct SpiritView: View {
    let id: String
    var busy = false
    var size: CGFloat = 22
    var phase: Double = 0  // в приложении - время для покачивания; в островке 0

    static func color(_ id: String) -> Color {
        switch id {
        case "jarvis": return Color(red: 0.93, green: 0.30, blue: 0.85)  // фуксия
        case "server": return Color(red: 1.00, green: 0.55, blue: 0.15)  // оранжевый
        case "pc": return Color(red: 0.30, green: 0.72, blue: 1.00)      // голубой
        default:
            return GlassesAgents.extra.first { $0.id == id }.flatMap { hex($0.hex) }
                ?? Color(red: 0.56, green: 0.58, blue: 0.61)
        }
    }

    /// «#3ddc97» -> цвет; не цвет - nil.
    static func hex(_ text: String) -> Color? {
        let clean = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard clean.count == 6, let v = UInt32(clean, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
                     blue: Double(v & 0xff) / 255)
    }

    var body: some View {
        let tint = Self.color(id)
        ZStack {
            GhostShape(wave: phase)
                .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .overlay(GhostShape(wave: phase).stroke(Color.white.opacity(0.35), lineWidth: max(0.5, size / 30)))
                .shadow(color: tint.opacity(busy ? 0.9 : 0.35), radius: busy ? size / 3 : size / 8)
            HStack(spacing: size * 0.18) {
                Eye(size: size)
                Eye(size: size)
            }
            .offset(y: -size * 0.08)
            if busy {  // румянец за работой
                HStack(spacing: size * 0.42) {
                    Circle().fill(Color.white.opacity(0.35)).frame(width: size * 0.14)
                    Circle().fill(Color.white.opacity(0.35)).frame(width: size * 0.14)
                }
                .offset(y: size * 0.1)
            }
        }
        .frame(width: size, height: size * 1.1)
        .offset(y: sin(phase * 2) * size * 0.05)
    }
}

private struct Eye: View {
    let size: CGFloat
    var body: some View {
        Capsule().fill(Color(white: 0.08)).frame(width: size * 0.12, height: size * 0.17)
    }
}

/// Купол сверху, волны снизу.
struct GhostShape: Shape {
    var wave: Double = 0

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let r = w / 2
        p.move(to: CGPoint(x: 0, y: r))
        p.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: w, y: h * 0.86))
        let waves = 3
        let step = w / CGFloat(waves)
        for i in 0..<waves {
            let x0 = w - CGFloat(i) * step
            let lift = CGFloat(sin(wave * 3 + Double(i))) * h * 0.03
            p.addQuadCurve(to: CGPoint(x: x0 - step, y: h * 0.86),
                           control: CGPoint(x: x0 - step / 2, y: h * (i % 2 == 0 ? 1.0 : 0.74) + lift))
        }
        p.closeSubpath()
        return p
    }
}
