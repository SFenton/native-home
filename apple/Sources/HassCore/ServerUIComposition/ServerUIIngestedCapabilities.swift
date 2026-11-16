import Foundation

// MARK: - Ingested capabilities

/// Capabilities the app ships while ingesting the Studio's pending set, one array per lane.
///
/// Each lane appends ids only to its own array, so lanes do not collide in one list. A capability that moves here
/// must also leave `capabilities.pending.json`, move its `pending-*` corpus cases to `accept/`, and be regenerated
/// into `capabilities.json` (`FENTON_REGEN_CAPABILITIES=1 swift test --filter ServerUIContractCorpusTests`).
public enum ServerUIIngestedCapabilities {
    /// Generic grammar: conditions, operands, overlays and tile look (lane L1a).
    public static let grammar: [String] = [
        "sh.conditions@1", "sh.app-state@1", "sh.home-status-counts@1",
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
    /// Flow: pipelines, pipeline operands and app state (lane L4).
    public static let flow: [String] = []

    /// Every ingested capability, in lane order.
    public static var all: [String] { grammar + components + layout + rules + flow }
}
