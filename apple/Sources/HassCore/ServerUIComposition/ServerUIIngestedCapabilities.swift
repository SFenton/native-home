import Foundation

// MARK: - Ingested capabilities

/// Capabilities the app ships while ingesting the Studio's pending set, one array per lane.
///
/// Each lane appends ids only to its own array, so lanes do not collide in one list. A capability that moves here
/// must also leave `capabilities.pending.json`, move its `pending-*` corpus cases to `accept/`, and be regenerated
/// into `capabilities.json` (`FENTON_REGEN_CAPABILITIES=1 swift test --filter ServerUIContractCorpusTests`).
public enum ServerUIIngestedCapabilities {
    /// Generic grammar: conditions, operands, overlays and tile look (lane L1a), then list reads and the raw state (lane `ni-grammar2`),
    /// then the five generic parts (lane `ni-parts`): options read from an entity, tile button rules, a grid's least columns, a toggle
    /// row's parts and the check face.
    ///
    /// `sh.pipeline-operands@1` is listed with the flow lane (``flow``): the fixed-digit and title-case formats of `ni-grammar2` need it.
    public static let grammar: [String] = [
        "sh.conditions@1", "sh.app-state@1", "sh.home-status-counts@1", "sh.list-read@1", "sh.raw-state@1",
        "sh.bound-options-read@1", "sh.tile-disc-rules@1", "sh.grid-min-columns@1", "sh.bound-row-parts@1", "sh.check-face@1",
    ]
    /// Components: tab bar, badges, list and tile parts (lane L2).
    public static let components: [String] = ["sh.component-ref@1"]
    /// Layout: tab blocks, fallbacks and status counts (lane L3).
    public static let layout: [String] = [
        "sh.tab-blocks@1", "sh.tab-bar@1", "sh.tab-fallback@1", "sh.overlay@1", "sh.tile-parts@1", "sh.tile-look@1", "sh.badges@1"
    ]
    /// Rules: action rules, confirm and enabled conditions (lane L1b).
    public static let rules: [String] = [
        "sh.rules@1", "sh.enabled-when@1", "sh.confirm-when@1", "sh.action-rules@1",
    ]
    /// Flow: pipelines, the operands only a flow has, and the parts of a list a flow feeds (lane L4).
    public static let flow: [String] = ["sh.pipeline@1", "sh.pipeline-operands@1", "sh.list-parts@1"]

    /// The words text case and the light and dark colour pair (lane `ni-tc4`).
    ///
    /// `words` needs only `sh.text-case-words@1`, so it decodes whether or not `sh.pipeline-operands@1` is listed; a `words` format inside a
    /// flow also needs this id, which the flow lane keeps when it takes the flow.
    public static let appearance: [String] = ["sh.text-case-words@1", "sh.solid-appearance@1"]

    /// Per-state fills and hidden words on state styles (lane L5a).
    public static let styleFills: [String] = ["sh.state-style-fills@1"]

    /// A state tile's icon and button icon colours, its fit in a taller cell, and the ink of a state line on a fill (lane `ni-tc5`).
    public static let tileInk: [String] = ["sh.tile-ink@1"]

    /// A picture's orientation and the corner button groups on it (lane `ni-mapctl`): a flip, then up to four groups of 44 pt buttons.
    public static let surface: [String] = ["sh.surface-orientation@1", "sh.surface-controls@1"]

    /// The style parts (lane `ni-wgstyle`): a text's font, ink, lines, alignment and ticker with the `rgba` colour, the `stack` and `shape` nodes, the
    /// `symbol` node, and a symbol and a hint on the options of a segmented choice.
    public static let styleParts: [String] = ["sh.text-style@1", "sh.stack@1", "sh.symbol-part@1", "sh.choice-icons@1"]

    /// The repeat and the flow extras (lane `ni-wgflow`): a flow that gives records and the `repeat` node that draws one cell for each, with `item` and
    /// `index`; the steps `min`, `max`, `running-sum` and `annotate`, the date styles `hour` and `weekday`, and the `progress` operation of a `date` operand.
    public static let flowRepeat: [String] = ["sh.repeat@1", "sh.flow-extras@1"]

    /// The chart and the linear gauge (lane `ni-wgchart`): one series as bars, a line or an area on an axis, from points written in the document or from the
    /// records of a flow or a `repeat`; and a rail with a gradient, a span and a marker.
    public static let dataParts: [String] = ["sh.chart@1", "sh.linear-gauge@1"]

    /// Swipe to adjust, the words a tile says for its states, the default tile ink and a grid grouped by state (lane `ni-tilecontract`).
    public static let tileContract: [String] = ["sh.tile-swipe@1", "sh.state-words@1", ServerUITileInkDefault.capability, "sh.grid-state-groups@1"]

    /// Every ingested capability, in lane order.
    public static var all: [String] { grammar + components + layout + rules + flow + styleFills + appearance + tileInk + surface + styleParts + tileContract + flowRepeat + dataParts }
}
