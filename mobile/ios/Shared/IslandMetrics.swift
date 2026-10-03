import SwiftUI

/// Островок развёрнутый и экран блокировки (просьба владельца 02.10.2026): метрики сервера,
/// сторожа и агентов - плотно, без прибыли, без обрезанных духов.
///   1) духи-кнопки агентов (нажал - голосовое ему);
///   2) сервер: CPU, память, диск, службы;
///   3) сторож: сделки на сопровождении, биржи (задержка, отказы), пауза процессов;
///      во время записи вместо него - полоски голоса, когда кто-то говорит - его фраза.
struct IslandMetrics: View {
    let state: IslandAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Пока кто-то работает, всё место отдано его плану (владелец
            // 03.10.2026): духи-кнопки и метрики сервера ничего не говорят о
            // ходе работы, а список шагов со временем - говорит. В покое они
            // возвращаются: тогда это главное, что есть на экране.
            // Решение владельца важнее всего, кроме идущей записи (владелец 03.10.2026: «на
            // экране блокировки либо вопросы выбора, либо подтвердить выкладку, а то всегда
            // текущее действие агентов, если ничего - обычные метрики»).
            if let d = state.decision, state.mode != .recording {
                DecisionCard(decision: d)
            } else if state.mode == .working, let busy = worker {
                WorkCard(spirit: busy)
            } else if state.mode == .speaking {
                // Заговорил - островок раскрывается на пару секунд: слева он, справа его задача
                // и ход (владелец 03.10.2026), потом iOS сворачивает в обычный дух с волной.
                SpeakerCard(state: state)
            } else {
                AgentPills(state: state)
                if let d = state.dash {
                    LimitsRow(spirits: state.spirits)
                    ServerRow(srv: d.srv)
                    third(d)
                } else {
                    LimitsRow(spirits: state.spirits)
                    Caption(text: "Жду сводку с сервера…")
                }
            }
        }
    }

    /// Кто работает: сначала агент с планом, Джарвис - последней.
    private var worker: IslandAttributes.Spirit? {
        let busy = state.spirits.filter(\.busy)
        return busy.first { $0.total > 0 && $0.id != "jarvis" } ?? busy.first { $0.id != "jarvis" } ?? busy.first
    }

    @ViewBuilder private func third(_ d: Dash) -> some View {
        switch state.mode {
        case .recording:
            HStack(spacing: 8) {
                SpiritView(id: state.recFor, busy: true, size: 16)
                LevelBars(levels: state.levels, tint: SpiritView.color(state.recFor), count: 22, height: 20)
                Spacer(minLength: 0)
                if let since = state.recSince {
                    Text(timerInterval: since...since.addingTimeInterval(3600), countsDown: false)
                        .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(DashTheme.down)
                        .frame(maxWidth: 44, alignment: .trailing)
                }
            }
        case .speaking, .thinking:
            HStack(spacing: 7) {
                SpiritView(id: state.mode == .thinking ? state.recFor : state.speaker, busy: true, size: 16)
                Text(state.line)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(DashTheme.ink2).lineLimit(1)
            }
        default:
            if !state.done.isEmpty {
                HStack(spacing: 6) {  // итог отправки голосового - 3 секунды
                    Image(systemName: state.doneOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(state.doneOK ? DashTheme.money : DashTheme.down)
                    Text(state.done).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(state.doneOK ? DashTheme.money : DashTheme.down).lineLimit(1)
                }
            } else {
                WatchRow(watch: d.watch, alerts: d.alerts)
            }
        }
    }
}

/// Работающий агент (владелец 03.10.2026): дух, имя, сколько работает, «2/5» и его список дел.
struct WorkCard: View {
    let spirit: IslandAttributes.Spirit

    /// Сколько строк плана показываем: шесть не влезали, последняя обрезалась
    /// (владелец 03.10.2026, снимок островка).
    static let maxLines = 4

