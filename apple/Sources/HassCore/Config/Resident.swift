import Foundation

/// A household member, named by a neutral key (`resident_1`) that the document, the pages and the tests share.
///
/// Who a key stands for (display name, Home Assistant user, assignee, entity ids) is data in the document's
/// `chores.people` (``ChoresConfig/people``); this type holds only the key, so no house name is built into a
/// type. One type serves the Chores pages, the bed sides and Solo Trip, which used to keep a separate enum each.
public struct Resident: Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    /// The neutral key, `resident_1` and so on.
    public let key: String

    /// Creates a resident from a key. An unknown key reads with its key as its name and no ids.
    public init(key: String) {
        self.key = key
    }

    /// Reads the key as a single JSON string.
    public init(from decoder: Decoder) throws {
        key = try decoder.singleValueContainer().decode(String.self)
    }

    /// Writes the key as a single JSON string.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }

    /// The key.
    public var id: String { key }
    /// The key.
    public var description: String { key }

    /// The first person in the household's order.
    public static let resident1 = Resident(key: "resident_1")
    /// The second person in the household's order.
    public static let resident2 = Resident(key: "resident_2")

    /// Every resident in the document's order: the server's people (none without a document).
    public static var allCases: [Resident] { ChoresConfig.people.map { Resident(key: $0.key) } }

    /// This resident's record in the document, or a bare one named by its key when the document lacks it.
    public var person: HouseConfig.Person {
        ChoresConfig.people.first { $0.key == key } ?? HouseConfig.Person(
            key: key, name: key, haUserId: "", personEntityId: "", taskAssignee: "", soloTripId: key,
            seesAdminTodo: true, summaryLists: .init(overdue: "", dueToday: "", noDueDate: "")
        )
    }

    /// Display name.
    public var name: String { person.name }
    /// Home Assistant user id.
    public var haUserId: String { person.haUserId }
    /// The task form's assignee value for this person.
    public var taskAssignee: String { person.taskAssignee }
    /// The `person.*` entity.
    public var personEntityId: String { person.personEntityId }
    /// The value Home Assistant's Solo Trip scope uses for this person (`traveler`, `home_resident`).
    public var soloTripId: String { person.soloTripId }

    /// The other resident of a two-person household.
    public var other: Resident { Resident.allCases.first { $0.key != key } ?? self }

    /// The resident signed in as `userId`, compared case-insensitively, if any.
    public static func forUserId(_ userId: String?) -> Resident? {
        guard let id = userId?.trimmingCharacters(in: .whitespaces).lowercased(), !id.isEmpty else { return nil }
        return allCases.first { $0.haUserId.lowercased() == id }
    }

    /// The resident a gallery or test names by resident key (`resident_1`), if the document has one.
    public init?(viewerName: String) {
        guard let match = ChoresConfig.people.first(where: { $0.key == viewerName }) else { return nil }
        self.init(key: match.key)
    }

    /// The resident Home Assistant calls `soloTripId` in the Solo Trip sensor, if any.
    public init?(soloTripId: String) {
        guard let match = ChoresConfig.people.first(where: { $0.soloTripId == soloTripId }) else { return nil }
        self.init(key: match.key)
    }
}

/// A resident of the house on a bed side or a Solo Trip (the same type as ``ChoresConfig/Resident``).
public typealias HouseholdResident = Resident
