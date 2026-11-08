import Foundation

/// Chores, Groceries and To-Do pages: the web's `TODO_PAGES`, `CHORE_QUICK_LINKS` and household residents
/// (`ha-sfenton-react-dash:src/constants/portedDashboard.ts`, `householdResidents.ts`, `choreQuickLinkCounts.ts`).
public enum ChoresConfig {
    // MARK: - Residents

    /// A household member (the same type as the top-level ``HassCore/Resident``).
    public typealias Resident = HassCore.Resident

    /// The household's people, in order: the server's document.
    public static var people: [HouseConfig.Person] { HouseConfigSource.active.read { $0.chores.people } ?? [] }

    // MARK: - Lists and pages

    /// Which quick-link subtitle bucket a list counts toward.
    public enum CountBucket: Sendable, Codable { case overdue, upcoming, noDueDate }

    /// One Home Assistant `todo` list shown as a section.
    public struct TodoList: Hashable, Sendable, Identifiable, Codable {
        public var title: String
        public var entityId: String
        /// Script run instead of `todo.update_item` when an item is checked off (admin To-Do).
        public var completionScript: String?
        public var countBucket: CountBucket?
        /// Completed items are hidden (the web default).
        public var hideCompleted = true
        /// The list is skipped while its entity reports no open items.
        public var hideWhenNoOpenItems = false
        /// Only these Home Assistant users see the list; empty means everyone.
        public var userIds: [String] = []

        public var id: String { entityId }

        /// Whether the signed-in `userId` sees this list, given the list entity's open-item count (web `todoListVisible`).
        ///
        /// - Parameter keepsOpen: A row was just ticked and still offers Undo, so the list stays even though its open count
        ///   already reads zero.
        public func isVisible(to userId: String?, openItems: EntityState?, keepsOpen: Bool = false) -> Bool {
            if !userIds.isEmpty {
                guard let userId, userIds.contains(userId) else { return false }
            }
            guard hideWhenNoOpenItems, !keepsOpen else { return true }
            return (openItems?.numericState ?? 0) > 0
        }
    }

    /// What the page's Add button creates.
    public enum AddAction: Hashable, Sendable, Codable {
        /// A task from the household task service, preassigned to this assignee value ("" is Anyone).
        case assignedTask(defaultAssignee: String)
        /// A grocery item on this list.
        case groceryItem(entityId: String)
        /// An admin to-do (synced to GitHub; may carry images).
        case adminTodo(entityId: String)
    }

    /// A page of todo lists (web `TodoPageConfig`).
    public struct Page: Hashable, Sendable, Identifiable, Codable {
        /// Route path, e.g. `alexs-chores`.
        public var id: String
        public var title: String
        public var lists: [TodoList]
        public var emptyTitle: String
        public var emptyDescription: String
        /// Shows the vacation message instead of "nice job" while Vacation Mode is on.
        public var hiddenByVacation = false
        public var hideListHeaders = false
        /// Tasks come from the household task service: rows are editable through the task form and lay out as a grid.
        public var hasTaskForm = false
        /// The resident whose chores these are (personalized empty state).
        public var resident: Resident?
        public var addAction: AddAction

        /// Whether rows can be deleted: DoneTick tasks and groceries (`todo.remove_item` after a confirmation). The admin
        /// To-Do is synced to GitHub issues, so it can only be renamed or completed.
        public var deletesItems: Bool {
            if hasTaskForm { return true }
            if case .groceryItem = addAction { return true }
            return false
        }

        /// Whether rows can be renamed (the admin To-Do only).
        public var editsAdminTodo: Bool {
            if case .adminTodo = addAction { return true }
            return false
        }

        /// The empty-state description for `viewer`: personal when it is their own page, vacation copy when hidden.
        public func emptyDescription(viewer: Resident?, vacationModeOn: Bool) -> String {
            if hiddenByVacation && vacationModeOn { return ChoresConfig.vacationEmptyDescription }
            if let resident, resident == viewer { return "You have no chores due. Nice job!" }
            return emptyDescription
        }
    }

    // MARK: - Entities

    /// The vacation-mode helper: follows ``Vacation/modeEntityId``.
    public static var vacationModeEntityId: String { Vacation.modeEntityId }
    /// Web `pageVacation.empty.description`: the server's document.
    public static var vacationEmptyDescription: String { HouseConfigSource.active.read { $0.chores.vacationEmptyDescription } ?? "" }
    /// The admin To-Do list (web `ADMIN_TODO_ENTITY_ID`).
    public static var adminTodoEntityId: String { HouseConfigSource.active.read { $0.chores.adminTodoEntityId } ?? "" }
    /// Grocery list.
    public static var groceryEntityId: String { HouseConfigSource.active.read { $0.chores.groceryEntityId } ?? "" }
    /// Endpoint for admin to-dos with images (multipart POST, `CreateTodoItemSheet.tsx`).
    public static var adminTodoUploadPath: String { HouseConfigSource.active.read { $0.chores.adminTodoUploadPath } ?? "" }

    // MARK: - Pages

    /// The page with this route path, or an empty placeholder when the document has none (no document yet): the lists come
    /// from the document, so the placeholder holds none.
    private static func page(_ id: String, orPlaceholder title: String) -> Page {
        page(id) ?? Page(
            id: id, title: title, lists: [], emptyTitle: "Nothing To Show", emptyDescription: "",
            addAction: .assignedTask(defaultAssignee: "")
        )
    }