    var body: some View {
        let tint = SpiritView.color(spirit.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SpiritView(id: spirit.id, busy: true, size: 24)
                Text(spirit.name).font(.system(size: 15, weight: .bold)).foregroundStyle(tint)
                    .lineLimit(1).fixedSize()
                if let since = spirit.since {
                    Text(timerInterval: since...since.addingTimeInterval(36_000), countsDown: false)
                        .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(DashTheme.label)
                        .frame(maxWidth: 50, alignment: .leading)
                }
                Spacer(minLength: 0)
                // Целиком, без обрезки (владелец 03.10.2026: «не видно полностью лимиты»).
                LimitChip(spirit: spirit, size: 11, compact: true).fixedSize()
                if spirit.total > 0 {
                    Text("\(spirit.done)/\(spirit.total)").font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit().foregroundStyle(tint)
                }
            }
            if let todo = spirit.todo, !todo.isEmpty {
                // Весь список, а не один шаг (владелец 03.10.2026): островок
                // должен отвечать на вопрос «где работа идёт и где встала», а
                // слово «работает» на него не отвечает никак.
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(todo.prefix(WorkCard.maxLines).enumerated()), id: \.offset) { _, item in
                        TodoLine(item: item, tint: tint)
                    }
                }
            } else if !spirit.step.isEmpty {
                Text(spirit.step)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(DashTheme.ink2).lineLimit(2)
            } else {
                // Плана нет вовсе - так и говорим. «Работает» и так видно по
                // духу, таймеру и самой карточке: лишнее слово места не стоит.
                Text("план не заявлен")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(DashTheme.faint).lineLimit(1)
            }
        }
    }
}

/// Что ждёт решения: кто спрашивает, вопрос и кнопки вариантов. Кнопка - DecideIntent: ответ
/// уходит на сервер из островка и с замка, не открывая приложение. Сложный вопрос - «Открыть».
struct DecisionCard: View {
    let decision: IslandAttributes.Decision

    static func icon(_ d: IslandAttributes.Decision) -> String {
        switch (d.kind, d.stage) {
        case ("progress", "done"): return "checkmark.circle.fill"
        case ("progress", "fail"): return "xmark.circle.fill"
        case ("progress", _): return "arrow.triangle.2.circlepath"
        case ("deploy", _): return "arrow.up.circle.fill"
        default: return "questionmark.circle.fill"
        }
    }

