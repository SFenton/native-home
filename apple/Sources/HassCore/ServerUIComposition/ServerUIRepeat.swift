import Foundation

// MARK: - Repeat (`sh.repeat@1`)

/// A list drawn from a flow: one copy of its first child for every record the `records` flow ``providerId`` gives, up to ``limit``
/// (`sh.repeat@1`).
///
/// Inside that child `item` reads a field of the record and `index` its position, checked against the flow's `schema` when the document
/// compiles. The optional second child is drawn ``placeholderCount`` times while the flow has not answered; it has no record, so only `index`
/// is allowed in it. The five ``Words`` say what shows with no list. The draw is in the app (`UKRepeatView`); this type is what the document says.
public struct ServerUIRepeat: Equatable, Sendable {
    /// The direction the cells run.
    public enum Axis: String, CaseIterable, Sendable { case horizontal, vertical }

    /// Whether previous and next buttons show on a horizontal paged repeat.
    public enum Buttons: String, CaseIterable, Sendable {
        case never
        /// Only in a window of regular width (an iPad or a wide landscape window).
        case regularWidth = "regular-width"
    }

    /// How a horizontal repeat is cut into pages: how many cells a page holds in a compact and in a regular-width window (at most 12), the factor
    /// the count is scaled by at each of four text sizes, down to ``minimum`` cells, whether a page indicator and previous and next buttons show,
    /// and the name VoiceOver gives the pager.
    public struct Paging: Equatable, Sendable {
        /// The cells a page holds in a compact and in a regular-width window.
        /// The cells a page holds in a compact window.
        public var compact: Int
        /// The cells a page holds in a regular-width window.
        public var regular: Int
        /// The factor of the count at the default, large, extra large and accessibility text sizes, each no larger than the one before.
        public var scaleByTextSize: [Double]?
        /// The fewest cells a page may shrink to; one when absent.
        public var minimum: Int?
        /// Whether the page indicator shows.
        public var indicator: Bool
        /// Whether previous and next buttons show.
        public var buttons: Buttons
        /// The name VoiceOver gives the pager; the node's title when absent.
        public var label: String?

        /// Creates a paging.
        public init(compact: Int, regular: Int, scaleByTextSize: [Double]? = nil, minimum: Int? = nil, indicator: Bool = false,
                    buttons: Buttons = .never, label: String? = nil) {
            self.compact = compact
            self.regular = regular
            self.scaleByTextSize = scaleByTextSize
            self.minimum = minimum
            self.indicator = indicator
            self.buttons = buttons
            self.label = label
        }

        /// How many cells one page holds: the compact or regular count, times the factor of the text size, rounded down, never below
        /// ``minimum`` (one when absent) and never above the count itself.
        ///
        /// - Parameters:
        ///   - isRegular: Whether the window is regular width.
        ///   - textStep: The text size's step, 0 to 3 (``ServerUIRepeat/textStep(scale:)``).
        public func pageSize(isRegular: Bool, textStep: Int) -> Int {
            let base = isRegular ? regular : compact
            let factor = scaleByTextSize.flatMap { $0.indices.contains(textStep) ? $0[textStep] : nil } ?? 1
            let scaled = Int((Double(base) * factor + 1e-9).rounded(.down))
            return max(minimum ?? 1, min(base, scaled))
        }
    }

    /// The five words that say what shows with no list: loading, nothing in it, no data, a failed first load, and a kept list that is out of date.
    public struct Words: Equatable, Sendable {
        /// What shows while the flow has not answered and there is no placeholder, and under the placeholders.
        public var loading: String
        /// What shows when the flow answered with no records.
        public var empty: String
        /// What shows when the flow has no data to give (its source is gone).
        public var unavailable: String
        /// What shows when the first run failed.
        public var error: String
        /// The footnote under a kept list that is out of date.
        public var stale: String

        /// Creates the words.
        public init(loading: String, empty: String, unavailable: String, error: String, stale: String) {
            self.loading = loading
            self.empty = empty
            self.unavailable = unavailable
            self.error = error
            self.stale = stale
        }
    }

    /// The most cells a repeat draws, and the most a placeholder draws.
    public static let maximumCells = 100, maximumPlaceholders = 24

    /// The node's id, title and layout.
    public let node: ServerUICompositionDocument.Node
    /// The records flow it draws (a `pipeline@1` source whose output is `records`).
    public var providerId: String
    /// The direction the cells run.
    public var axis: Axis
    /// The points between cells.
    public var spacing: ServerUICompositionDocument.Space
    /// The most cells drawn, from 1 to 100.
    public var limit: Int
    /// How a horizontal repeat is cut into pages, or `nil` for a plain row.
    public var paging: Paging?
    /// How many copies of the placeholder draw while the flow has not answered, or `nil` for none.
    public var placeholderCount: Int?
    /// The words for loading, empty, unavailable, failed and stale.
    public var words: Words
    /// The template (the first child) and, when ``placeholderCount`` is set, the placeholder (the second).
    public var children: [ServerUICompositionDocument.Component]

