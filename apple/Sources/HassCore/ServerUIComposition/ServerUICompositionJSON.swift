import Foundation

// MARK: - Bounded strict JSON

/// Reuses `JSONValue` without its intentionally permissive entity-attribute decoder.
/// Duplicate detection happens on the decoded dictionary's key set, so keys that are canonically equivalent
/// (and would merge in a `[String: JSONValue]`) are rejected as duplicates just like byte-identical keys.
struct ServerUICompositionJSON {
    static let maximumDocumentBytes = 2_097_152
    static let maximumOverheadBytes = 65_536
    static let maximumBytes = maximumDocumentBytes + maximumOverheadBytes
    static let reserved: Set<String> = ["__proto__", "prototype", "constructor"]

    private let bytes: [UInt8]
    private var index = 0
    private var values = 0
    private var issues: [ServerUICompositionError] = []

    init(_ data: Data) throws {
        guard data.count <= Self.maximumBytes else {
            throw ServerUICompositionError(.limitExceeded, "")
        }
        bytes = Array(data)
    }

    mutating func parse() throws -> JSONValue {
        let value = try value(at: "", depth: 0)
        whitespace()
        guard index == bytes.count else { throw ServerUICompositionError(.invalidValue, "") }
        if let first = ServerUICompositionShape.first(issues) { throw first }
        return value
    }

    static func pointer(_ parent: String, _ key: String) -> String {
        parent + "/" + key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }

    private mutating func value(at pointer: String, depth: Int) throws -> JSONValue {
        whitespace()
        values += 1
        guard values <= 100_000, depth <= 40 else {
            throw ServerUICompositionError(.limitExceeded, pointer)
        }
        guard index < bytes.count else { throw ServerUICompositionError(.invalidValue, pointer) }
        switch bytes[index] {
        case 123:
            index += 1
            whitespace()
            var object: [String: JSONValue] = [:]
            var entries = 0
            if take(125) { return .object(object) }
            while true {
                whitespace()
                let key = try string(at: pointer)
                let child = Self.pointer(pointer, key)
                if object[key] != nil { issues.append(ServerUICompositionError(.duplicateKey, child)) }
                entries += 1
                guard entries <= 1_000 else { throw ServerUICompositionError(.limitExceeded, pointer) }
                if Self.reserved.contains(key) { issues.append(ServerUICompositionError(.invalidValue, child)) }
                whitespace()
                guard take(58) else { throw ServerUICompositionError(.invalidValue, child) }
                object[key] = try value(at: child, depth: depth + 1)
                whitespace()
                if take(125) { break }
                guard take(44) else { throw ServerUICompositionError(.invalidValue, pointer) }
            }
            return .object(object)
        case 91:
            index += 1
            whitespace()
            var array: [JSONValue] = []
            if take(93) { return .array(array) }
            while true {
                guard array.count < 1_000 else { throw ServerUICompositionError(.limitExceeded, pointer) }
                array.append(try value(at: Self.pointer(pointer, String(array.count)), depth: depth + 1))
                whitespace()
                if take(93) { break }
                guard take(44) else { throw ServerUICompositionError(.invalidValue, pointer) }
            }
            return .array(array)
        case 34: return .string(try string(at: pointer))
        case 116: try literal("true", at: pointer); return .bool(true)
        case 102: try literal("false", at: pointer); return .bool(false)
        case 110: try literal("null", at: pointer); return .null
        default: return try number(at: pointer)
        }
    }

