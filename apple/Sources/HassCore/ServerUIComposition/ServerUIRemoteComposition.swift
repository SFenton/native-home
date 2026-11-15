import Foundation

// MARK: - Media remote atoms

extension ServerUICompositionDocument {
    /// A closed reference to an injected or typed authored canonical remote session.
    public struct Remote: Equatable, Sendable {
        /// The node's common fields.
        public let node: Node
        /// The remote source the control binds to.
        public let sourceId: String
        /// What the control presents.
        public let control: RemoteControl
        /// Copy for loading and failure.
        public let feedback: RemoteFeedback
        /// Whether the control is a device tile rather than a pad.
        public var deviceTile = false
        /// Room personalization of a device tile.
        public var personalization: RoomPersonalization? = nil
        /// The room-card family a device tile belongs to.
        public var deviceFamily: RoomCardKind = .media
    }

    /// Fixed copy for a remote's loading and failure states.
    public struct RemoteFeedback: Equatable, Sendable {
        /// Shown while the source loads.
        public let loadingText: String
        /// Shown when the source fails.
        public let errorText: String
    }

    /// Stable controller slots, not service names or executable expressions.
    public enum RemoteSlot: String, CaseIterable, Sendable {
        case power, up, left, select, right, down, back, home, keyboard, pause, play
        case volumeDown = "volume-down", volumeMute = "volume-mute", volumeUp = "volume-up"
    }

    /// One key of a pad or transport, bound to a controller slot.
    public struct RemoteKey: Equatable, Sendable {
        /// The key's place in its group.
        public let position: Int
        /// The controller slot the key presses.
        public let slot: RemoteSlot
        /// The accessibility label.
        public let label: String
        /// The glyph, or `nil` for none.
        public let icon: Symbol?
        /// The glyph's rotation in degrees.
        public let rotation: Double
        /// Spoken while the control is on.
        public let activeText: String
        /// Spoken while the control is off.
        public let inactiveText: String
    }

    /// How a group of keys is arranged.
    public enum RemoteKeysLayout: String, Sendable { case pad, transport }
    /// The Hue Sync switches.
    public enum RemoteHueToggle: String, Sendable { case power, lightSync = "light-sync" }
    /// The Hue Sync selectors.
    public enum RemoteHueChoice: String, Sendable { case mode, intensity }
    /// Where an app tile's artwork comes from.
    public enum RemoteArtwork: String, Sendable { case none, provider }

    /// One choice of a selector.
    public struct RemoteOption: Equatable, Sendable {
        /// The value sent when chosen.
        public let value: String
        /// The choice's title.
        public let label: String
    }

    /// The transport buttons of a page card.
    public enum RemoteCardSlot: String, Sendable { case power, previous, play, pause, next }
    /// One transport button of a page card.
    public struct RemoteCardAction: Equatable, Sendable {
        /// The button's slot.
        public let slot: RemoteCardSlot
        /// The accessibility label.
        public let label: String
        /// The glyph.
        public let icon: Symbol
    }

    /// Copy for the inline keyboard.
    public struct RemoteKeyboardCopy: Equatable, Sendable {
        /// The field's label.
        public let label: String
        /// The field's placeholder.
        public let placeholder: String
        /// The send button's title.
        public let sendLabel: String
        /// The cancel button's title.
        public let cancelLabel: String
        /// Shown when sending fails.
        public let errorText: String

        /// Creates the keyboard copy.
        public init(label: String, placeholder: String, sendLabel: String, cancelLabel: String, errorText: String) {
            self.label = label
            self.placeholder = placeholder
            self.sendLabel = sendLabel
            self.cancelLabel = cancelLabel
            self.errorText = errorText
        }
    }

    /// Each case is one value/closure presentation, never a page or whole remote feature.
    public enum RemoteControl: Equatable, Sendable {
        case keys(layout: RemoteKeysLayout, label: String, keys: [RemoteKey])
        case volume(keys: [RemoteKey], unavailableText: String, errorText: String)
        case keyboard(RemoteKeyboardCopy)
        case app(key: String, icon: Symbol, artwork: RemoteArtwork, whiteBackground: Bool, activeText: String)
        case device(key: String, icon: Symbol, states: [RemoteOption], fallbackText: String, unavailableText: String)
        case hueToggle(target: RemoteHueToggle, icon: Symbol, onText: String, offText: String, unavailableText: String)
        case hueChoice(target: RemoteHueChoice, options: [RemoteOption], unavailableText: String)
        case hueBrightness(unavailableText: String)
        case hueInput(option: String, icon: Symbol, selectedText: String, connectedText: String,
                      disconnectedText: String, unavailableText: String)
        case card(key: String, icon: Symbol, states: [RemoteOption], fallbackText: String,
                  unavailableText: String, errorText: String, actions: [RemoteCardAction],
                  showsVolume: Bool, volumeLabel: String, action: Action)

