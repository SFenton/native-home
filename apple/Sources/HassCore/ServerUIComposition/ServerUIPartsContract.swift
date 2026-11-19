import Foundation

// MARK: - Choice options read from an entity (`sh.bound-options-read@1`)

/// The options of a bound choice that come from an entity's list attribute instead of the document's own list.
///
/// The authored `options` stay in the document as the fallback: while the list is missing, still loading, not a list, or holds fewer
/// than two usable items, the choice draws them, never an empty control. Under this read, `control` in ``action`` stands for the chosen
/// item as the entity holds it.
public struct ServerUIOptionsRead: Equatable, Sendable {
    /// How an item becomes the words drawn for it.
    public enum Labels: String, Sendable {
        /// The item as the entity holds it.
        case asIs = "as-is"
        /// `armed_away` is `Armed Away` (``ServerUITextCase``).
        case titleCase = "title-case"
    }

    /// One option read from the list: the item as held, and the words drawn for it.
    public struct Option: Equatable, Sendable {
        public let value: String
        public let label: String

        /// Creates an option.
        public init(value: String, label: String) {
            self.value = value
            self.label = label
        }
    }

    /// The `ha-entity` source the list is read from.
    public let sourceId: String
    /// The list's path on that source: `["attributes", name]`.
    public let path: [String]
    /// The value the entity holds now: the option equal to it is the chosen one.
    public let current: ServerUIOperand
    public let labels: Labels
    /// What choosing an option does; `control` is the chosen item.
    public let action: ServerUICallService

    /// The most options a choice offers, authored or read.
    public static let maximumOptions = 12

    /// Creates a read.
    public init(sourceId: String, path: [String], current: ServerUIOperand, labels: Labels, action: ServerUICallService) {
        self.sourceId = sourceId
        self.path = path
        self.current = current
        self.labels = labels
        self.action = action
    }

    /// The options a list gives: its text items that are not blank, each once and in the list's order, at most
    /// ``maximumOptions``. Anything else in the list is left out. `nil` when fewer than two remain: the authored options stand.
    public static func options(from items: [JSONValue], labels: Labels) -> [Option]? {
        var seen: Set<String> = []
        var options: [Option] = []
        for item in items {
            guard case .string(let text) = item, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(text).inserted else { continue }
            options.append(Option(value: text, label: labels == .titleCase ? ServerUITextCase.title.apply(to: text) : text))
            if options.count == maximumOptions { break }
        }
        return options.count >= 2 ? options : nil
    }

    /// The options the entity's list gives now, or `nil` to use the authored ones (no list, still loading, or fewer than two usable items).
    public func options(in environment: some ServerUIReading) -> [Option]? {
        guard case .value(.array(let items)) = environment.read(sourceId: sourceId, path: path) else { return nil }
        return Self.options(from: items, labels: labels)
    }

    /// The value the entity holds now (text), or `nil` while it cannot be read.
    public func currentValue(in environment: some ServerUIReading) -> String? {
        guard case .value(.string(let text)) = current.evaluate(environment) else { return nil }
        return text
    }

    /// The source ids the options and the chosen one depend on.
    public var sourceIds: Set<String> { current.sourceIds.union([sourceId]) }
}

// MARK: - A toggle row's own parts (`sh.bound-row-parts@1`, `sh.check-face@1`)

/// The parts of a bound toggle drawn as a row, each optional: a leading glyph tint, a line under the title, a hint, the row's metrics
/// and a caption for a failed call; and its face, a switch or a check mark.
///
/// A check face keeps only the hint, the failure caption and its tint: it has no icon, subtitle, glyph or metrics of its own.
public struct ServerUIRowParts: Equatable, Sendable {
    /// The row's size: ``UKRowStyle/module`` (16 pt side padding, 52 pt high, 60 with a subtitle) or ``UKRowStyle/form`` (44 pt minimum).
    public enum Metrics: String, Sendable { case form, module }
    /// What the row draws at its trailing (or, for a check, leading) edge.
    public enum Face: String, Sendable { case `switch`, check }
    /// The checked colour of a check face: the action blue, or the success green.
    public enum CheckTint: String, Sendable { case action, success }

