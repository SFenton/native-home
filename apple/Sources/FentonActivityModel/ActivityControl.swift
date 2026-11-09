import Foundation

/// One button on a card (`controls` on the wire). At most ``HomeActivityState/maxControls`` ride along (three on a
/// problem card, whose last button is Done).
public struct ActivityControl: Codable, Hashable, Sendable, Identifiable {
    /// How the button is drawn.
    public enum Role: String, Codable, Hashable, Sendable {
        /// A white pill.
        case primary
        /// A dark pill.
        case secondary

        /// An unknown role (including Phase 1's `normal` and `destructive`) reads as ``secondary``.
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Role(rawValue: raw) ?? .secondary
        }
    }

    /// The control ids a Lock Screen button may run without unlocking: the job verbs, which only start, stop or
    /// park a task. Any other id (a lock or door control, say) is refused there and must be run in the app.
    public static let lockScreenSafeIDs: Set<String> = [
        "stop", "cancel", "cancel_timer", "pause", "resume", "dock", "done", "try_again"
    ]

    /// Whether `id` may run from the Lock Screen without authentication.
    public static func isSafeFromLockScreen(_ id: String) -> Bool { lockScreenSafeIDs.contains(id) }

    /// The control's id, which the engine maps to a service (`stop`, `pause`, `resume`, `dock`, `done`).
    public var id: String
    /// The label.
    public var title: String
    /// The role the engine asked for. The first control is always drawn primary (``ActivityCard/Button``).
    public var role: Role

    /// Creates a control.
    public init(id: String, title: String, role: Role = .secondary) {
        self.id = id
        self.title = title
        self.role = role
    }

    private enum CodingKeys: String, CodingKey { case id, title, role }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        role = try container.decodeIfPresent(Role.self, forKey: .role) ?? .secondary
    }
}
