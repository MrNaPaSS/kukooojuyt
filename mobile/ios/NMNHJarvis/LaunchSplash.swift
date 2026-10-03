import SwiftUI

/// Заставка при запуске (владелец 03.10.2026: «как на ПК - молния, дух влетает в островок, и оттуда,
/// как будто из-за островка справа вверху, выглядывает и машет»).
///
/// Молнии бьют с краёв экрана в центр, во вспышке появляется дух Джарвис, взлетает и прячется
/// в Dynamic Island, потом выглядывает из-за его правого края, машет и прячется обратно. Островок
/// рисует сама система поверх приложения - то, что под ним, скрыто само.
/// Касание - пропустить. «Уменьшить движение» в настройках iPhone - без заставки.
struct LaunchSplash: View {
    @Binding var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var bolts = Bolt.make(count: 12)

    /// Время этапов, секунды от запуска.
    enum T {
        static let strike = 0.7, flash = 0.9, appear = 1.0, hold = 1.7, fly = 2.3
        static let peekIn = 2.5, wave = 2.8, peekOut = 3.5, end = 3.8
    }

    /// Островок iPhone 14 Pro и новее: центр по вертикали и половина ширины, в точках.
    static let islandY: CGFloat = 30
    static let islandHalf: CGFloat = 63

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                let size = geo.size
                ZStack {
                    Color.black.opacity(Self.backdrop(t))
                    Canvas { ctx, canvas in
                        draw(bolts: ctx, in: canvas, t: t)
                    }
                    spirit(t: t, in: size)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(start.distance(to: Date()) < T.fly)  // после полёта - страница уже живая
        .contentShape(Rectangle())
        .onTapGesture { shown = false }
        .task {
            if reduceMotion { shown = false; return }
            try? await Task.sleep(for: .seconds(T.end))
            shown = false
        }
    }

    /// Чёрный фон: держится до полёта, потом тает - под ним уже страница.
    static func backdrop(_ t: Double) -> Double {
        t < T.hold ? 1 : max(0, 1 - (t - T.hold) / (T.fly - T.hold + 0.1))
    }

    // MARK: молнии и вспышка

    private func draw(bolts ctx: GraphicsContext, in size: CGSize, t: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        if t < T.flash {
            let grow = Self.ease(t / T.strike)
            let fade = t < T.strike ? 1 : 1 - (t - T.strike) / (T.flash - T.strike)
            for bolt in bolts {
                let path = bolt.path(in: size, to: center, upTo: grow)
                ctx.stroke(path, with: .color(bolt.color.opacity(0.35 * fade)), lineWidth: 7)
                ctx.stroke(path, with: .color(.white.opacity(0.95 * fade)), lineWidth: 1.6)
            }
        }
        // Вспышка в центре, где сходятся молнии.
        let flash = t < T.strike ? 0 : t < T.flash ? (t - T.strike) / (T.flash - T.strike)
            : max(0, 1 - (t - T.flash) / 0.5)
        if flash > 0 {
            let r = 40 + 160 * flash
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [.white.opacity(0.9 * flash), SpiritView.color("jarvis").opacity(0.35 * flash), .clear]),
                center: center, startRadius: 0, endRadius: r))
        }
    }

    // MARK: дух

    @ViewBuilder private func spirit(t: Double, in size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let island = CGPoint(x: size.width / 2, y: Self.islandY)
        if t >= T.appear && t < T.fly {
            // Появился во вспышке, повисел, взлетел и уменьшился в островок.
            let pop = Self.back((t - T.appear) / 0.35)
            let fly = Self.easeIn((t - T.hold) / (T.fly - T.hold))
            let side = 92 * pop * (1 - fly) + 14 * fly
            SpiritView(id: "jarvis", busy: true, size: max(1, side), phase: t)
                .position(x: center.x, y: center.y + (island.y - center.y) * fly)
                .opacity(t > T.fly - 0.08 ? 0 : 1)
        } else if t >= T.peekIn && t < T.end {
            // Выглядывает из-за правого края островка, машет, прячется.
            let out = t < T.peekOut ? Self.ease((t - T.peekIn) / 0.3) : 1 - Self.easeIn((t - T.peekOut) / 0.3)
            let waving = t >= T.wave && t < T.peekOut
            let tilt = waving ? sin((t - T.wave) * 16) * 16 : 0
            HStack(alignment: .top, spacing: -3) {
                SpiritView(id: "jarvis", busy: true, size: 24, phase: t)
                    .rotationEffect(.degrees(tilt), anchor: .bottom)
                Hand(swing: waving ? sin((t - T.wave) * 16) : 0)
            }
            .position(x: island.x + Self.islandHalf - 14 + 30 * out, y: island.y + 4)
        }
    }

    // MARK: кривые

    static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
    static func ease(_ t: Double) -> Double { 1 - pow(1 - clamp(t), 3) }
    static func easeIn(_ t: Double) -> Double { pow(clamp(t), 3) }
    static func back(_ t: Double) -> Double {
        let c = 1.9, x = clamp(t) - 1
        return 1 + (c + 1) * x * x * x + c * x * x
    }
}

/// Ручка, которой дух машет: маленький кружок на качающейся «руке».
private struct Hand: View {
    let swing: Double
    var body: some View {
        Circle().fill(SpiritView.color("jarvis"))
            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.6))
            .frame(width: 7, height: 7)
            .offset(x: 2, y: 6)
            .rotationEffect(.degrees(-30 + swing * 35), anchor: .bottomLeading)
            .frame(width: 10, height: 14)
    }
}

/// Молния: ломаная от точки на краю экрана к центру. Изломы заданы при запуске и не дрожат.
struct Bolt {
    let edge: CGPoint    // доли ширины и высоты: где на краю начинается
    let jitter: [Double] // смещения изломов поперёк, -1...1
    let color: Color

    static let colors: [Color] = [Color(red: 0.49, green: 0.78, blue: 1), .white, SpiritView.color("jarvis"),
                                  Color(red: 0.99, green: 0.55, blue: 0), Color(red: 0.24, green: 0.62, blue: 1)]

    static func make(count: Int) -> [Bolt] {
        (0..<count).map { i in
            let along = (Double(i % 3) + 0.5) / 3 + Double.random(in: -0.1...0.1)
            let edge: CGPoint
            switch i % 4 {
            case 0: edge = CGPoint(x: along, y: 0)
            case 1: edge = CGPoint(x: 1, y: along)
            case 2: edge = CGPoint(x: along, y: 1)
            default: edge = CGPoint(x: 0, y: along)
            }
            return Bolt(edge: edge, jitter: (0..<9).map { _ in Double.random(in: -1...1) },
                        color: colors[i % colors.count])
        }
    }

    /// Путь до доли progress длины: молния «растёт» от края к центру.
    func path(in size: CGSize, to center: CGPoint, upTo progress: Double) -> Path {
        let from = CGPoint(x: edge.x * size.width, y: edge.y * size.height)
        let dx = center.x - from.x, dy = center.y - from.y
        let length = max(1, hypot(dx, dy))
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let steps = jitter.count + 1
        let shown = Int((Double(steps) * progress).rounded(.up))
        var p = Path()
        p.move(to: from)
        for k in 1...max(1, min(shown, steps)) {
            let f = Double(k) / Double(steps)
            let swing = k < steps ? jitter[k - 1] * length * 0.06 : 0
            p.addLine(to: CGPoint(x: from.x + dx * f + normal.x * swing, y: from.y + dy * f + normal.y * swing))
        }
        return p
    }
}
