import SwiftUI

/// План агента по касанию островка (владелец 03.10.2026): агент работает, в островке «1/3» -
/// нажал, и открывается его список дел: прогресс кольцом, текущий шаг пульсирует, готовые
/// зачёркнуты. Стекло - как в новой iOS; переключатель сверху - духи и цветные имена, без плашек.
struct PlanSheet: View {
    @ObservedObject var board: AgentBoard
    @State var agent: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switcher
                header
                steps
            }
            .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 30)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: board.plans[agent])
            .animation(.easeInOut(duration: 0.25), value: agent)
        }
        .scrollIndicators(.hidden)
        .environment(\.colorScheme, .dark)
        .task(id: agent) {
            while !Task.isCancelled {  // пока открыт - свежие шаги каждые 3 с
                await GlassesVoice.shared.refreshBoard()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private var plan: AgentPlan? { board.plans[agent].flatMap { $0.steps.isEmpty ? nil : $0 } }
    private var work: AgentWork? { board.work[agent] }
    private var tint: Color { SpiritView.color(agent) }

    /// Три духа с цветными именами; выбранный - ярче и с точкой «работает».
    private var switcher: some View {
        HStack(spacing: 8) {
            ForEach(GlassesAgents.all, id: \.self) { id in
                let on = id == agent
                Button { agent = id } label: {
                    VStack(spacing: 5) {
                        SpiritView(id: id, busy: board.work[id]?.busy ?? false, size: on ? 30 : 24)
                        HStack(spacing: 4) {
                            Text(GlassesAgents.name(id)).font(.system(size: 13, weight: on ? .bold : .semibold))
                                .foregroundStyle(SpiritView.color(id))
                            if board.work[id]?.busy == true {
                                Circle().fill(DashTheme.money).frame(width: 5, height: 5)
                            }
                        }
                    }
                    .opacity(on ? 1 : 0.5)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plan-\(id)")
            }
        }
        .frame(height: 62)
    }

    private var header: some View {
        HStack(spacing: 14) {
            TimelineView(.animation(minimumInterval: 1 / 30)) { time in
                SpiritView(id: agent, busy: work?.busy ?? false, size: 52,
                           phase: (work?.busy ?? false) ? time.date.timeIntervalSinceReferenceDate : 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(GlassesAgents.name(agent)).font(.system(size: 22, weight: .bold)).foregroundStyle(tint)
                status
                if let plan, !plan.name.isEmpty {
                    Text(plan.name).font(.system(size: 13, weight: .medium)).foregroundStyle(DashTheme.ink2).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if let plan { Ring(done: plan.done, total: plan.steps.count, tint: tint) }
        }
        .padding(16)
        .glassCard(radius: 26)
    }

    @ViewBuilder private var status: some View {
        if let since = work?.since, work?.busy == true {
            HStack(spacing: 5) {
                Circle().fill(DashTheme.money).frame(width: 6, height: 6)
                Text("работает ")
                    + Text(timerInterval: since...since.addingTimeInterval(36_000), countsDown: false)
            }
            .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(DashTheme.label)
        } else {
            Text(plan == nil ? "ждёт" : "план на паузе").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DashTheme.faint)
        }
    }

    @ViewBuilder private var steps: some View {
        if let plan {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(plan.steps) { step in
                    StepRow(step: step, tint: tint, current: step.id == plan.current?.id)
                    if step.id != plan.steps.last?.id {
                        Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 40)
                    }
                }
            }
            .padding(.vertical, 6)
            .glassCard(radius: 22)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "checklist").font(.system(size: 26, weight: .semibold)).foregroundStyle(tint)
                Text("Плана сейчас нет").font(.system(size: 15, weight: .semibold)).foregroundStyle(DashTheme.ink)
                Text("Когда \(GlassesAgents.name(agent)) возьмёт задачу, шаги появятся здесь")
                    .font(.system(size: 13)).foregroundStyle(DashTheme.label).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(24)
            .glassCard(radius: 22)
        }
    }
}

/// Шаг плана: готово - галочка и зачёркнуто, в работе - пульсирующий кружок цвета агента.
private struct StepRow: View {
    let step: AgentPlan.Step
    let tint: Color
    let current: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon.frame(width: 22, height: 20)
            Text(step.t)
                .font(.system(size: 15, weight: current ? .semibold : .regular))
                .foregroundStyle(step.s == 2 ? DashTheme.faint : current ? DashTheme.ink : DashTheme.ink2)
                .strikethrough(step.s == 2, color: DashTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(current ? tint.opacity(0.10) : Color.clear)
    }

    @ViewBuilder private var icon: some View {
        if step.s == 2 {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 17)).foregroundStyle(DashTheme.money)
        } else if current {
            Image(systemName: "circle.circle.fill").font(.system(size: 17)).foregroundStyle(tint)
                .symbolEffect(.pulse, options: .repeating)
        } else {
            Image(systemName: "circle").font(.system(size: 17)).foregroundStyle(DashTheme.faint)
        }
    }
}

/// Кольцо прогресса с «1/3» внутри.
private struct Ring: View {
    let done: Int
    let total: Int
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 6)
            Circle().trim(from: 0, to: total > 0 ? CGFloat(done) / CGFloat(total) : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(done)/\(total)").font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(DashTheme.ink)
                .contentTransition(.numericText())
        }
        .frame(width: 62, height: 62)
    }
}

extension View {
    /// Карточка «стекло»: на iOS 26+ настоящее Liquid Glass, раньше - тонкий материал.
    @ViewBuilder func glassCard(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.clipShape(shape).glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        #endif
    }

    /// Экран плана поверх окна приложения: открывается ссылкой jarvis://plan из островка.
    func planSheet(board: AgentBoard = .shared) -> some View {
        modifier(PlanSheetHost(board: board))
    }
}

private struct PlanSheetHost: ViewModifier {
    @ObservedObject var board: AgentBoard

    func body(content: Content) -> some View {
        content
            .onOpenURL { board.open($0) }
            .sheet(isPresented: Binding(get: { board.focus != nil }, set: { if !$0 { board.focus = nil } })) {
                PlanSheet(board: board, agent: board.focus ?? "server")
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .sheetGlass()
            }
    }
}

private extension View {
    /// На iOS 26+ лист и так стеклянный - фон не трогаем; раньше - тонкий материал.
    @ViewBuilder func sheetGlass() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self
        } else {
            self.presentationBackground(.ultraThinMaterial).presentationCornerRadius(30)
        }
        #else
        self.presentationBackground(.ultraThinMaterial).presentationCornerRadius(30)
        #endif
    }
}
