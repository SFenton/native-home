import Foundation

// MARK: - Authenticated summary scope

/// Private, immutable domain input for the shell's summary tabs and action-bearing collections.
/// Construct from the authenticated user and verified house configuration, never authored JSON.
public struct ServerUISummaryScope: Sendable {
    /// The authored failure choices.
    public enum Failure: Error, Equatable { case missingIdentity, ambiguousIdentity }
    public let viewer: Resident?
    public let lists: ProfileSummary.ResidentLists?
    public var tabs: [SummaryTab] { SummaryTab.tabs(viewer: viewer) }
    public var initialTab: SummaryTab { .profile }
    public var title: String { ProfileSummary.title(viewer: viewer) }
    public let showsAdminTodo: Bool

    /// Creates a server uisummary scope.
    public init(authenticatedUserID: String, people: [HouseConfig.Person]) throws {
        let identity = authenticatedUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !identity.isEmpty else { throw Failure.missingIdentity }
        let matches = people.filter { $0.haUserId.lowercased() == identity }
        guard matches.count <= 1 else { throw Failure.ambiguousIdentity }
        viewer = matches.first.map { Resident(person: $0) }
        showsAdminTodo = matches.first?.seesAdminTodo == true
        lists = matches.first.map { person in
            .init(overdue: .init(title: "Overdue Chores", entityId: person.summaryLists.overdue),
                  dueToday: .init(title: "Upcoming Chores", entityId: person.summaryLists.dueToday),
                  noDueDate: .init(title: "No Due Date", entityId: person.summaryLists.noDueDate))
        }
    }

    /// The only personal collections the authenticated viewer may mount.
    public func lists(for tab: SummaryTab) -> [ChoresConfig.TodoList] {
        guard let lists else { return [] }
        switch tab {
        case .overdue: return [lists.overdue]
        case .upcoming: return [lists.dueToday, lists.noDueDate]
        case .profile, .expiredFood: return []
        }
    }
}
