import Foundation
import Security

/// Сервер NMNH для нативной части: голос Джарвис, лента агентов, озвучка.
///
/// Токен наставника живёт 15 минут. В фоне страница спит и его не обновляет, поэтому
/// приложение держит свой refresh (живёт 30 дней, сервер его не отзывает при обновлении)
/// и само берёт свежий access на 401.
final class ServerAPI {
    struct Reply: Decodable {
        let heard: String
        let text: String
        let audio: String
    }

    enum Failure: Error { case unauthorized, server(Int), network }

    /// «номер сборки коммит» - сервер запоминает, какая версия стоит на телефоне.
    static let build: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleVersion"] as? String ?? "?") \(info["JarvisCommit"] as? String ?? "?")"
    }()

    private(set) var base: URL
    private var access: String
    private var refresh: String
    private let session: URLSession

    init(base: URL, access: String, refresh: String) {
        self.base = base
        self.access = access
        self.refresh = refresh
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90  // Джарвис думает и озвучивает - до минуты
        session = URLSession(configuration: config)
    }

    func update(access: String, refresh: String) {
        self.access = access
        if !refresh.isEmpty { self.refresh = refresh }
    }

    /// target: jarvis - ответ Джарвис голосом; server, pc - диктовка в чат агента.
    func sendVoice(_ audio: Data, to target: String = "jarvis") async throws -> Reply {
        let data = try await call("api/admin/voice/\(target)", method: "POST", body: audio, type: "audio/mp4")
        return try JSONDecoder().decode(Reply.self, from: data)
    }

    func agents() async throws -> [String: Any] {
        let data = try await call("api/admin/agents")
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Сводка пульта для островка и виджетов (pult_island.py).
    func island() async throws -> Dash {
        let data = try await call("api/admin/agents/island")
        guard let dash = Dash.decode(data) else { throw Failure.server(0) }
        return dash
    }

    func speech(_ text: String, jarvis: Bool = true) async throws -> Data {
        var parts = URLComponents()
        parts.queryItems = [URLQueryItem(name: "text", value: String(text.prefix(1500))),
                            URLQueryItem(name: "jarvis", value: jarvis ? "true" : "false")]
        return try await call("api/admin/voice/tts?" + (parts.percentEncodedQuery ?? ""))
    }

    private func call(_ path: String, method: String = "GET", body: Data? = nil, type: String? = nil,
                      retry: Bool = true) async throws -> Data {
        guard let url = URL(string: path, relativeTo: base) else { throw Failure.network }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "ngrok-skip-browser-warning")
        request.setValue(Self.build, forHTTPHeaderField: "X-Jarvis-Build")
        if let type { request.setValue(type, forHTTPHeaderField: "Content-Type") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.network
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && retry {
            try await renew()
            return try await call(path, method: method, body: body, type: type, retry: false)
        }
        if code == 401 { throw Failure.unauthorized }
        guard (200..<300).contains(code) else { throw Failure.server(code) }
        return data
    }

    private func renew() async throws {
        guard !refresh.isEmpty, let url = URL(string: "api/auth/refresh", relativeTo: base) else {
            throw Failure.unauthorized
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refresh])
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let pair = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let fresh = pair["access_token"] as? String else {
            throw Failure.unauthorized
        }
        access = fresh
        if let next = pair["refresh_token"] as? String { refresh = next }
        Keychain.save(refresh, as: "refresh")
    }
}

/// Refresh наставника - в связке ключей iOS, не в файлах приложения.
enum Keychain {
    private static let service = "trade.nmnh.jarvis"

    static func save(_ value: String, as key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock  // в фоне при заблокированном экране
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: key,
                                    kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}
