// The connection to Suwayomi-Server: where it lives, and one function that runs a GraphQL
// document against it.

import Foundation
import Observation
import Security

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The server answered 401: it wants a username and password, or didn't like the ones it got.
struct LoginNeeded: LocalizedError {
    var errorDescription: String? { "The server didn't accept the login" }
}

struct Login: Codable, Equatable {
    var username: String
    var password: String

    var header: String {
        "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }

    // Kept in the keychain, not in preferences.
    private static let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "dev.kalki.yomu.server",
        kSecAttrAccount: "login",
    ]

    static func saved() -> Login? {
        var result: CFTypeRef?
        let find = query.merging([kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]) { $1 }
        guard SecItemCopyMatching(find as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Login.self, from: data)
    }

    static func save(_ login: Login?) {
        SecItemDelete(query as CFDictionary)
        guard let login, let data = try? JSONEncoder().encode(login) else { return }
        let add = query.merging([kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock]) { $1 }
        SecItemAdd(add as CFDictionary, nil)
    }
}

@Observable final class Server {
    static let shared = Server()

    private(set) var base: URL?
    private(set) var login: Login?

    private init() {
        base = UserDefaults.standard.string(forKey: "serverURL").flatMap(URL.init(string:))
        login = base == nil ? nil : Login.saved()
    }

    func use(_ url: URL?, login: Login? = nil) {
        base = url
        self.login = url == nil ? nil : login
        Login.save(self.login)
        UserDefaults.standard.set(url?.absoluteString, forKey: "serverURL")
        Reach.shared.forget()
    }

    /// The server hands back paths like `/api/v1/manga/1/thumbnail`.
    func url(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("file://") { return URL(string: path) }
        guard let base else { return nil }
        return URL(string: base.absoluteString + (path.hasPrefix("/") ? path : "/" + path))
    }

    /// A request for anything on the server, carrying the login if there is one.
    func request(_ url: URL, login: Login? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        if !url.isFileURL, let login = login ?? self.login {
            request.setValue(login.header, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Turns what someone types ("192.168.1.3", "manga.example.com:8080", a full URL) into a base
    /// address. A bare host gets http and Suwayomi's own port.
    static func address(from text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }
        let typedScheme = text.contains("://")
        if !typedScheme { text = "http://" + text }
        guard var parts = URLComponents(string: text), let host = parts.host, !host.isEmpty else { return nil }
        if !typedScheme, parts.port == nil { parts.port = 4567 }
        return parts.url
    }
}

enum GQL {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private struct Envelope<T: Decodable>: Decodable {
        let data: T?
        let errors: [Failure]?
    }

    private struct Failure: Decodable {
        let message: String
    }

    static func run<T: Decodable>(_ document: String, _ variables: [String: Any] = [:], at base: URL? = nil, login: Login? = nil) async throws -> T {
        guard let base = base ?? Server.shared.base else { throw APIError(message: "No server set") }
        var request = Server.shared.request(base.appendingPathComponent("api/graphql"), login: login)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": document, "variables": variables])
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
            Reach.shared.mark(true)
        } catch let error as URLError {
            let unreachable: [URLError.Code] = [.cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .networkConnectionLost]
            if unreachable.contains(error.code) { Reach.shared.mark(false) }
            throw error
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 401 { throw LoginNeeded() }
        let envelope: Envelope<T>
        do {
            envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        } catch {
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw APIError(message: "The server answered \(http.statusCode)")
            }
            throw error
        }
        if let failure = envelope.errors?.first { throw APIError(message: failure.message) }
        guard let value = envelope.data else { throw APIError(message: "The server sent nothing back") }
        return value
    }
}
