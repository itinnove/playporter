import Foundation
import CryptoKit
import Network
import AppKit

enum GoogleAuthError: LocalizedError {
    case notSignedIn
    case listenerFailed(String)
    case oauthError(String)
    case badTokenResponse(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Non connecté à Google"
        case .listenerFailed(let d): return "Serveur local impossible (\(d))"
        case .oauthError(let d): return "Autorisation refusée ou invalide (\(d))"
        case .badTokenResponse(let d): return "Réponse du serveur de tokens invalide (\(d))"
        }
    }
}

// MARK: - PKCE

enum PKCE {
    static func randomURLSafe(_ byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Loopback redirect catcher

/// Listens on 127.0.0.1 with an OS-assigned port, opens once to receive the
/// OAuth redirect, replies with a small HTML page, then stops.
final class LoopbackAuthReceiver {
    private var listener: NWListener?
    private var connection: NWConnection?
    private var redirectContinuation: CheckedContinuation<URLComponents, Error>?
    private var didFinish = false

    /// Starts the listener and returns the assigned loopback port.
    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)

        let listener: NWListener
        do {
            listener = try NWListener(using: params)
        } catch {
            throw GoogleAuthError.listenerFailed(error.localizedDescription)
        }
        self.listener = listener

        var resumed = false
        return try await withCheckedThrowingContinuation { cont in
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    if let port = listener.port?.rawValue {
                        cont.resume(returning: port)
                    } else {
                        cont.resume(throwing: GoogleAuthError.listenerFailed("port introuvable"))
                    }
                case .failed(let e):
                    resumed = true
                    cont.resume(throwing: GoogleAuthError.listenerFailed(e.localizedDescription))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            listener.start(queue: .main)
        }
    }

    /// Suspends until the browser hits the loopback URL.
    func waitForRedirect() async throws -> URLComponents {
        try await withCheckedThrowingContinuation { cont in
            self.redirectContinuation = cont
        }
    }

    func stop() {
        listener?.cancel(); listener = nil
        connection?.cancel(); connection = nil
    }

    private func handle(_ conn: NWConnection) {
        connection = conn
        conn.start(queue: .main)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self else { return }
            guard let data, let request = String(data: data, encoding: .utf8) else {
                self.finish(throwing: GoogleAuthError.oauthError("requête vide")); return
            }
            let firstLine = request.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
            let tokens = firstLine.split(separator: " ")
            guard tokens.count >= 2, let comps = URLComponents(string: "http://127.0.0.1\(tokens[1])") else {
                self.finish(throwing: GoogleAuthError.oauthError("redirection illisible")); return
            }
            let body = """
            <!doctype html><html><head><meta charset="utf-8"></head>
            <body style="font-family:-apple-system,system-ui;text-align:center;padding-top:64px;color:#1d1d1f">
            <h2>✅ Playporter connecté</h2><p>Vous pouvez fermer cet onglet et revenir à l'app.</p>
            </body></html>
            """
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
            conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
            self.finish(with: comps)
        }
    }

    private func finish(with comps: URLComponents) {
        guard !didFinish else { return }
        didFinish = true
        redirectContinuation?.resume(returning: comps)
        redirectContinuation = nil
    }

    private func finish(throwing error: Error) {
        guard !didFinish else { return }
        didFinish = true
        redirectContinuation?.resume(throwing: error)
        redirectContinuation = nil
    }
}

// MARK: - Google auth

final class GoogleAuth {
    static let shared = GoogleAuth()
    private let refreshAccount = "google.refreshToken"

    var isAuthorized: Bool { KeychainStore.getString(account: refreshAccount) != nil }

    func signOut() { KeychainStore.delete(account: refreshAccount) }

    /// Full interactive sign-in; stores the refresh token in the keychain.
    func signIn() async throws {
        let verifier = PKCE.randomURLSafe(32)
        let challenge = PKCE.challenge(for: verifier)
        let state = PKCE.randomURLSafe(16)

        let receiver = LoopbackAuthReceiver()
        let port = try await receiver.start()
        defer { receiver.stop() }
        let redirectURI = "http://127.0.0.1:\(port)"

        var comps = URLComponents(string: Secrets.authURI)!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: Secrets.clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: Secrets.scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "state", value: state),
        ]
        guard let authURL = comps.url else { throw GoogleAuthError.oauthError("URL d'autorisation invalide") }
        await MainActor.run { _ = NSWorkspace.shared.open(authURL) }

        let redirect = try await receiver.waitForRedirect()
        let items = redirect.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            throw GoogleAuthError.oauthError(err)
        }
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw GoogleAuthError.oauthError("state invalide")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.oauthError("code manquant")
        }

        let refresh = try await exchangeCode(code, verifier: verifier, redirectURI: redirectURI)
        KeychainStore.setString(refresh, account: refreshAccount)
    }

    /// A fresh access token, obtained from the stored refresh token.
    func accessToken() async throws -> String {
        guard let refresh = KeychainStore.getString(account: refreshAccount) else {
            throw GoogleAuthError.notSignedIn
        }
        let json = try await postForm(Secrets.tokenURI, [
            "client_id": Secrets.clientID,
            "client_secret": Secrets.clientSecret,
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        ])
        guard let token = json["access_token"] as? String else {
            throw GoogleAuthError.badTokenResponse("access_token manquant")
        }
        return token
    }

    private func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws -> String {
        let json = try await postForm(Secrets.tokenURI, [
            "code": code,
            "client_id": Secrets.clientID,
            "client_secret": Secrets.clientSecret,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ])
        guard let refresh = json["refresh_token"] as? String else {
            throw GoogleAuthError.badTokenResponse("refresh_token manquant")
        }
        return refresh
    }

    private func postForm(_ urlString: String, _ params: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw GoogleAuthError.oauthError("URL invalide") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params
            .map { "\($0.key)=\(percentEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let obj = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let desc = (obj["error_description"] as? String) ?? (obj["error"] as? String) ?? "HTTP \(http.statusCode)"
            throw GoogleAuthError.badTokenResponse(desc)
        }
        return obj
    }

    private func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
