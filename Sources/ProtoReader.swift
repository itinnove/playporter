import Foundation

/// Minimal, dependency-free protobuf wire-format reader.
///
/// Only supports what we need to walk the aapt2 proto-encoded `AndroidManifest.xml`
/// contained in an AAB: varints and length-delimited fields. It deliberately does
/// not know the schema — callers navigate by field number.
struct ProtoReader {
    private let bytes: [UInt8]
    private var index: Int = 0

    init(_ data: Data) { self.bytes = [UInt8](data) }
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { index >= bytes.count }

    /// A single field read from the stream.
    struct Field {
        let number: Int
        let wireType: Int
        /// Payload for length-delimited fields (wire type 2).
        let lengthDelimited: [UInt8]?
        /// Value for varint fields (wire type 0).
        let varint: UInt64?
    }

    private mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    /// Reads the next field, or nil at end / on malformed data.
    mutating func next() -> Field? {
        guard let key = readVarint() else { return nil }
        let number = Int(key >> 3)
        let wireType = Int(key & 0x07)
        switch wireType {
        case 0: // varint
            guard let v = readVarint() else { return nil }
            return Field(number: number, wireType: wireType, lengthDelimited: nil, varint: v)
        case 2: // length-delimited
            guard let len = readVarint() else { return nil }
            let n = Int(len)
            guard n >= 0, index + n <= bytes.count else { return nil }
            let slice = Array(bytes[index ..< index + n])
            index += n
            return Field(number: number, wireType: wireType, lengthDelimited: slice, varint: nil)
        case 1: // 64-bit
            guard index + 8 <= bytes.count else { return nil }
            index += 8
            return Field(number: number, wireType: wireType, lengthDelimited: nil, varint: nil)
        case 5: // 32-bit
            guard index + 4 <= bytes.count else { return nil }
            index += 4
            return Field(number: number, wireType: wireType, lengthDelimited: nil, varint: nil)
        default:
            return nil
        }
    }

    /// Collects every field in this message.
    static func fields(in data: [UInt8]) -> [Field] {
        var reader = ProtoReader(data)
        var out: [Field] = []
        while let f = reader.next() { out.append(f) }
        return out
    }
}