    var body: some View {
        let tint = SpiritView.color(decision.agent)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                SpiritView(id: decision.agent, busy: true, size: 20)
                Text(decision.title).font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: DecisionCard.icon(decision))
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(tint)
            }
            if !decision.text.isEmpty {
                Text(decision.text).font(.system(size: 13, weight: .medium)).foregroundStyle(DashTheme.ink)
                    .lineLimit(2)
            }
            if decision.kind == "progress" {
                // После «Выложить» кнопок нет - ход выкладки (владелец 03.10.2026).
                DeploySteps(decision: decision)
            } else if decision.simple {
                HStack(spacing: 6) {
                    ForEach(Array(decision.options.enumerated()), id: \.offset) { index, label in
                        Button(intent: DecideIntent(kind: decision.kind, id: decision.id, pick: index)) {
                            Text(label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .foregroundStyle(index == 0 ? Color.black : DashTheme.ink)
                                .padding(.vertical, 7).frame(maxWidth: .infinity)
                                .background(Capsule().fill(index == 0 ? tint : Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Link(destination: URL(string: "jarvis://plan?agent=\(decision.agent)") ?? URL(fileURLWithPath: "/")) {
                    Text("Открыть и ответить").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.black)
                        .padding(.vertical, 7).frame(maxWidth: .infinity).background(Capsule().fill(tint))
                }
            }
        }
    }
}

/// Ход выкладки точками: готовые зелёные, текущий - цвет агента, упавший - красный.
struct DeploySteps: View {
    let decision: IslandAttributes.Decision

    var body: some View {
        let current = decision.stepIndex
        let done = decision.stage == "done"
        let failed = decision.stage == "fail"
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(IslandAttributes.Decision.steps.enumerated()), id: \.offset) { index, step in
                let passed = done || index < current
                let now = !done && index == current
                VStack(spacing: 3) {
                    ZStack {
                        Circle().fill(failed && now ? DashTheme.down : passed ? DashTheme.money
                                      : now ? SpiritView.color(decision.agent) : Color.white.opacity(0.15))
                            .frame(width: 14, height: 14)
                        if passed || (failed && now) {
                            Image(systemName: failed && now ? "xmark" : "checkmark")
                                .font(.system(size: 7, weight: .black)).foregroundStyle(Color.black)
                        }
                    }
                    Text(step.label).font(.system(size: 10, weight: now ? .bold : .medium))
                        .foregroundStyle(now ? DashTheme.ink : DashTheme.label).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Лимит подписки: «5ч 90% · нед 55%» (владелец 03.10.2026 - нужны оба окна).
///
/// Показываются оба намеренно: пятичасовое упирается и отпускает через час,
/// недельное - до понедельника, и это разные решения. Цвет - по худшему из
/// двух: встанет работа одинаково, в какое бы он ни упёрся.
struct LimitChip: View {
    let spirit: IslandAttributes.Spirit
    var size: CGFloat = 12
    var compact = false  // «5ч 39% · н 57%» - для тесной строки островка

    /// Выше этого процента лимит становится поводом поторопиться.
    static let hot = 80

    var body: some View {
        if let worst = [spirit.lim5, spirit.lim7].compactMap({ $0 }).max() {
            let tint = worst >= LimitChip.hot ? DashTheme.down : DashTheme.label
            Text(LimitChip.text(five: spirit.lim5, week: spirit.lim7, compact: compact))
                .font(.system(size: size, weight: .semibold)).monospacedDigit()
                .foregroundStyle(tint)
                .padding(.horizontal, compact ? 4 : 6).padding(.vertical, 2)
                .background(Capsule().fill(tint.opacity(0.14)))
        }
    }

    /// «5ч 90% · нед 55%»; нет одного из окон - показываем то, что есть.
    static func text(five: Int?, week: Int?, compact: Bool = false) -> String {
        [five.map { "5ч \($0)%" }, week.map { compact ? "н \($0)%" : "нед \($0)%" }].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Лимиты обоих агентов, когда никто не работает (владелец 03.10.2026: «хочу
/// видеть лимиты агентов 5ч и нед в телефоне»).
///
/// В покое островок показывает сервер и сторожа, а это - третье, на что он
/// смотрит: сколько у агентов осталось хода. Джарвис здесь нет: она не на
/// подписке Claude, и лимита у неё не бывает.
struct LimitsRow: View {
    let spirits: [IslandAttributes.Spirit]

    var body: some View {
        let withLimits = spirits.filter { $0.lim5 != nil || $0.lim7 != nil }
        if !withLimits.isEmpty {
            HStack(spacing: 10) {
                ForEach(withLimits) { spirit in
                    HStack(spacing: 5) {
                        SpiritView(id: spirit.id, busy: spirit.busy, size: 14)
                        Text(LimitChip.text(five: spirit.lim5, week: spirit.lim7))
                            .font(.system(size: 12, weight: .medium)).monospacedDigit()
                            .foregroundStyle(
                                max(spirit.lim5 ?? 0, spirit.lim7 ?? 0) >= LimitChip.hot
                                    ? DashTheme.down : DashTheme.ink2
                            )
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Строка плана: готово - галочка и зачёркнуто, в работе - кружок цвета агента, впереди - пустой.
/// Справа время: у готового - сколько занял, у текущего - живой счётчик (владелец 03.10.2026).
struct TodoLine: View {
    let item: IslandAttributes.Todo
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: item.s == 2 ? "checkmark.circle.fill" : item.s == 1 ? "circle.circle.fill" : "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(item.s == 2 ? DashTheme.money : item.s == 1 ? tint : DashTheme.faint)
            Text(item.t).font(.system(size: 13, weight: item.s == 1 ? .semibold : .regular))
                .foregroundStyle(item.s == 2 ? DashTheme.faint : item.s == 1 ? DashTheme.ink : DashTheme.ink2)
                .strikethrough(item.s == 2, color: DashTheme.faint)
                .lineLimit(1)
            Spacer(minLength: 4)
            time
        }
    }

    /// Время шага. У текущего - таймер системы: он тикает сам, без обновлений
    /// с сервера, а их у Live Activity считанное число в час.
    @ViewBuilder private var time: some View {
        if item.s == 1, let began = item.b {
            Text(timerInterval: began...began.addingTimeInterval(36_000), countsDown: false)
                .font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(tint)
                .frame(maxWidth: 52, alignment: .trailing)
        } else if item.s == 2, let spent = item.d {
            Text(TodoLine.spent(spent))
                .font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(DashTheme.faint)
        }
    }

    /// Сколько занял готовый шаг: секунды до минуты, дальше минуты и часы.
    /// Коротко намеренно - это подпись у края строки, а не отчёт.
    static func spent(_ seconds: Int) -> String {
        if seconds < 60 { return "\(max(1, seconds)) с" }
        if seconds < 3600 { return "\(seconds / 60) мин" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return minutes > 0 ? "\(hours) ч \(minutes) м" : "\(hours) ч"
    }
}

/// Говорящий крупно: дух, имя, фраза в две строки.
struct SpeakerCard: View {
    let state: IslandAttributes.ContentState

    private var spirit: IslandAttributes.Spirit? { state.spirits.first { $0.id == state.speaker } }

    var body: some View {
        let tint = SpiritView.color(state.speaker)
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                // Слева - кто говорит.
                SpiritView(id: state.speaker, busy: true, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(GlassesAgents.name(state.speaker)).font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tint).lineLimit(1)
                    Image(systemName: "waveform").font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
                .fixedSize()
                Spacer(minLength: 8)
                // Справа - его задача и ход выполнения.
                task(tint)
            }
            Text(state.line).font(.system(size: 13, weight: .medium)).foregroundStyle(DashTheme.ink2).lineLimit(1)
        }
    }

    @ViewBuilder private func task(_ tint: Color) -> some View {
        if let s = spirit, s.total > 0 {
            VStack(alignment: .trailing, spacing: 4) {
                Text(s.step.isEmpty ? "план выполнен" : s.step)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(DashTheme.ink)
                    .lineLimit(2).multilineTextAlignment(.trailing)
                HStack(spacing: 6) {
                    Bar(progress: Double(s.done) / Double(max(1, s.total)), tint: tint).frame(width: 70)
                    Text("\(s.done)/\(s.total)").font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit().foregroundStyle(tint)
                }
            }
        } else if let s = spirit, s.busy, !s.step.isEmpty {
            Text(s.step).font(.system(size: 13, weight: .semibold)).foregroundStyle(DashTheme.ink)
                .lineLimit(2).multilineTextAlignment(.trailing)
        } else {
            Text("без задачи").font(.system(size: 12, weight: .medium)).foregroundStyle(DashTheme.faint)
        }
    }
}

/// Три духа-кнопки в одну строку, без переносов: дух, имя, точка «работает».
struct AgentPills: View {
    let state: IslandAttributes.ContentState
    var body: some View {
        HStack(spacing: 6) {
            ForEach(GlassesAgents.all, id: \.self) { id in
                let live = state.mode == .recording && state.recFor == id
                let busy = state.spirits.first { $0.id == id }?.busy ?? false
                // Только дух и цветное имя, без цветных капсул (владелец 03.10.2026); запись - красная точка.
                Button(intent: TalkIntent(agent: id)) {
                    HStack(spacing: 5) {
                        SpiritView(id: id, busy: busy || live, size: 17)
                        if live { Circle().fill(DashTheme.down).frame(width: 6, height: 6) }
                        Text(live ? "Отправить" : GlassesAgents.name(id))
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(SpiritView.color(id))
                        if busy && !live {
                            Circle().fill(DashTheme.money).frame(width: 5, height: 5)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Сервер одной строкой: CPU, память, диск, службы.
struct ServerRow: View {
    let srv: Dash.Srv
    var body: some View {
        HStack(spacing: 6) {
            Stat(label: "CPU", value: "\(srv.cpu)%", tint: load(srv.cpu))
            Stat(label: "Память", value: "\(srv.ram)%", tint: load(srv.ram))
            Stat(label: "Диск", value: "\(srv.disk)%", tint: load(srv.disk))
            Stat(label: "Службы", value: srv.down.isEmpty ? "все ✓" : "стоит \(srv.down.count)",
                 tint: srv.down.isEmpty ? DashTheme.money : DashTheme.down)
        }
    }

    private func load(_ p: Int) -> Color { p >= 90 ? DashTheme.down : p >= 70 ? DashTheme.warn : DashTheme.server }
}

/// Маленькая плитка: подпись и значение в одну высоту.
struct Stat: View {
    let label: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(DashTheme.label).lineLimit(1)
            Text(value).font(.system(size: 14, weight: .bold)).foregroundStyle(DashTheme.ink).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

/// Сторож одной строкой: сделки, биржи, пауза процессов; тревога - красным вместо неё.
struct WatchRow: View {
    let watch: Dash.Watch
    let alerts: [String]
    var body: some View {
        if let alert = alerts.first {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(DashTheme.down)
                Text(alerts.count > 1 ? "\(alert) · ещё \(alerts.count - 1)" : alert)
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DashTheme.down).lineLimit(1)
            }
        } else {
            HStack(spacing: 8) {
                Label("\(watch.open)", systemImage: "eye.fill").foregroundStyle(DashTheme.trades)
                ForEach(Array(watch.ex.prefix(2).enumerated()), id: \.offset) { _, e in
                    HStack(spacing: 3) {
                        Circle().fill(e.err >= 5 || e.worst >= 1500 || e.drops > 2 ? DashTheme.down : DashTheme.money)
                            .frame(width: 6, height: 6)
                        Text(e.calls > 0 ? "\(e.n.uppercased()) \(e.ms)мс" : "\(e.n.uppercased()) \(e.streams) пот.")
                    }
                    .foregroundStyle(DashTheme.ink2)
                }
                Spacer(minLength: 0)
                Text("пауза \(watch.lag)мс").foregroundStyle(watch.lag >= 1000 ? DashTheme.warn : DashTheme.label)
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
        }
    }
}
