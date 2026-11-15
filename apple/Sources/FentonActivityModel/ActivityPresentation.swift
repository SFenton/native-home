import Foundation

/// Authored presentation for the existing activity engine, not a source of activity state or actions.
///
/// The containing publication must first pass its bounded, duplicate-key-aware parser. A target
/// delivers this projection only after the native publication transaction accepts it.
public struct ActivityPresentation: Codable, Equatable, Sendable {
    /// Supported glyphs for a job, independent of the engine's control semantics.
    public enum Glyph: String, Codable, Sendable {
        case fan, dishwasher, dryer, washer, vacuum, generic
        case hotFlash = "hot_flash"
    }

    /// Existing activity color families.
    public enum Tint: String, Codable, Sendable {
        case engine, neutral, air, cleaning, water, cooling
    }

    public let id: String
    public let jobId: String
    public let title: String
    public let glyph: Glyph
    public let tint: Tint

    private enum Keys: String, CodingKey, CaseIterable {
        case id, jobId, type, title, glyph, tint, source, privacy, updates, intents
    }
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    /// Rejects unknown properties and policies instead of silently weakening privacy or actions.
    public init(from decoder: any Decoder) throws {
        let all = try decoder.container(keyedBy: AnyKey.self)
        guard Set(all.allKeys.map(\.stringValue)) == Set(Keys.allCases.map(\.rawValue)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid activity presentation fields"))
        }
        let values = try decoder.container(keyedBy: Keys.self)
        func policy(_ key: Keys, _ expected: String) throws {
            guard try values.decode(String.self, forKey: key) == expected else {
                throw DecodingError.dataCorruptedError(forKey: key, in: values, debugDescription: "Unsupported activity policy")
            }
        }
        try policy(.type, "activity-presentation@1")
        try policy(.source, "activity-engine@1")
        try policy(.privacy, "system-sensitive@1")
        try policy(.updates, "engine@1")
        try policy(.intents, "engine-safe@1")
        let id = try values.decode(String.self, forKey: .id)
        let jobId = try values.decode(String.self, forKey: .jobId)
        let title = try values.decode(String.self, forKey: .title)
        guard id.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$"#, options: .regularExpression) == id.startIndex..<id.endIndex,
              !["__proto__", "prototype", "constructor"].contains(id),
              jobId.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$"#, options: .regularExpression) == jobId.startIndex..<jobId.endIndex,
              !["__proto__", "prototype", "constructor"].contains(jobId),
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              title.utf16.count <= HomeActivityAttributes.maxTitleLength else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid activity presentation"))
        }
        self.id = id
        self.jobId = jobId
        self.title = title
        self.glyph = try values.decode(Glyph.self, forKey: .glyph)
        self.tint = try values.decode(Tint.self, forKey: .tint)
    }

    /// Encodes the value to its wire form.
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        try values.encode(id, forKey: .id)
        try values.encode(jobId, forKey: .jobId)
        try values.encode(title, forKey: .title)
        try values.encode(glyph, forKey: .glyph)
        try values.encode(tint, forKey: .tint)
        try values.encode("activity-presentation@1", forKey: .type)
        try values.encode("activity-engine@1", forKey: .source)
        try values.encode("system-sensitive@1", forKey: .privacy)
        try values.encode("engine@1", forKey: .updates)
        try values.encode("engine-safe@1", forKey: .intents)
    }
}
