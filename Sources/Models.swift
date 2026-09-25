import Foundation

/// A Google Play release track.
enum PlayTrack: String, CaseIterable, Identifiable, Sendable {
    case internalTest = "internal"
    case alpha
    case beta
    case production

    var id: String { rawValue }

    var label: String {
        switch self {
        case .internalTest: return "Test interne"
        case .alpha: return "Test fermé (alpha)"
        case .beta: return "Test ouvert (bêta)"
        case .production: return "Production"
        }
    }

    /// Display label for a raw track value stored on a build.
    static func label(for raw: String) -> String {
        PlayTrack(rawValue: raw)?.label ?? raw
    }
}

/// Metadata extracted from an Android App Bundle (.aab).
struct AABInfo: Equatable, Sendable {
    /// The `applicationId` declared in the manifest (e.g. "com.itinnove.seineyonne").
    let applicationId: String
    /// android:versionCode, if it could be decoded.
    let versionCode: Int?
    /// android:versionName, if present.
    let versionName: String?
    /// The bundle file on disk.
    let fileURL: URL

    var fileName: String { fileURL.lastPathComponent }
}
