import Foundation

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
