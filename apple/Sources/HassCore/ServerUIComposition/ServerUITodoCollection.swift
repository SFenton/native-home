import Foundation

// MARK: - Authored todo collection

extension ServerUICompositionDocument {
    /// One record page of todo lists, authored in the publication: which lists it shows, what its Add button creates, the
    /// copy of its empty state and how it changes for one resident.
    ///
    /// This is the definition `fenton_home/house_config` used to carry as `chores.pages`. A `collection` node with the
    /// `todo` template names the source's id as its `providerId`; the forms that add and edit its rows are the
    /// ids `<source id>-add` and `<source id>-edit`. House configuration keeps only the facts a page needs (the people,
    /// the grocery and admin lists); the app reads nothing else about a page from it.
    public struct TodoCollection: Equatable, Sendable {
        /// One Home Assistant `todo` list the page shows as a section.
        public struct List: Equatable, Sendable {
            /// The section title.
            public let title: String
            /// The `todo.*` entity.
            public let entityId: String
            /// Script run instead of `todo.update_item` when an item is checked off.
            public let completionScript: String?
            /// Completed items are hidden.
            public let hideCompleted: Bool
            /// The list is skipped while its entity reports no open items.
            public let hideWhenNoOpenItems: Bool
            /// A rule on who sees the list. Only a viewer rule naming user ids, hidden until the user is known, is accepted,
            /// because a list is read where only the user id is known; see ``userIds``.
            public let visibility: ServerUIVisibility?

            /// The Home Assistant user ids the rule names; empty means everyone sees the list.
            public var userIds: [String] {
                if case .viewer(_, let ids)? = visibility?.predicate { return ids ?? [] }
                return []
            }
        }

        /// What the page's Add button creates.
        public enum AddAction: Equatable, Sendable {
            /// A task from the household task service, preassigned to this assignee value ("" is Anyone).
            case task(defaultAssignee: String)
            /// A grocery item on this list.
            case grocery(entityId: String)
            /// An admin to-do (may carry images).
            case admin(entityId: String)
        }

        /// A personal version of the page for one resident.
        public struct Personalization: Equatable, Sendable {
            /// A person's key in house configuration (`chores.people[].key`).
            public let residentId: String
            /// The page title for the resident themselves.
            public let ownTitle: String
            /// The page title for anyone else.
            public let otherTitle: String
            /// The empty-state text for the resident themselves; absent keeps ``TodoCollection/emptyDescription``.
            public let ownEmptyDescription: String?
        }

        /// The page title, for a viewer ``personalization`` does not name.
        public let title: String
        /// The lists, in order.
        public let lists: [List]
        /// What Add creates.
        public let addAction: AddAction
        /// Whether sections draw without their list titles.
        public let hideListHeaders: Bool
        /// Whether the page shows the vacation message while Vacation Mode is on.
        public let hiddenByVacation: Bool
        /// The empty state's title.
        public let emptyTitle: String
        /// The empty state's text.
        public let emptyDescription: String
        /// The resident variant, if any.
        public let personalization: Personalization?

        /// Whether rows come from the household task service (and so edit through the task form).
        public var hasTaskForm: Bool {
            if case .task = addAction { return true }
            return false
        }

        /// The page as the todo views read it, under the source's id.
        public func page(id: String) -> ChoresConfig.Page {
            ChoresConfig.Page(
                id: id, title: title,
                lists: lists.map {
                    ChoresConfig.TodoList(title: $0.title, entityId: $0.entityId, completionScript: $0.completionScript,
                                          countBucket: nil, hideCompleted: $0.hideCompleted,
                                          hideWhenNoOpenItems: $0.hideWhenNoOpenItems, userIds: $0.userIds)
                },
                emptyTitle: emptyTitle, emptyDescription: emptyDescription, hiddenByVacation: hiddenByVacation,
                hideListHeaders: hideListHeaders, hasTaskForm: hasTaskForm, resident: personalization.map { Resident(key: $0.residentId) },
                ownEmptyDescription: personalization?.ownEmptyDescription,
                addAction: {
                    switch addAction {
                    case .task(let assignee): .assignedTask(defaultAssignee: assignee)
                    case .grocery(let entityId): .groceryItem(entityId: entityId)
                    case .admin(let entityId): .adminTodo(entityId: entityId)
                    }
                }())
        }
    }
}
