import SwiftUI

// Окно одного агента (AgentAttributes) - вид. Общий файл: его рисует Live Activity в расширении
// (JarvisIsland/AgentWindow.swift) и галерея замка в приложении (DemoView, снимки для владельца).

/// «2/5» цветом агента; закончил - галочка.
struct AgentProgressText: View {
    let state: AgentAttributes.ContentState
    var body: some View {
        let spirit = state.spirit
        if state.finished {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(DashTheme.money)
        } else {
            Text("\(spirit.done)/\(spirit.total)").monospacedDigit().foregroundStyle(SpiritView.color(spirit.id))
        }
    }
}

/// Карточка агента: дух и имя, «N/M» с полоской и туду списком (до четырёх строк вокруг текущего шага).
/// Плана нет - текущий шаг с живым таймером.
struct AgentWindowCard: View {
    let state: AgentAttributes.ContentState
    var stale = false
    var island = false  // в островке без лимитов: там тесно

    var body: some View {
        let spirit = state.spirit
        let _ = GlassesAgents.remember(spirit)
        let tint = SpiritView.color(spirit.id)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                SpiritView(id: spirit.id, busy: !state.finished, size: 24)
                Text(spirit.name).font(.system(size: 15, weight: .bold)).foregroundStyle(tint)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if !island { LimitChip(spirit: spirit, size: 11, compact: true).fixedSize() }
                AgentProgressText(state: state).font(.system(size: 15, weight: .bold, design: .rounded))
            }
            Bar(progress: Double(spirit.done) / Double(max(1, spirit.total)), tint: state.finished ? DashTheme.money : tint)
            if state.finished {
                Text("План выполнен").font(.system(size: 13, weight: .semibold)).foregroundStyle(DashTheme.money)
            } else if let todo = spirit.todo, !todo.isEmpty {
                // Туду списком, как раньше в общей карточке (владелец 05.10.2026: «как и ранее с тодо, а не только
                // с текущим шагом»): сделанное, текущий с таймером и следующие.
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(todo.prefix(island ? 2 : WorkCard.maxLines).enumerated()), id: \.offset) { _, item in
                        TodoLine(item: item, tint: tint)
                    }
                }
            } else {
                current(spirit, tint: tint)
                upcoming(spirit)
            }
        }
        .opacity(stale && !state.finished ? 0.6 : 1)  // опрос встал - окно бледнеет, а не делает вид живого
    }

    @ViewBuilder private func current(_ spirit: IslandAttributes.Spirit, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "circle.circle.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            Text(spirit.step.isEmpty ? "шаг не назван" : spirit.step)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(DashTheme.ink).lineLimit(2)
            Spacer(minLength: 4)
            // Таймер системы: тикает сам, без обновлений с сервера.
            if let began = spirit.stepStarted ?? spirit.since {
                Text(timerInterval: began...began.addingTimeInterval(36_000), countsDown: false)
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }

    /// Дальше - свёрнуто: «Дальше: тесты · выкладка · ещё 2».
    @ViewBuilder private func upcoming(_ spirit: IslandAttributes.Spirit) -> some View {
        if let line = AgentActivityPlan.upcomingLine(spirit, names: island ? 1 : 2) {
            Text(line).font(.system(size: 12, weight: .medium)).foregroundStyle(DashTheme.label).lineLimit(1)
        }
    }
}