    /// The line under the title.
    public var subtitle: ServerUICompositionDocument.StringValue?
    /// What VoiceOver reads after the label; the unavailable text replaces it while the row cannot be changed.
    public var hint: String?
    /// Unset keeps the native default of the surface.
    public var metrics: Metrics?
    /// Said under the row after a call that failed.
    public var failureText: String?
    /// The tint of the leading glyph (the node's `icon`): its own value, or the `otherwise` of its rule.
    public var glyph: ServerUICompositionDocument.TileFill?
    /// How the glyph follows a rule or an entity's color.
    public var glyphRule: ServerUIDynamicLook<ServerUICompositionDocument.TileFill>?
    public var face: Face = .switch
    /// Only with a check face; unset draws the success green.
    public var checkTint: CheckTint?

    /// Creates the parts, none set.
    public init() {}

    /// Whether the row draws a check mark instead of a switch.
    public var isCheck: Bool { face == .check }

    /// Whether any part is authored: a toggle with none is the plain switch row it always was.
    public var isAuthored: Bool {
        subtitle != nil || hint != nil || metrics != nil || failureText != nil || glyph != nil || face != .switch || checkTint != nil
    }

    /// Whether the node's `icon` is drawn in the row's glyph column: only with an authored glyph, so a toggle that carries an icon and
    /// no glyph keeps the row it always drew.
    public var drawsIcon: Bool { glyph != nil }

    /// The tint of the glyph now; `previous` is what it showed, kept while a bound color is loading.
    public func resolvedGlyph(in environment: some ServerUIReading, keeping previous: ServerUICompositionDocument.TileFill? = nil)
        -> ServerUICompositionDocument.TileFill? {
        guard let glyph else { return nil }
        guard let glyphRule else { return glyph }
        switch glyphRule.resolve(base: glyph, role: .glyph, in: environment) {
        case .value(let value): return value
        case .loading: return previous ?? glyph
        }
    }

    /// The source ids the parts read.
    public var sourceIds: Set<String> {
        var ids = glyphRule?.sourceIds ?? []
        if let subtitle { ids.formUnion(ServerUIStringResolver.sourceIds(subtitle)) }
        return ids
    }
}

// MARK: - A tile button that follows a rule (`sh.tile-disc-rules@1`)

extension ServerUITileParts.Disc {
    /// The symbol to draw now. A rule still loading keeps what `previous` showed, and its own `otherwise` when nothing was shown.
    public func resolvedIcon(in environment: some ServerUIReading, keeping previous: ServerUICompositionDocument.Symbol? = nil)
        -> ServerUICompositionDocument.Symbol {
        guard let iconRule else { return icon }
        switch iconRule.resolve(base: icon, in: environment) {
        case .value(let value): return value
        case .loading: return previous ?? icon
        }
    }

    /// The words VoiceOver reads for the button now: the plain label, or the text slot's answer. A slot that is loading keeps what
    /// `previous` said, and one that is unavailable says the authored label.
    public func resolvedLabel(read: (ServerUICompositionDocument.Read) -> ServerUIReadResult, in environment: some ServerUIReading,
                              keeping previous: String? = nil) -> String {
        var memory = ServerUITextMemory()
        return resolvedLabel(read: read, in: environment, keeping: previous, memory: &memory)
    }

    /// As ``resolvedLabel(read:in:keeping:)``, with this button's `memory` of the text its label slot last answered, so a `keep` slot
    /// (`sh.text-keep@1`) says that text while its value is unavailable.
    public func resolvedLabel(read: (ServerUICompositionDocument.Read) -> ServerUIReadResult, in environment: some ServerUIReading,
                              keeping previous: String?, memory: inout ServerUITextMemory) -> String {
        guard let labelValue else { return label }
        switch ServerUIStringResolver.resolve(labelValue, read: read, in: environment, memory: &memory) {
        case .value(.string(let text)) where !text.trimmingCharacters(in: .whitespaces).isEmpty: return text
        case .loading: return previous ?? label
        default: return label
        }
    }

    /// The source ids the button's rules read.
    public var ruleSourceIds: Set<String> {
        var ids = iconRule?.sourceIds ?? []
        if let labelValue { ids.formUnion(ServerUIStringResolver.sourceIds(labelValue)) }
        return ids
    }
}
