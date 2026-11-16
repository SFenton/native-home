import Foundation

/// Author-supplied DoneTick people; identity and ordering never come from global house configuration.
public struct ServerUITodoPeople: Equatable, Sendable {
    /// The authored person.
    public struct Person: Equatable, Sendable {
        public let userId: String?
        public let assignee: String
        public let name: String

        /// Creates a person.
        public init(userId: String?, assignee: String, name: String) {
            self.userId = userId
            self.assignee = assignee
            self.name = name
        }
    }

    /// The authored failure choices.
    public enum Failure: Error, Equatable { case invalidPerson }
    public let people: [Person]
    public let anyone: String
    public let viewer: String
    public let unknownPrefix: String

    /// Creates a server uitodo people.
    public init(people: [Person], anyone: String, viewer: String, unknownPrefix: String) throws {
        let valid = people.allSatisfy {
            ($0.userId.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? true) &&
                !$0.assignee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let userIds = people.compactMap(\.userId)
        guard valid, Set(userIds).count == userIds.count,
              Set(people.map(\.assignee)).count == people.count,
              [anyone, viewer, unknownPrefix].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw Failure.invalidPerson }
        self.people = people
        self.anyone = anyone
        self.viewer = viewer
        self.unknownPrefix = unknownPrefix
    }

    /// Unknown existing assignees are kept as a selectable option rather than lost on edit.
    public func options(viewerUserId: String?, selected: String) -> [DonetickTaskForm.Option] {
        var result = [DonetickTaskForm.Option(anyone, "")]
        result += people.map { person in
            DonetickTaskForm.Option(viewerUserId != nil && person.userId == viewerUserId ? viewer : person.name, person.assignee)
        }
        if !selected.isEmpty, !result.contains(where: { $0.value == selected }) {
            result.append(.init("\(unknownPrefix) \(selected)", selected))
        }
        return result
    }
}