    /// The component drawn once for each record.
    public var template: ServerUICompositionDocument.Component? { children.first }
    /// The component drawn in place of a record while the flow has not answered.
    public var placeholder: ServerUICompositionDocument.Component? { children.count > 1 ? children[1] : nil }

    /// Creates a repeat.
    public init(node: ServerUICompositionDocument.Node, providerId: String, axis: Axis, spacing: ServerUICompositionDocument.Space, limit: Int = maximumCells,
                paging: Paging? = nil, placeholderCount: Int? = nil, words: Words, children: [ServerUICompositionDocument.Component]) {
        self.node = node
        self.providerId = providerId
        self.axis = axis
        self.spacing = spacing
        self.limit = limit
        self.paging = paging
        self.placeholderCount = placeholderCount
        self.words = words
        self.children = children
    }

    /// The text size's step, 0 to 3, from how much larger than the default the body text is drawn (`scale` 1 is the default size): the app's
    /// default, then large, extra large and the accessibility sizes. It is the step the Studio's preview takes from its own scale.
    public static func textStep(scale: Double) -> Int { scale < 1.1 ? 0 : scale < 1.25 ? 1 : scale < 1.4 ? 2 : 3 }
}

// MARK: - Keyed updates

/// What changed between two answers of a records flow, with a cell keyed by its position: the cells whose record differs, the cells that are new
/// and the cells that are gone. A change to one record is one entry in ``changed``, so one cell updates in place and the rest are not touched.
public struct ServerUIRepeatDiff: Equatable, Sendable {
    /// The positions that held a record before and hold a different one now.
    public let changed: [Int]
    /// The positions that are new.
    public let added: Range<Int>
    /// The positions that are gone.
    public let removed: Range<Int>

    /// Whether nothing changed.
    public var isEmpty: Bool { changed.isEmpty && added.isEmpty && removed.isEmpty }

    /// The difference from `old` to `new`, both cut to `limit` cells first (the cells a repeat draws).
    public static func between(_ old: [JSONValue], _ new: [JSONValue], limit: Int = ServerUIRepeat.maximumCells) -> Self {
        let before = old.prefix(limit), after = new.prefix(limit)
        let shared = min(before.count, after.count)
        let changed = (0..<shared).filter { before[$0] != after[$0] }
        return Self(changed: changed, added: shared..<max(shared, after.count), removed: shared..<max(shared, before.count))
    }
}

// MARK: - What a repeat draws

/// What a repeat draws for where its flow stands: its template for each record, its placeholder while the flow has not answered, or one of
/// the five words. It is the Studio's choice case by case (`RepeatBody`), so the page and the Studio agree on what shows.
public struct ServerUIRepeatPlan: Equatable, Sendable {
    /// What fills the repeat.
    public enum Body: Equatable, Sendable {
        /// The template, once for each of this many records.
        case cells(Int)
        /// The placeholder, this many times, with the loading word under it.
        case placeholders(Int)
        /// A word alone: nothing to draw.
        case word(Word)
    }

    /// The words that stand where a list would be.
    public enum Word: String, Equatable, Sendable { case loading, empty, unavailable, error }

    /// What fills the repeat.
    public let body: Body
    /// Whether the kept list is out of date (the flow failed or lost its source after it answered), so the stale footnote shows under it.
    public let isStale: Bool

    /// Chooses what to draw.
    ///
    /// - Parameters:
    ///   - phase: Where the records flow stands; `nil` when the document names no collection for it (drawn as loading).
    ///   - recordCount: How many records it last gave.
    ///   - limit: The repeat's limit.
    ///   - placeholderCount: How many placeholders draw while loading, or `nil` for none.
    public static func make(phase: ServerUIRowCollection.Phase?, recordCount: Int, limit: Int, placeholderCount: Int?) -> Self {
        let shown = min(recordCount, max(0, limit))
        if shown > 0 { return Self(body: .cells(shown), isStale: phase == .stale || phase == .failed || phase == .unavailable) }
        switch phase {
        case .ready, .stale: return Self(body: .word(.empty), isStale: false)
        case .failed: return Self(body: .word(.error), isStale: false)
        case .unavailable: return Self(body: .word(.unavailable), isStale: false)
        case .loading, nil:
            if let count = placeholderCount, count > 0 {
                return Self(body: .placeholders(min(count, ServerUIRepeat.maximumPlaceholders)), isStale: false)
            }
            return Self(body: .word(.loading), isStale: false)
        }
    }

    /// The document's words for a state.
    public func text(_ word: Word, in words: ServerUIRepeat.Words) -> String {
        switch word {
        case .loading: words.loading
        case .empty: words.empty
        case .unavailable: words.unavailable
        case .error: words.error
        }
    }
}
