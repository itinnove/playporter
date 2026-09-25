import Foundation

enum PlayPublisherError: LocalizedError {
    case api(String)
    case unexpectedResponse(String)

    var errorDescription: String? {
        switch self {
        case .api(let m): return m
        case .unexpectedResponse(let m): return "Réponse inattendue de l'API Play (\(m))"
        }
    }
}

struct UploadResult {
    let versionCode: Int
    let appName: String?
}

/// Drives the Google Play Developer API "edits" flow to push an AAB to the
/// internal testing track.
struct PlayPublisher {
    let accessToken: String

    private let apiBase = "https://androidpublisher.googleapis.com/androidpublisher/v3"
    private let uploadBase = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3"

    /// Full pipeline: insert edit → (read app name) → upload bundle → assign to
    /// the chosen track → commit. Returns the recorded versionCode and, if
    /// available, the app's store title.
    func publish(
        aab: URL,
        packageName: String,
        track: String,
        progress: @escaping (String) -> Void
    ) async throws -> UploadResult {
        progress("Création d'une révision…")
        let editId = try await insertEdit(packageName: packageName)

        let appName = try? await fetchAppName(packageName: packageName, editId: editId)

        progress("Upload de l'AAB…")
        let versionCode = try await uploadBundle(aab: aab, packageName: packageName, editId: editId)

        progress("Assignation au canal \(PlayTrack.label(for: track))…")
        try await assignTrack(packageName: packageName, editId: editId, versionCode: versionCode, track: track)

        progress("Validation…")
        try await commit(packageName: packageName, editId: editId)

        return UploadResult(versionCode: versionCode, appName: appName)
    }

    /// Best-effort: reads the app title from its store listing.
    private func fetchAppName(packageName: String, editId: String) async throws -> String? {
        let url = URL(string: "\(apiBase)/applications/\(enc(packageName))/edits/\(enc(editId))/listings")!
        let data = try await send(url, method: "GET")
        guard let json = jsonObject(data),
              let listings = json["listings"] as? [[String: Any]] else { return nil }
        // Prefer the default language, else the first non-empty title.
        let titles = listings.compactMap { $0["title"] as? String }.filter { !$0.isEmpty }
        return titles.first
    }

    // MARK: - Steps

    private func insertEdit(packageName: String) async throws -> String {
        let url = URL(string: "\(apiBase)/applications/\(enc(packageName))/edits")!
        let data = try await send(url, method: "POST")
        guard let json = jsonObject(data), let id = json["id"] as? String else {
            throw PlayPublisherError.unexpectedResponse("edit sans id")
        }
        return id
    }

    private func uploadBundle(aab: URL, packageName: String, editId: String) async throws -> Int {
        let url = URL(string: "\(uploadBase)/applications/\(enc(packageName))/edits/\(enc(editId))/bundles?uploadType=media")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.upload(for: req, fromFile: aab)
        try check(resp, data)
        guard let json = jsonObject(data), let vc = json["versionCode"] as? Int else {
            throw PlayPublisherError.unexpectedResponse("versionCode manquant après upload")
        }
        return vc
    }

    private func assignTrack(packageName: String, editId: String, versionCode: Int, track: String) async throws {
        let url = URL(string: "\(apiBase)/applications/\(enc(packageName))/edits/\(enc(editId))/tracks/\(enc(track))")!
        let body: [String: Any] = [
            "track": track,
            "releases": [
                ["status": "completed", "versionCodes": [String(versionCode)]]
            ],
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await send(url, method: "PUT", jsonBody: payload)
    }

    private func commit(packageName: String, editId: String) async throws {
        let url = URL(string: "\(apiBase)/applications/\(enc(packageName))/edits/\(enc(editId)):commit")!
        _ = try await send(url, method: "POST")
    }

    // MARK: - HTTP helpers

    private func send(_ url: URL, method: String, jsonBody: Data? = nil) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let jsonBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = jsonBody
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp, data)
        return data
    }

    private func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            if let json = jsonObject(data),
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw PlayPublisherError.api(message)
            }
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw PlayPublisherError.api("HTTP \(http.statusCode) \(raw.prefix(200))")
        }
    }

    private func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }
}
