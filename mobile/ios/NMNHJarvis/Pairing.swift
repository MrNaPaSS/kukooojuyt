import SwiftUI

/// Подключение телефона по QR с ПК (владелец 03.10.2026, ТЗ nmnh-agent-setup-tz.md этап 5).
///
/// На ПК: трей NMNH Agent -> «Подключение…» -> «Телефон» - QR. Камера iPhone открывает ссылку
/// jarvis://pair?code=...&api=https://..., приложение меняет одноразовый код (5 минут) на вход
/// админа (POST /api/pair/claim) и кладёт его странице - вход без пароля. Без кода - окно с
/// инструкцией, один раз при первом запуске и по ссылке jarvis://pair без кода.
@MainActor
final class Pairing: ObservableObject {
    static let shared = Pairing()

    enum Phase: Equatable {
        case guide                // как подключиться
        case connecting
        case done
        case failed(String)
    }

    @Published var phase: Phase?
    /// Страница получает вход: (access, refresh) - в localStorage админки и перезагрузка.
    var deliver: ((String, String) -> Void)?

    static let guideSeenKey = "pairGuideSeen"

    /// Первый запуск без входа - показать инструкцию (один раз).
    func firstRun() {
        guard Keychain.load("refresh") == nil, !UserDefaults.standard.bool(forKey: Self.guideSeenKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.guideSeenKey)
        phase = .guide
    }

    func open(_ url: URL) {
        guard let link = Self.parse(url) else { return }
        guard let code = link.code else { phase = .guide; return }
        phase = .connecting
        Task { await claim(code: code, api: link.api) }
    }

    /// jarvis://pair?code=AB12CD&api=https://api... -> (код, адрес API); не наша ссылка - nil.
    nonisolated static func parse(_ url: URL) -> (code: String?, api: URL?)? {
        guard url.scheme == "jarvis", url.host == "pair" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let code = items.first { $0.name == "code" }?.value.flatMap { value -> String? in
            let clean = value.trimmingCharacters(in: .whitespaces)
            return clean.count >= 4 && clean.count <= 64 && clean.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" || $0 == "_" })
                ? clean : nil
        }
        let api = items.first { $0.name == "api" }?.value.flatMap(URL.init(string:))
            .flatMap { $0.scheme == "https" ? $0 : nil }  // вход - только по https
        return (code, api)
    }

    private func claim(code: String, api: URL?) async {
        guard let base = api ?? Keychain.load("base").flatMap(URL.init(string:)),
              let url = URL(string: "api/pair/claim", relativeTo: base.absoluteString.hasSuffix("/") ? base
                              : URL(string: base.absoluteString + "/")) else {
            phase = .failed("В QR нет адреса сервера. Обновите NMNH Agent на ПК и покажите QR снова.")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard status == 200, let access = body["access_token"] as? String,
                  let refresh = body["refresh_token"] as? String else {
                phase = .failed(status == 400 || status == 404 || status == 410 ? "Код устарел или уже использован. Покажите на ПК новый QR."
                                : "Сервер не принял код (\(status)). Попробуйте новый QR.")
                return
            }
            Keychain.save(refresh, as: "refresh")
            Keychain.save((api ?? base).absoluteString, as: "base")
            deliver?(access, refresh)
            phase = .done
        } catch {
            phase = .failed("Нет связи с сервером. Проверьте интернет и попробуйте ещё раз.")
        }
    }
}

/// Окно подключения: инструкция, ход и итог.
struct ConnectSheet: View {
    @ObservedObject var pairing: Pairing

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                SpiritView(id: "jarvis", busy: pairing.phase == .connecting, size: 34)
                Text("Подключение к NMNH").font(.system(size: 20, weight: .bold))
            }
            switch pairing.phase {
            case .connecting:
                HStack(spacing: 10) { ProgressView(); Text("Подключаю телефон…") }
            case .done:
                Label("Готово: телефон подключён, вход выполнен.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DashTheme.money)
                Button("Продолжить") { pairing.phase = nil }.buttonStyle(.borderedProminent)
            case .failed(let why):
                Label(why, systemImage: "xmark.circle.fill").foregroundStyle(DashTheme.down)
                steps
            default:
                steps
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            step(1, "На ПК откройте NMNH Agent: значок в трее -> «Подключение…» -> раздел «Телефон».")
            step(2, "Наведите камеру iPhone на QR и нажмите на появившуюся ссылку.")
            step(3, "Приложение само войдёт - пароль не нужен. Код живёт 5 минут.")
            Text("Уже входили на странице паролем? Это окно можно просто закрыть.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Button("Закрыть") { pairing.phase = nil }.buttonStyle(.bordered)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.system(size: 13, weight: .bold)).frame(width: 22, height: 22)
                .background(Circle().fill(SpiritView.color("jarvis").opacity(0.25)))
            Text(text).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    /// Ссылки jarvis://pair и окно подключения поверх приложения.
    func pairSheet(pairing: Pairing = .shared) -> some View {
        modifier(PairSheetHost(pairing: pairing))
    }
}

private struct PairSheetHost: ViewModifier {
    @ObservedObject var pairing: Pairing

    func body(content: Content) -> some View {
        content
            .onOpenURL { pairing.open($0) }
            .sheet(isPresented: Binding(get: { pairing.phase != nil }, set: { if !$0 { pairing.phase = nil } })) {
                ConnectSheet(pairing: pairing)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }
}
