import Foundation

/// The stored list and active pointer.
struct MobileAppRegistrationList: Codable, Equatable {
    var registrations: [MobileAppRegistration] = []
    var active: MobileAppRegistration?
    /// Removals Home Assistant has not confirmed yet (sign-out offline); older saved lists have none.
    var pending: [PendingUnregister] = []

    init(registrations: [MobileAppRegistration] = [], active: MobileAppRegistration? = nil, pending: [PendingUnregister] = []) {
        self.registrations = registrations
        self.active = active
        self.pending = pending
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        registrations = try container.decodeIfPresent([MobileAppRegistration].self, forKey: .registrations) ?? []
        active = try container.decodeIfPresent(MobileAppRegistration.self, forKey: .active)
        pending = try container.decodeIfPresent([PendingUnregister].self, forKey: .pending) ?? []
    }

    mutating func addPending(_ entry: PendingUnregister) {
        if !pending.contains(entry) { pending.append(entry) }
    }

    mutating func removePending(_ entry: PendingUnregister) {
        pending.removeAll { $0 == entry }
    }

    func registration(server: HassServer, userID: String) -> MobileAppRegistration? {
        registrations.first { $0.server == server && $0.userID == userID }
    }

    mutating func save(_ registration: MobileAppRegistration) {
        registrations.removeAll { $0.server == registration.server && $0.userID == registration.userID }
        registrations.append(registration)
    }

    mutating func remove(server: HassServer, userID: String) {
        registrations.removeAll { $0.server == server && $0.userID == userID }
        if active?.server == server, active?.userID == userID { active = nil }
    }
}