        /// Narrow capability closure; future controls do not implicitly negotiate this entire family.
        public var capability: String {
            let name: String
            switch self {
            case .keys: name = "keys"
            case .volume: name = "volume"
            case .keyboard: name = "keyboard"
            case .app: name = "app"
            case .device: name = "device"
            case .hueToggle: name = "hue-toggle"
            case .hueChoice: name = "hue-choice"
            case .hueBrightness: name = "hue-brightness"
            case .hueInput: name = "hue-input"
            case .card: name = "card"
            }
            return "sh.remote-\(name)@1"
        }
    }
}

// MARK: - Strict wire shapes

extension ServerUICompositionShape {
    static let remoteSource: Shape = {
        object(["id": id, "kind": fixed("model"), "model": fixed("media-remote@1"),
                "inputs": object(["providerId": id])])
    }()

    static let remoteFeedback: Shape = {
        object(["loadingText": title, "errorText": title])
    }()

    static let remoteKey: Shape = {
        object([
            "position": .number(0, 8, integer: true),
            "slot": .choice(ServerUICompositionDocument.RemoteSlot.allCases.map(\.rawValue)),
            "label": label,
            "icon": .variant("type", [
                "sf-symbol": symbol,
                "none": object(["type": fixed("none")])
            ]),
            "rotation": .number(-360, 360, integer: false), "activeText": label, "inactiveText": label
        ])
    }()

    static let remoteOptions: Shape = {
        array(object(["value": label, "label": label]), 64)
    }()

    static let remoteNavigation: Shape = {
        .variant("type", [
            "push": push,
            "select-tab": object(["type": fixed("select-tab"), "tabId": id]),
            "present": object(["type": fixed("present"), "modalId": id, "arguments": arguments, "ifPresented": fixed("reject")]),
            "dismiss-then-push": object(["type": fixed("dismiss-then-push"), "destination": push])
        ])
    }()

    static let remoteControl: Shape = {
        func atom(_ kind: String, _ fields: [String: Shape]) -> Shape {
            object(fields.merging(["kind": fixed(kind)], uniquingKeysWith: { _, rhs in rhs }))
        }
        let stateFields: [String: Shape] = [
            "key": label, "icon": symbol, "states": remoteOptions,
            "fallbackText": title, "unavailableText": title
        ]
        return .variant("kind", [
            "keys": atom("keys", ["layout": .choice(["pad", "transport"]), "label": title,
                                   "keys": array(remoteKey, 9, minimum: 1)]),
            "volume": atom("volume", ["keys": array(remoteKey, 3, minimum: 3),
                                       "unavailableText": title, "errorText": title]),
            "keyboard": atom("keyboard", [
                "label": label, "placeholder": label, "sendLabel": label, "cancelLabel": label, "errorText": title
            ]),
            "app": atom("app", ["key": label, "icon": symbol, "artwork": .choice(["none", "provider"]),
                                 "whiteBackground": .bool, "activeText": title]),
            "device": atom("device", stateFields.merging([
                "presentation": .optional(.choice(["row", "tile"])),
                "family": .optional(.choice(["media", "power"])),
                "personalization": .optional(object(["residentId": id, "ownTitle": title, "otherTitle": title]))
            ]) { _, new in new }),
            "hue-toggle": atom("hue-toggle", ["target": .choice(["power", "light-sync"]), "icon": symbol,
                                               "onText": title, "offText": title, "unavailableText": title]),
            "hue-choice": atom("hue-choice", ["target": .choice(["mode", "intensity"]),
                                               "options": remoteOptions, "unavailableText": title]),
            "hue-brightness": atom("hue-brightness", ["unavailableText": title]),
            "hue-input": atom("hue-input", ["option": label, "icon": symbol, "selectedText": title,
                                             "connectedText": title, "disconnectedText": title, "unavailableText": title]),
            "card": atom("card", stateFields.merging([
                "errorText": title, "action": remoteNavigation, "showsVolume": .bool, "volumeLabel": label,
                "actions": array(object(["slot": .choice(["power", "previous", "play", "pause", "next"]),
                                         "label": label, "icon": symbol]), 5)
            ], uniquingKeysWith: { _, rhs in rhs }))
        ])
    }()
}
