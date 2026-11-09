import Foundation

/// A Home Assistant websocket command sender; ``HassConnection`` is the app's, tests use a stub.
@MainActor
public protocol HassCommandSending: AnyObject {
    /// Sends one websocket command once and returns its result.
    func command(_ type: String, data: [String: any Sendable]) async throws -> JSONValue
}

/// What linking this phone's tracker to the signed-in user's person did (`.agents/platforms/apple/location.md`,
/// Presence link).
public enum PresenceLinkOutcome: Equatable, Sendable {
    /// The tracker was added to the person.
    case linked(person: String)
    /// The person already tracked it; nothing changed.
    case alreadyLinked(person: String)
    /// The person already tracks a composite tracker (the S+H Home Integration's presence feature, 1.2, feeds it this
    /// phone), so adding the phone's own tracker would only be undone seconds later and make the person briefly follow
    /// the phone alone.
    case compositeManaged(person: String)
    /// Home Assistant only lets administrators edit people and the entity registry.
    case needsAdmin
    /// No editable person has this user; an administrator must create one (people from YAML can't be edited).
    case noPerson
    /// Home Assistant has no `device_tracker` for this registration yet.
    case trackerMissing
    /// Home Assistant refused or couldn't be reached; the next connection tries again.
    case failed

    /// Whether the person now follows this phone.
    public var isLinked: Bool {
        switch self {
        case .linked, .alreadyLinked, .compositeManaged: true
        default: false
        }
    }
}

/// Puts this phone's `mobile_app` `device_tracker` on the signed-in user's person, because Home Assistant only follows
/// the trackers listed on a person. Idempotent and append-only: other trackers on the person are kept in order, a
/// tracker already listed is left alone, and only `device_trackers` is sent, so nothing else on the person changes.
///
/// **Composite signal.** A person whose `device_trackers` already lists an entity the entity registry gives
/// `platform: "composite"` is left alone (``PresenceLinkOutcome/compositeManaged(person:)``): the integration's presence
/// feature (S+H Home Integration 1.2) combines the phone into that tracker and removes a directly listed phone tracker.
/// The registry list is already fetched to find the phone's tracker, so the check costs no extra command. A composite
/// defined only in YAML without a `unique_id` has no registry entry and is not detected; such a person is linked as before.
public enum PresenceLinker {
    /// Links the tracker of `webhookID` to the person whose user is `user`.
    /// - Parameters:
    ///   - webhookID: The registration's webhook id, which is the `device_tracker`'s unique id in `mobile_app`.
    ///   - user: The signed-in user.
    ///   - api: The websocket.
    @MainActor
    public static func link(webhookID: String, user: HassUser, api: any HassCommandSending) async -> PresenceLinkOutcome {
        guard user.isAdmin || user.isOwner else { return .needsAdmin }
        do {
            let registry = try await api.command("config/entity_registry/list", data: [:])
            guard let tracker = try await tracker(for: webhookID, registry: registry, api: api) else { return .trackerMissing }
            let people = try await api.command("person/list", data: [:])
            guard let person = people["storage"]?.array?.first(where: { $0["user_id"]?.string == user.id }),
                  let personID = person["id"]?.string else { return .noPerson }
            let name = person["name"]?.string ?? personID
            let current = person["device_trackers"]?.array?.compactMap(\.string) ?? []
            guard !current.contains(tracker) else { return .alreadyLinked(person: name) }
            let composites = Set(registry.array?.compactMap { entry -> String? in
                entry["platform"]?.string == "composite" ? entry["entity_id"]?.string : nil
            } ?? [])
            guard current.allSatisfy({ !composites.contains($0) }) else { return .compositeManaged(person: name) }
            _ = try await api.command("person/update", data: ["person_id": personID, "device_trackers": current + [tracker]])
            return .linked(person: name)
        } catch {
            return .failed
        }
    }

    /// Takes this phone's tracker off the signed-in user's person, and only that tracker.
    ///
    /// Idempotent: a tracker or person that is already gone, or a tracker the person doesn't list, is success, so a
    /// retry after a half-finished attempt never sticks. A user who can't edit people never linked anything, so there
    /// is nothing to remove.
    /// - Returns: Whether the person no longer lists this phone.
    /// - Throws: Whatever Home Assistant's failure was; the caller must not treat the removal as done.
    @MainActor
    public static func unlink(webhookID: String, user: HassUser, api: any HassCommandSending) async throws {
        guard user.isAdmin || user.isOwner else { return }
        let registry = try await api.command("config/entity_registry/list", data: [:])
        guard let tracker = registry.array?.first(where: {
            $0["platform"]?.string == "mobile_app" && $0["unique_id"]?.string == webhookID
                && $0["entity_id"]?.string?.hasPrefix("device_tracker.") == true
        })?["entity_id"]?.string else { return }
        let people = try await api.command("person/list", data: [:])
        guard let person = people["storage"]?.array?.first(where: { $0["user_id"]?.string == user.id }),
              let personID = person["id"]?.string else { return }
        let current = person["device_trackers"]?.array?.compactMap(\.string) ?? []
        guard current.contains(tracker) else { return }
        _ = try await api.command("person/update", data: ["person_id": personID, "device_trackers": current.filter { $0 != tracker }])
    }

    /// The `device_tracker` entity id registered for `webhookID`, enabling it if Home Assistant disabled it.
    @MainActor
    private static func tracker(for webhookID: String, registry: JSONValue, api: any HassCommandSending) async throws -> String? {
        guard let entry = registry.array?.first(where: {
            $0["platform"]?.string == "mobile_app" && $0["unique_id"]?.string == webhookID
                && $0["entity_id"]?.string?.hasPrefix("device_tracker.") == true
        }), let entityID = entry["entity_id"]?.string else { return nil }
        if let reason = entry["disabled_by"]?.string, !reason.isEmpty {
            _ = try await api.command("config/entity_registry/update", data: ["entity_id": entityID, "disabled_by": NSNull()])
        }
        return entityID
    }
}
