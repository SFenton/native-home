import Foundation

// MARK: - State words (`sh.state-words@1`)

/// The words a tile says for its states (`sh.state-words@1`). An absent key draws the app's word, production's, so a document without `words` is
/// byte-identical and draws production's text (`.agents/design/mockups/proposals/sim-fidelity-contract`, section 2).
public struct ServerUIStateWords: Equatable, Sendable {
    /// A word key.
    public enum Key: String, Sendable, CaseIterable {
        case on, off, unavailable, count, level
        /// The token the word must hold: `count` holds `{count}`, `level` holds `{value}`, the rest none.
        var requiredToken: String? { self == .count ? "{count}" : self == .level ? "{value}" : nil }
    }

    /// "On": a light group tile that does not dim, a room with one light, an occupancy that is occupied.
    public var on: String?
    /// "Off": a light that is off, a room with no lights on, an occupancy that is clear.
    public var off: String?
    /// "Unavailable".
    public var unavailable: String?
    /// "{count} On": a room with more than one light, with `{count}` for the number on.
    public var count: String?
    /// "{value}%": a light's level, with `{value}` for the percentage.
    public var level: String?

    /// Creates words; an absent one draws production's.
    public init(on: String? = nil, off: String? = nil, unavailable: String? = nil, count: String? = nil, level: String? = nil) {
        self.on = on
        self.off = off
        self.unavailable = unavailable
        self.count = count
        self.level = level
    }

    /// The keys each tile can draw; a key it cannot draw is refused, so no document holds a dead word.
    public static let lightGroupKeys: Set<Key> = [.on, .off, .unavailable, .level]
    /// The keys a brightness light control draws.
    public static let brightnessKeys: Set<Key> = [.off, .unavailable, .level]
    /// The keys a room overview draws for a `home-status@1` projection: lights say `on` for one light and `count` for more.
    public static func overviewKeys(projection: String) -> Set<Key> {
        switch projection {
        case "lights": [.on, .off, .unavailable, .count]
        case "occupancy": [.on, .off, .unavailable]
        default: [.unavailable]
        }
    }

    /// The word for `key`, if authored.
    public subscript(key: Key) -> String? {
        switch key {
        case .on: on
        case .off: off
        case .unavailable: unavailable
        case .count: count
        case .level: level
        }
    }

    /// The `{...}` tokens in `word`, in order.
    static func tokens(in word: String) -> [String] {
        var found: [String] = []
        var index = word.startIndex
        while let open = word[index...].firstIndex(of: "{"), let close = word[open...].firstIndex(of: "}") {
            found.append(String(word[open...close]))
            index = word.index(after: close)
        }
        return found
    }

    /// One problem as a key to refuse and why.
    struct Problem: Equatable {
        let code: ServerUICompositionError.Code
        let key: Key
    }

    /// The checks of a words object for a tile that takes `allowed`: each key is one the tile draws, holds its token (`count` and `level`) and no other.
    func problems(allowed: Set<Key>) -> [Problem] {
        var found: [Problem] = []
        for key in Key.allCases {
            guard let word = self[key] else { continue }
            guard allowed.contains(key) else { found.append(.init(code: .invalidCombination, key: key)); continue }
            let present = Self.tokens(in: word)
            if let need = key.requiredToken {
                if !present.contains(need) || present.contains(where: { $0 != need }) { found.append(.init(code: .invalidValue, key: key)); continue }
            } else if !present.isEmpty { found.append(.init(code: .invalidValue, key: key)); continue }
            let rest = word.replacingOccurrences(of: key.requiredToken ?? "\u{0}", with: "")
            if rest.contains(where: { $0 == "{" || $0 == "}" }) { found.append(.init(code: .invalidValue, key: key)) }
        }
        return found
    }

    /// `level` with `{value}` replaced by `percent`, or production's "45%" when no word is authored.
    public func levelText(percent: Int) -> String {
        (level ?? "{value}%").replacingOccurrences(of: "{value}", with: String(percent))
    }

    /// `count` with `{count}` replaced by `number`, or production's "3 On" when no word is authored.
    public func countText(_ number: Int) -> String {
        (count ?? "{count} On").replacingOccurrences(of: "{count}", with: String(number))
    }
}