    private mutating func string(at pointer: String) throws -> String {
        let start = index
        guard take(34) else { throw ServerUICompositionError(.invalidValue, pointer) }
        // Plain ASCII needs no decoder; only an escape or a non-ASCII byte takes the slow path.
        var plain = true
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 {
                if plain { return String(decoding: bytes[(start + 1)..<(index - 1)], as: UTF8.self) }
                let data = Data(bytes[start..<index])
                do {
                    // JSONDecoder rejects malformed escapes, lone surrogates, and invalid UTF-8.
                    return try JSONDecoder().decode(String.self, from: data)
                } catch {
                    throw ServerUICompositionError(.invalidValue, pointer)
                }
            }
            guard byte >= 32 else { throw ServerUICompositionError(.invalidValue, pointer) }
            if byte >= 128 { plain = false }
            if byte == 92 {
                plain = false
                guard index < bytes.count else { throw ServerUICompositionError(.invalidValue, pointer) }
                index += 1
            }
        }
        throw ServerUICompositionError(.invalidValue, pointer)
    }

    private mutating func number(at pointer: String) throws -> JSONValue {
        let start = index
        _ = take(45)
        if !take(48) {
            guard index < bytes.count, (49...57).contains(bytes[index]) else {
                throw ServerUICompositionError(.invalidValue, pointer)
            }
            digits()
        }
        if take(46) {
            let before = index
            digits()
            guard before < index else { throw ServerUICompositionError(.invalidValue, pointer) }
        }
        if take(101) || take(69) {
            if !take(43) { _ = take(45) }
            let before = index
            digits()
            guard before < index else { throw ServerUICompositionError(.invalidValue, pointer) }
        }
        guard let number = Double(String(decoding: bytes[start..<index], as: UTF8.self)), number.isFinite else {
            throw ServerUICompositionError(.invalidValue, pointer)
        }
        return .number(number)
    }

    private mutating func literal(_ text: String, at pointer: String) throws {
        for byte in text.utf8 {
            guard take(byte) else { throw ServerUICompositionError(.invalidValue, pointer) }
        }
    }
    private mutating func digits() {
        while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
    }
    private mutating func whitespace() {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }
    private mutating func take(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    // MARK: - Canonical byte accounting and manifest JCS

    /// RFC 8785 strings, UTF-16 key order, no insignificant whitespace, and shortest numbers.
    /// Manifest numbers are validated safe, positive integers, so their serialization is exact.
    static func canonical(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return canonicalNumber(value)
        case .string(let value): return quoted(value)
        case .array(let array): return "[" + array.map(canonical).joined(separator: ",") + "]"
        case .object(let object):
            return "{" + object.sorted { $0.key.utf16.lexicographicallyPrecedes($1.key.utf16) }.map {
                quoted($0.key) + ":" + canonical($0.value)
            }.joined(separator: ",") + "}"
        }
    }

    private static func quoted(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 8: result += "\\b"
            case 9: result += "\\t"
            case 10: result += "\\n"
            case 12: result += "\\f"
            case 13: result += "\\r"
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 0...31: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    private static func canonicalNumber(_ value: Double) -> String {
        if value == 0 { return "0" }
        if abs(value) <= 9_007_199_254_740_991, value.rounded() == value { return String(Int64(value)) }
        let sign = value < 0 ? "-" : ""
        let parts = String(abs(value)).lowercased().split(separator: "e")
        let mantissa = String(parts[0])
        let exponent = parts.count == 2 ? Int(parts[1])! : 0
        let decimal = mantissa.firstIndex(of: ".").map { mantissa.distance(from: mantissa.startIndex, to: $0) } ?? mantissa.count
        var digits = mantissa.replacingOccurrences(of: ".", with: "")
        var position = decimal + exponent
        while digits.first == "0" { digits.removeFirst(); position -= 1 }
        while digits.last == "0" { digits.removeLast() }
        if position > 0, position <= 21 {
            if position >= digits.count { return sign + digits + String(repeating: "0", count: position - digits.count) }
            let split = digits.index(digits.startIndex, offsetBy: position)
            return sign + digits[..<split] + "." + digits[split...]
        }
        if position <= 0, position > -6 {
            return sign + "0." + String(repeating: "0", count: -position) + digits
        }
        let head = String(digits.removeFirst())
        let fraction = digits.isEmpty ? "" : "." + digits
        let power = position - 1
        return sign + head + fraction + "e" + (power >= 0 ? "+" : "") + String(power)
    }
}
