import Foundation

/// The roles the app reads from the document's role-keyed maps.
///
/// A role-keyed map (`media.sourceSelect.entityIds`, `.sources`, `.revertSeconds`) is a dictionary in the document, so
/// a server file could omit a role the app later looks up with a force-unwrap or a silent default. ``HouseConfig/decode(_:)``
/// calls ``HouseConfig/validateRoles()`` so a document that lacks one is refused at the door, naming the role (never a value).
public extension HouseConfig.SourceSelectRemote {
    /// Roles `entityIds` must carry.
    static let requiredEntityRoles: Set<String> = [
        "control", "console", "remote", "volume", "mediaSource", "activeMediaSource", "consoleHdmiStatus",
        "syncPower", "syncLightSync", "syncBrightness", "syncHdmiInput", "syncMode", "syncIntensity",
    ]
    /// Roles `sources` must carry.
    static let requiredSourceRoles: Set<String> = ["launcher", "off", "server", "tv", "pc", "console"]
    /// Roles `revertSeconds` must carry.
    static let requiredRevertRoles: Set<String> = ["launcher", "server", "tv", "pc", "console", "consoleOff", "sync"]
}

public extension HouseConfig.SecuritySection {
    /// Roles `garageDoors` must carry.
    static let requiredGarageDoorRoles: Set<String> = ["left", "right"]
}

extension HouseConfig {
    /// Throws ``DecodeError/malformed(_:)`` naming each role-keyed map that lacks a role the app reads.
    func validateRoles() throws {
        let select = media.sourceSelect
        let checks: [(name: String, have: Set<String>, need: Set<String>)] = [
            ("media.sourceSelect.entityIds", Set(select.entityIds.keys), SourceSelectRemote.requiredEntityRoles),
            ("media.sourceSelect.sources", Set(select.sources.keys), SourceSelectRemote.requiredSourceRoles),
            ("media.sourceSelect.revertSeconds", Set(select.revertSeconds.keys), SourceSelectRemote.requiredRevertRoles),
            ("security.garageDoors", Set(security.garageDoors.keys), SecuritySection.requiredGarageDoorRoles),
        ]
        let missing = checks.compactMap { check -> String? in
            let absent = check.need.subtracting(check.have)
            return absent.isEmpty ? nil : "\(check.name) lacks \(absent.sorted().joined(separator: ", "))"
        }
        guard missing.isEmpty else { throw DecodeError.malformed(missing.joined(separator: "; ")) }
    }
}
