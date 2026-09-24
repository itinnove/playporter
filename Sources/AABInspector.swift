import Foundation

enum AABInspectorError: LocalizedError {
    case unzipFailed(String)
    case emptyManifest
    case malformedManifest
    case packageNotFound

    var errorDescription: String? {
        switch self {
        case .unzipFailed(let detail): return "Décompression impossible (\(detail))"
        case .emptyManifest: return "Manifeste vide dans l'AAB"
        case .malformedManifest: return "Manifeste illisible (format inattendu)"
        case .packageNotFound: return "Aucun applicationId trouvé dans le manifeste"
        }
    }
}

/// Reads an Android App Bundle without Java/bundletool.
///
/// The bundle is a zip; `base/manifest/AndroidManifest.xml` inside it is aapt2
/// proto-encoded. We extract it with `/usr/bin/unzip` and walk the proto tree
/// (XmlNode → XmlElement → XmlAttribute) to read the root `<manifest>` attributes.
enum AABInspector {

    static func inspect(_ url: URL) throws -> AABInfo {
        let manifest = try extractManifestProto(from: url)
        let attrs = try rootAttributes(from: manifest)
        guard let pkg = attrs["package"], !pkg.isEmpty else {
            throw AABInspectorError.packageNotFound
        }
        return AABInfo(
            applicationId: pkg,
            versionCode: attrs["versionCode"].flatMap { Int($0) },
            versionName: attrs["versionName"],
            fileURL: url
        )
    }

    // MARK: - Zip extraction

    private static func extractManifestProto(from url: URL) throws -> [UInt8] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, "base/manifest/AndroidManifest.xml"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw AABInspectorError.unzipFailed(error.localizedDescription)
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AABInspectorError.unzipFailed(err.isEmpty ? "code \(process.terminationStatus)" : err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard !data.isEmpty else { throw AABInspectorError.emptyManifest }
        return [UInt8](data)
    }

    // MARK: - Proto walk
    // XmlNode:      element = 1
    // XmlElement:   name = 3, attribute = 4 (repeated)
    // XmlAttribute: name = 2, value = 3 (string), compiled_item = 6

    private static func rootAttributes(from manifest: [UInt8]) throws -> [String: String] {
        let top = ProtoReader.fields(in: manifest)
        guard let elementBytes = top.first(where: { $0.number == 1 && $0.wireType == 2 })?.lengthDelimited else {
            throw AABInspectorError.malformedManifest
        }
        let element = ProtoReader.fields(in: elementBytes)
        var result: [String: String] = [:]
        for field in element where field.number == 4 && field.wireType == 2 {
            guard let attrBytes = field.lengthDelimited else { continue }
            let attr = ProtoReader.fields(in: attrBytes)
            guard let name = string(from: attr, field: 2), !name.isEmpty else { continue }
            if let value = string(from: attr, field: 3), !value.isEmpty {
                result[name] = value
            } else if let compiled = attr.first(where: { $0.number == 6 && $0.wireType == 2 })?.lengthDelimited,
                      let intValue = primitiveInt(fromItem: compiled) {
                result[name] = String(intValue)
            }
        }
        return result
    }

    private static func string(from fields: [ProtoReader.Field], field: Int) -> String? {
        guard let bytes = fields.first(where: { $0.number == field && $0.wireType == 2 })?.lengthDelimited else {
            return nil
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    // Item.prim = 7  →  Primitive.int_decimal_value = 6 / int_hexadecimal_value = 7
    private static func primitiveInt(fromItem itemBytes: [UInt8]) -> Int? {
        let item = ProtoReader.fields(in: itemBytes)
        guard let primBytes = item.first(where: { $0.number == 7 && $0.wireType == 2 })?.lengthDelimited else {
            return nil
        }
        let prim = ProtoReader.fields(in: primBytes)
        guard let v = prim.first(where: { ($0.number == 6 || $0.number == 7) && $0.wireType == 0 })?.varint else {
            return nil
        }
        return v <= UInt64(Int.max) ? Int(v) : nil
    }
}
