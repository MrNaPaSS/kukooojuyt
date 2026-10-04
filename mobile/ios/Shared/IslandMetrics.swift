import SwiftUI

/// Островок развёрнутый и экран блокировки (просьба владельца 02.10.2026): метрики сервера,
/// сторожа и агентов - плотно, без прибыли, без обрезанных духов.
///   1) духи-кнопки агентов (нажал - голосовое ему);
///   2) сервер: CPU, память, диск, службы;
///   3) сторож: сделки на сопровождении, биржи (задержка, отказы), пауза процессов;
///      во время записи вместо него - полоски голоса, когда кто-то говорит - его фраза.
struct IslandMetrics: View {
    let state: IslandAttributes.ContentState
    var stale = false  // Live Activity устарела (staleDate прошёл) - итог выкладки больше не показываем

    var body: some View {
        let _ = GlassesAgents.learn(state.spirits)  // расширение узнаёт добавленных агентов из состояния
        VStack(alignment: .leading, spacing: 8) {
            // Пока кто-то работает, всё место отдано его плану (владелец
            // 03.10.2026): духи-кнопки и метрики сервера ничего не говорят о
            // ходе работы, а список шагов со временем - говорит. В покое они
            // возвращаются: тогда это главное, что есть на экране.
            // Решение владельца важнее всего, кроме идущей записи (владелец 03.10.2026: «на
            // экране блокировки либо вопросы выбора, либо подтвердить выкладку, а то всегда
            // текущее действие агентов, если ничего - обычные метрики»).
            if let d = state.decision, state.mode != .recording, !(stale && d.kind == "progress") {
                DecisionCard(decision: d)
            } else if state.mode == .working, let busy = worker {
                // Только тот, кто работает без плана: у кого план - своё окно ниже (AgentWindow),
                // а общая карточка остаётся с духами, лимитами, серверами и сторожем (04.10.2026).
                WorkCard(spirit: busy)
            } else if state.mode == .speaking {
                // Заговорил - островок раскрывается на пару секунд: слева он, справа его задача
                // и ход (владелец 03.10.2026), потом iOS сворачивает в обычный дух с волной.
                SpeakerCard(state: state)
            } else {
                AgentPills(state: state)
                if let d = state.dash {
                    LimitsRow(spirits: state.spirits)
                    if d.hosts.isEmpty {
                        ServerRow(srv: d.srv)  // сервер старее приложения - одна строка, как раньше
                    } else {
                        HostRows(hosts: d.hosts, srv: d.srv)
                    }
                    third(d)
                } else {
                    LimitsRow(spirits: state.spirits)
                    Caption(text: "Жду сводку с сервера…")
                }
            }
        }
    }

    /// Кто работает без своего окна (без плана): сначала агенты, Джарвис - последней.
    private var worker: IslandAttributes.Spirit? {
        freshest(state.spirits.filter { $0.busy && !$0.wantsWindow })  // у кого окно на замке - в своём окне
