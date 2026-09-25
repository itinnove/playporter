import AppKit
import CryptoKit

/// Auto-update intégré : lit un manifeste JSON distant, compare la version,
/// télécharge l'archive, vérifie le sha256, remplace Playporter.app et relance.
/// Manifeste attendu :
/// { "version":"0.2.0", "url":"https://…/Playporter-0.2.0.zip", "sha256":"…", "notes":"…" }
enum Updater {
    static let manifestURL = "https://playporter.itinnove.com/latest.json"

    struct Manifest: Codable, Equatable {
        let version: String
        let url: String
        let sha256: String?
        let notes: String?
    }

    enum UpdaterError: LocalizedError {
        case badURL, badArchive(String), checksum
        var errorDescription: String? {
            switch self {
            case .badURL: return "Lien de mise à jour invalide"
            case .badArchive(let d): return "Archive invalide (\(d))"
            case .checksum: return "Somme de contrôle invalide (archive corrompue)"
            }
        }
    }

    static func currentVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    static func fetchManifest() async throws -> Manifest {
        guard let url = URL(string: manifestURL) else { throw UpdaterError.badURL }
        var r = URLRequest(url: url)
        r.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: r)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    /// true si `remote` > version courante (comparaison numérique par segments).
    static func isNewer(_ remote: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
        let a = parts(remote), b = parts(currentVersion())
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Télécharge, vérifie, remplace l'app et relance. Termine le process.
    static func performUpdate(_ m: Manifest) async throws {
        guard let url = URL(string: m.url) else { throw UpdaterError.badURL }
        let (tmp, _) = try await URLSession.shared.download(from: url)

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("playporter-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: tmp, to: zip)

        if let want = m.sha256, !want.isEmpty {
            let data = try Data(contentsOf: zip)
            let got = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard got.caseInsensitiveCompare(want) == .orderedSame else { throw UpdaterError.checksum }
        }

        let out = work.appendingPathComponent("out")
        try run("/usr/bin/ditto", ["-xk", zip.path, out.path])

        let newApp = try findApp(in: out)
        let oldPath = Bundle.main.bundlePath
        let appsDir = (oldPath as NSString).deletingLastPathComponent
        let newDest = appsDir + "/" + newApp.lastPathComponent

        // Script d'échange : attend la fermeture, remplace, nettoie quarantaine, relance.
        let script = work.appendingPathComponent("swap.sh")
        let sh = """
        #!/bin/bash
        sleep 1
        rm -rf "\(newDest)"
        mv "\(newApp.path)" "\(newDest)"
        if [ "\(oldPath)" != "\(newDest)" ]; then rm -rf "\(oldPath)"; fi
        xattr -dr com.apple.quarantine "\(newDest)" 2>/dev/null
        open "\(newDest)"
        """
        try sh.write(to: script, atomically: true, encoding: .utf8)
        try run("/bin/chmod", ["+x", script.path])

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path]
        try p.run()
        NSApp.terminate(nil)
    }

    // MARK: - helpers
    private static func findApp(in dir: URL) throws -> URL {
        let fm = FileManager.default
        let direct = dir.appendingPathComponent("Playporter.app")
        if fm.fileExists(atPath: direct.path) { return direct }
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        if let app = items.first(where: { $0.pathExtension == "app" }) { return app }
        throw UpdaterError.badArchive("aucun .app trouvé")
    }

    private static func run(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw UpdaterError.badArchive("échec \(path) code \(p.terminationStatus)")
        }
    }
}
