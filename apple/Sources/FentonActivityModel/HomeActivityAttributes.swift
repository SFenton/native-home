import Foundation
#if os(iOS)
import ActivityKit
#endif

/// A job's static attributes (`.agents/platforms/apple/live-activities-per-job.md` §3). The Swift type name is the wire
/// `attributes-type` (`HomeActivityAttributes`), and a push-to-start token is per type, so renaming it orphans every
/// token already registered. One activity carries one job (a fan timer, the dishwasher, one vacuum room); its tag is
/// `job.<id>`.
public struct HomeActivityAttributes: Codable, Hashable, Sendable {
    /// The Phase 1 aggregate tag; also the default when a push sends no tag.
    public static let homeTag = "fenton-home"
    /// The prefix of a per-job tag (`job.fan.demo_fan`).
    public static let jobTagPrefix = "job."
    /// The `attributes-type` the relay sends.
    public static let wireName = "HomeActivityAttributes"
    /// An activity lasts 8 hours at most (the system ends it, then keeps it on the Lock Screen for up to 4 more).
    public static let maxLifetime: TimeInterval = 8 * 3600
    /// `title` at most.
    public static let maxTitleLength = 32

    /// `job.<id>`, for example `job.vacuum.main_floor`. It is also the `tag` Home Assistant's `mobile_app` keys the
    /// update token by.
    public var tag: String
    /// The device ("Main Floor Vacuum"). It never changes for the life of the activity.
    public var title: String
    /// `fan`, `dishwasher`, `dryer`, `washer`, `vacuum`, `problem`, `generic` (or Phase 1's `home`).
    public var kind: String
    /// A glyph id from the app's own set (``ActivityGlyph``), not an SF Symbol name.
    public var symbol: String
    /// A `ColorFamily` raw value (`air`, `cleaning`, `water`).
    public var tint: String

    /// Creates attributes.
    public init(tag: String = HomeActivityAttributes.homeTag, title: String = "Home", kind: String = "home",
                symbol: String = "", tint: String = "neutral") {
        self.tag = tag
        self.title = title
        self.kind = kind
        self.symbol = symbol
        self.tint = tint
    }

    /// Attributes decode with defaults so a Phase 1 push that sends only `tag`, `title` and `kind` still starts an activity.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? Self.homeTag
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Home"
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "home"
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? ""
        tint = try container.decodeIfPresent(String.self, forKey: .tint) ?? "neutral"
    }

    private enum CodingKeys: String, CodingKey { case tag, title, kind, symbol, tint }

    /// The device glyph: ``symbol`` when this build knows it, else the one for ``kind``.
    public var glyph: ActivityGlyph { ActivityGlyph(symbol: symbol, kind: kind) }

    /// The job id the engine's control map is keyed by: the tag without `job.` (`fan.demo_fan`).
    public var jobID: String { Self.jobID(forTag: tag) }

    /// The job id for a tag: `job.fan.demo_fan` is `fan.demo_fan`; any other tag is its own id.
    public static func jobID(forTag tag: String) -> String {
        tag.hasPrefix(jobTagPrefix) ? String(tag.dropFirst(jobTagPrefix.count)) : tag
    }

    /// The attributes trimmed to the wire budget (``maxTitleLength``).
    public func fitted() -> HomeActivityAttributes {
        var copy = self
        copy.title = HomeActivityState.truncated(title, to: Self.maxTitleLength)
        return copy
    }
}

#if os(iOS)
extension HomeActivityAttributes: ActivityAttributes {
    public typealias ContentState = HomeActivityState
}
#endif