    /// The Chores tab's own lists: the signed-in resident's chores grouped by time of day (route `chores`).
    public static var chores: Page { page("chores", orPlaceholder: "Chores") }
    /// Groceries (route `groceries`).
    public static var groceries: Page { page("groceries", orPlaceholder: "Groceries") }
    /// Chores nobody is assigned to (route `unassigned-chores`).
    public static var unassignedChores: Page { page("unassigned-chores", orPlaceholder: "Unassigned Chores") }
    /// Home improvement tasks (route `home-improvement-chores`).
    public static var homeImprovementChores: Page { page("home-improvement-chores", orPlaceholder: "Home Improvement Tasks") }
    /// The admin To-Do page (route `to-do`).
    public static var adminTodo: Page { page("to-do", orPlaceholder: "To-Do") }

    /// Every page, keyed by route path: the server's document.
    public static var pages: [Page] { HouseConfigSource.active.read { $0.chores.pages } ?? [] }

    /// The page for a route path.
    public static func page(_ id: String) -> Page? { pages.first { $0.id == id } }

    /// Whether the admin To-Do shows for `viewer`: everyone but a person the document hides it from (web
    /// `isDashboardPathVisibleToResident`); a viewer who is not a resident sees it.
    public static func showsAdminTodo(to viewer: Resident?) -> Bool { viewer?.person.seesAdminTodo ?? true }

    // MARK: - Quick links

    /// A Chores tab quick link to a sub-page.
    public struct QuickLink: Hashable, Sendable, Identifiable {
        public var title: String
        public var page: Page
        /// sRGB 0...255, the web's card colour. Reference only: the app colours tiles by `ColorFamily` in HassDesign
        /// because these collide with device families (owner, 2026-10-16).
        public var color: (red: Double, green: Double, blue: Double)
        public var countsGroceries = false
        public var resident: Resident?

        public var id: String { page.id }

        /// "Your Tasks" on the viewer's own link, the web's personalized title.
        public func title(viewer: Resident?) -> String {
            guard let resident, let viewer else { return title }
            return resident == viewer ? "Your Chores" : "\(resident.name)'s Chores"
        }

        /// The subtitle from the page's list counts.
        public func subtitle(_ entity: (String) -> EntityState?) -> String {
            let counts = ChoresConfig.counts(for: page, entity)
            return countsGroceries ? ChoresConfig.grocerySubtitle(counts.total) : ChoresConfig.choreSubtitle(counts)
        }

        /// The navigation tile's state line (owner, 2026-10-27, item 26): the open count the numeral used to carry,
        /// "3 open · 2 overdue". See ``ChoresConfig/openSubtitle(_:)``.
        public func openSubtitle(_ entity: (String) -> EntityState?) -> String {
            ChoresConfig.openSubtitle(ChoresConfig.counts(for: page, entity))
        }

        public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// The Chores tab quick links, in web order: the server's document (each link finds its page by id; a link whose page
    /// is missing is dropped).
    public static var quickLinks: [QuickLink] {
        guard let server = HouseConfigSource.active.read({ $0.chores.quickLinks }) else { return [] }
        let pages = pages
        return server.compactMap { link in
            pages.first { $0.id == link.pageId }.map {
                QuickLink(
                    title: link.title, page: $0, color: (link.tint.red, link.tint.green, link.tint.blue),
                    countsGroceries: link.countsGroceries, resident: link.resident
                )
            }
        }
    }

    // MARK: - Counts

    /// Open-item counts behind a quick-link subtitle.
    public struct Counts: Equatable, Sendable {
        public var overdue = 0
        public var upcoming = 0
        public var noDueDate = 0
        public var total = 0

        public init(overdue: Int = 0, upcoming: Int = 0, noDueDate: Int = 0, total: Int = 0) {
            self.overdue = overdue
            self.upcoming = upcoming
            self.noDueDate = noDueDate
            self.total = total
        }
    }

    /// Sums each list entity's open-item count into its bucket (web `choreQuickLinkCounts`).
    public static func counts(for page: Page, _ entity: (String) -> EntityState?) -> Counts {
        page.lists.reduce(into: Counts()) { counts, list in
            let value = entity(list.entityId)?.numericState ?? 0
            let count = value.isFinite && value > 0 ? Int(value) : 0
            switch list.countBucket {
            case .overdue: counts.overdue += count
            case .upcoming: counts.upcoming += count
            case .noDueDate: counts.noDueDate += count
            case nil: break
            }
            counts.total += count
        }
    }

    private static func pluralized(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    /// "2 overdue tasks · 1 task listed": overdue outranks upcoming; undated tasks are a second clause.
    public static func choreSubtitle(_ counts: Counts) -> String {
        let dated = counts.overdue > 0
            ? pluralized(counts.overdue, "overdue task", "overdue tasks")
            : counts.upcoming > 0 ? pluralized(counts.upcoming, "upcoming task", "upcoming tasks") : ""
        let undated = counts.noDueDate > 0 ? pluralized(counts.noDueDate, "task listed", "tasks listed") : ""
        if !dated.isEmpty && !undated.isEmpty { return "\(dated) · \(undated)" }
        return [dated, undated].first { !$0.isEmpty } ?? "No tasks listed"
    }

    /// A quick-link tile's state line (owner, 2026-10-27, item 26): how many are open and how many of those are overdue, in place of
    /// the numeral. "3 open · 2 overdue", "3 open" when none is overdue, "Nothing open" at zero. The same for Groceries (no list there
    /// is ever overdue).
    public static func openSubtitle(_ counts: Counts) -> String {
        guard counts.total > 0 else { return "Nothing open" }
        return counts.overdue > 0 ? "\(counts.total) open · \(counts.overdue) overdue" : "\(counts.total) open"
    }

    /// "3 items" or "No groceries listed".
    public static func grocerySubtitle(_ count: Int) -> String {
        count > 0 ? pluralized(count, "item", "items") : "No groceries listed"
    }
}
