import Foundation

/// The `fenton` block of a notification's `userInfo` (contract v1, rule 3).
public struct PushPayload: Equatable, Sendable {
    /// The payload version this app understands.
    public static let version = 1
    /// The `userInfo` key holding the block.
    public static let key = "fenton"
    /// The placeholder category the relay sends; the service extension replaces it with ``PushCategory``.
    public static let dynamicCategory = "fenton.dynamic"

    /// Replaces or clears earlier notifications with the same tag.
    public var tag: String?
    /// Thread grouping (also sent as `aps.thread-id`).
    public var group: String?
    /// What a tap opens.
    public var url: String?
    /// Buttons.
    public var actions: [PushAction]
    /// A camera whose snapshot the extension attaches.
    public var entityID: String?
    /// An image URL, absolute or a Home Assistant path.
    public var image: String?
    /// A video URL.
    public var video: String?
    /// A generic attachment URL.
    public var attachmentURL: String?
    /// A silent command, for background pushes.
    public var command: PushCommand?
    /// The automation's own `data.fenton` block (category, screen, layout); passed through for later versions.
    public var ext: JSONValue?
    /// Other `data` keys the relay did not map, such as `presentation_options`.
    public var extra: JSONValue?

    /// Creates a payload.
    public init(tag: String? = nil, group: String? = nil, url: String? = nil, actions: [PushAction] = [],
                entityID: String? = nil, image: String? = nil, video: String? = nil, attachmentURL: String? = nil,
                command: PushCommand? = nil, ext: JSONValue? = nil, extra: JSONValue? = nil) {
        self.tag = tag
        self.group = group
        self.url = url
        self.actions = actions
        self.entityID = entityID
        self.image = image
        self.video = video
        self.attachmentURL = attachmentURL
        self.command = command
        self.ext = ext
        self.extra = extra
    }

    /// Reads the block from a notification's `userInfo`; nil when there is none or its version is newer than
    /// this app knows.
    /// - Parameter userInfo: `UNNotificationContent.userInfo` or a remote notification dictionary.
    public init?(userInfo: [AnyHashable: Any]) {
        if let raw = userInfo[Self.key] {
            guard var payload = PushPayload(json: JSONValue(any: raw)) else { return nil }
            if payload.command == nil { payload.command = Self.officialCommand(in: userInfo) }
            self = payload
        } else if let command = Self.officialCommand(in: userInfo) {
            self.init(command: command)
        } else {
            return nil
        }
    }

    /// The command in the official Home Assistant app's block, `userInfo["homeassistant"]["command"]`, which a push
    /// built for the companion app (or a relay that forwards it as is) carries instead of the `fenton` block.
    static func officialCommand(in userInfo: [AnyHashable: Any]) -> PushCommand? {
        guard let raw = userInfo["homeassistant"] else { return nil }
        let block = JSONValue(any: raw)
        guard case .object = block, let name = block["command"]?.string, !name.isEmpty else { return nil }
        return command(named: name, tag: block["tag"]?.string.flatMap { $0.isEmpty ? nil : $0 })
    }

    private static func command(named name: String, tag: String?) -> PushCommand {
        switch name {
        case "clear_notification": tag.map { .clearNotification(tag: $0) } ?? .unsupported(name)
        case PushCommand.requestLocationUpdateName: .requestLocationUpdate
        default: .unsupported(name)
        }
    }

    /// Reads the block from JSON.
    public init?(json: JSONValue) {
        guard case .object = json else { return nil }
        if let version = json["v"]?.number, Int(version) > Self.version { return nil }
        let text = { (key: String) in json[key]?.string.flatMap { $0.isEmpty ? nil : $0 } }
        let tag = text("tag")
        let command = text("command").map { Self.command(named: $0, tag: tag) }
        self.init(
            tag: tag,
            group: text("group"),
            url: text("url"),
            actions: json["actions"]?.array?.compactMap(PushAction.init(json:)) ?? [],
            entityID: text("entity_id"),
            image: text("image"),
            video: text("video"),
            attachmentURL: json["attachment"]?["url"]?.string,
            command: command,
            ext: json["ext"],
            extra: json["extra"]
        )
    }

    /// The action with an id, if the notification has it.
    public func action(_ id: String) -> PushAction? { actions.first { $0.action == id } }
}
