import Foundation

// MARK: - Service call shapes

/// The shape rules for the Home Assistant services a published device provider names.
///
/// Each authored command sits in a ``Slot``. Any domain, service or script may be named; only the call's shape is checked
/// (see ``allows(_:in:)``).
enum ServerUIServiceVocabulary {
    /// Where in a remote an authored command appears.
    enum Slot: String, Sendable, CaseIterable {
        /// A pad button: direction, playback, volume, power or keyboard.
        case remoteButton
        /// An app launch tile.
        case remoteApp
        /// A device tile on the Devices tab, or a page card.
        case remoteDevice
    }

    /// Whether `call` has a well-formed shape for its slot.
    ///
    /// Any domain and service the document names is allowed (the owner's full-control decision supersedes the earlier closed
    /// list and the house-script membership check). Only the shape is checked: a target must belong to the domain being called,
    /// so a media_player call cannot address a lock, and a `script` call carries no target (HA runs a script by its name).
    ///
    /// - Parameters:
    ///   - call: The authored service call.
    ///   - slot: The slot that holds it.
    static func allows(_ call: ServiceCall, in slot: Slot) -> Bool {
        if call.domain == "script" { return call.target == nil }
        return call.target.map { $0.hasPrefix(call.domain + ".") } ?? true
    }

    /// One authored command group of a remote: the slot it occupies, where it sits for error pointers, and its calls.
    struct SlotCalls {
        let slot: Slot
        let field: String
        let calls: [ServiceCall]
    }

    /// Every authored call of `config`, with the slot it occupies.
    static func slotCalls(_ config: MediaRemoteConfig) -> [SlotCalls] {
        var result: [SlotCalls] = []
        let buttons: [(String, MediaRemoteButton?)] = [
            ("power", config.power), ("up", config.up), ("left", config.left), ("select", config.select),
            ("right", config.right), ("down", config.down), ("back", config.back), ("home", config.home),
            ("keyboard", config.keyboard), ("pause", config.pause), ("play", config.play),
            ("volumeDown", config.volumeDown), ("volumeMute", config.volumeMute), ("volumeUp", config.volumeUp)
        ]
        for (name, button) in buttons {
            if let button { result.append(SlotCalls(slot: .remoteButton, field: name, calls: calls(button.action))) }
        }
        for (index, app) in config.apps.enumerated() {
            result.append(SlotCalls(slot: .remoteApp, field: "apps/\(index)", calls: calls(app.action)))
        }
        for (index, device) in config.devices.enumerated() {
            if let action = device.action { result.append(SlotCalls(slot: .remoteDevice, field: "devices/\(index)", calls: calls(action))) }
        }
        return result
    }

    /// Every service call an action can make.
    static func calls(_ action: MediaRemoteAction) -> [ServiceCall] {
        func call(_ command: MediaRemoteCommand) -> [ServiceCall] {
            if case let .service(call, _) = command { [call] } else { [] }
        }
        switch action {
        case .command(let command): return call(command)
        case let .state(_, cases, otherwise): return cases.flatMap { call($0.command) } + call(otherwise)
        }
    }
}
