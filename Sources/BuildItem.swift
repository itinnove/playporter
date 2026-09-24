import Foundation

/// A build in the Playporter list — either waiting to be sent, in flight, sent,
/// or failed. Persisted so the list survives relaunches (like Transporter).
struct BuildItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var packageName: String
    var versionCode: Int?
    var versionName: String?
    var filePath: String
    var track: String
    var status: Status
    var date: Date
    var detail: String?

    enum Status: String, Codable {
        case ready       // dropped, not yet uploaded
        case uploading   // in flight
        case sent        // delivered to the track
        case failed
    }

    init(info: AABInfo) {
        self.packageName = info.applicationId
        self.versionCode = info.versionCode
        self.versionName = info.versionName
        self.filePath = info.fileURL.path
        self.track = "internal"
        self.status = .ready
        self.date = Date()
        self.detail = nil
    }

    var fileURL: URL { URL(fileURLWithPath: filePath) }
    var fileExists: Bool { FileManager.default.fileExists(atPath: filePath) }

    var versionLabel: String {
        switch (versionName, versionCode) {
        case let (name?, code?): return "\(name) (\(code))"
        case let (name?, nil): return name
        case let (nil, code?): return "build \(code)"
        default: return "—"
        }
    }
}
