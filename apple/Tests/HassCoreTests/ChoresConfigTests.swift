import Foundation
@testable import HassCore
import HassTestSupport
import Testing

@Suite(.demoHouse)
struct ChoresConfigTests {
    private let alex = ChoresConfig.Resident.resident1.haUserId
    private let sam = ChoresConfig.Resident.resident2.haUserId

    @Test func residentsMapFromHomeAssistantUsers() {
        #expect(ChoresConfig.Resident.forUserId(alex) == .resident1)
        #expect(ChoresConfig.Resident.forUserId(" \(sam.uppercased()) ") == .resident2)
        #expect(ChoresConfig.Resident.forUserId("someone") == nil)
        #expect(ChoresConfig.Resident.forUserId("") == nil)
        #expect(ChoresConfig.Resident.forUserId(nil) == nil)
        #expect(ChoresConfig.Resident.resident1.name == DemoHouse.config.chores.people[0].name)
        #expect(ChoresConfig.Resident.resident2.taskAssignee == "2")
    }

    @Test func adminTodoIsHiddenOnlyFromSam() {
        #expect(ChoresConfig.showsAdminTodo(to: .resident1))
        #expect(ChoresConfig.showsAdminTodo(to: nil))
        #expect(!ChoresConfig.showsAdminTodo(to: .resident2))
    }

    @Test func pagesMatchTheWebRoutes() {
        #expect(ChoresConfig.pages.map(\.id) == ["chores", "groceries", "alexs-chores", "sams-chores", "unassigned-chores", "home-improvement-chores", "to-do"])
        #expect(ChoresConfig.page("groceries")?.lists.first?.entityId == "todo.demo_todo_2")
        #expect(ChoresConfig.page("nope") == nil)
        #expect(ChoresConfig.page("chores")!.lists.count == 13)
        // A resident's page reads the views that include unassigned chores, like the Chores tab and the Profile summary
        // (owner, 2026-10-16: the LV600S aroma pad chores have no assignee and must show for Alex).
        #expect(ChoresConfig.page("sams-chores")!.lists.map(\.entityId) == ["todo.demo_todo_18", "todo.demo_todo_19",
                                                                    "todo.demo_todo_20", "todo.demo_todo_13"])
        #expect(ChoresConfig.page("unassigned-chores")!.lists.map(\.entityId) == ["todo.demo_todo_21", "todo.demo_todo_22", "todo.demo_todo_23", "todo.demo_todo_24"])
        // The Profile summary's overdue list is the Past Due list of the same page, so the badge, the summary and the page agree.
        #expect(ProfileSummary.lists(for: .resident1).overdue.entityId == ChoresConfig.pages.first { $0.resident == .resident1 }!.lists[0].entityId)
        #expect(ProfileSummary.lists(for: .resident2).overdue.entityId == ChoresConfig.pages.first { $0.resident == .resident2 }!.lists[0].entityId)
        #expect(ChoresConfig.page("home-improvement-chores")!.addAction == .assignedTask(defaultAssignee: "3"))
        #expect(ChoresConfig.page("to-do")!.editsAdminTodo)
        #expect(!ChoresConfig.page("groceries")!.editsAdminTodo)
        #expect(ChoresConfig.page("to-do")!.lists[0].completionScript == "script.demo_script_1")
    }

    @Test func listsShowOnlyToTheirUsersAndWhenOpen() {
        let alex = "demo-user-alex", sam = "demo-user-sam"
        let morning = ChoresConfig.page("chores")!.lists.first { $0.entityId == "todo.demo_todo_6" }!
        let open = EntityState(entityId: morning.entityId, state: "2")
        #expect(morning.isVisible(to: alex, openItems: open))
        #expect(!morning.isVisible(to: sam, openItems: open))
        #expect(!morning.isVisible(to: nil, openItems: open))
        let empty = EntityState(entityId: "todo.demo_x", state: "0")
        #expect(morning.hideWhenNoOpenItems && !morning.isVisible(to: alex, openItems: empty))
        #expect(morning.isVisible(to: alex, openItems: empty, keepsOpen: true), "A just-ticked row keeps its list")
        #expect(!morning.isVisible(to: sam, openItems: empty, keepsOpen: true), "Never for a viewer who is not allowed")
        #expect(!morning.isVisible(to: alex, openItems: EntityState(entityId: morning.entityId, state: "0")))
        #expect(!morning.isVisible(to: alex, openItems: nil))
        let grocery = ChoresConfig.page("groceries")!.lists[0]
        #expect(grocery.isVisible(to: nil, openItems: nil))
    }

    @Test func emptyDescriptionsPersonalizeAndYieldToVacation() {
        let page = ChoresConfig.page("alexs-chores")!
        #expect(page.emptyDescription(viewer: .resident2, vacationModeOn: false) == "Alex has no chores due. Nice job!")
        #expect(page.emptyDescription(viewer: .resident1, vacationModeOn: false) == "You have no chores due. Nice job!")
        #expect(page.emptyDescription(viewer: .resident1, vacationModeOn: true) == "Enjoy vacation!")
        #expect(ChoresConfig.page("groceries")!.emptyDescription(viewer: nil, vacationModeOn: true) == "Add some groceries to see them appear.")
    }

    @Test func quickLinksPersonalizeTitles() {
        let links = ChoresConfig.quickLinks
        #expect(links.map(\.id) == ["groceries", "alexs-chores", "sams-chores", "unassigned-chores", "home-improvement-chores"])
        #expect(links[1].title(viewer: .resident1) == "Your Chores")
        #expect(links[1].title(viewer: .resident2) == "\(Resident.resident1.name)'s Chores")
        #expect(links[1].title(viewer: nil) == "Alex's Tasks")
        #expect(links[3].title(viewer: .resident1) == "Unassigned Tasks")
        #expect(links[0] == links[0] && links[0] != links[1])
        #expect(Set(links).count == links.count)
    }

    @Test func countsSumIntoBuckets() {
        let states: [String: String] = ["todo.demo_todo_3": "2", "todo.demo_todo_16": "1",
                                        "todo.demo_todo_17": "3", "todo.demo_todo_8": "1",
                                        "todo.demo_todo_2": "unavailable"]
        let lookup: (String) -> EntityState? = { id in states[id].map { EntityState(entityId: id, state: $0) } }
        #expect(ChoresConfig.counts(for: ChoresConfig.page("alexs-chores")!, lookup) == .init(overdue: 2, upcoming: 4, noDueDate: 1, total: 7))
        #expect(ChoresConfig.counts(for: ChoresConfig.page("groceries")!, lookup) == .init())
        #expect(ChoresConfig.quickLinks[1].subtitle(lookup) == "2 overdue tasks · 1 task listed")
        #expect(ChoresConfig.quickLinks[0].subtitle(lookup) == "No groceries listed")
    }

    @Test func subtitlesFollowTheWebWording() {
        #expect(ChoresConfig.choreSubtitle(.init(overdue: 1)) == "1 overdue task")
        #expect(ChoresConfig.choreSubtitle(.init(upcoming: 3)) == "3 upcoming tasks")
        #expect(ChoresConfig.choreSubtitle(.init(upcoming: 1, noDueDate: 2)) == "1 upcoming task · 2 tasks listed")
        #expect(ChoresConfig.choreSubtitle(.init(noDueDate: 1)) == "1 task listed")
        #expect(ChoresConfig.choreSubtitle(.init()) == "No tasks listed")
        #expect(ChoresConfig.grocerySubtitle(1) == "1 item")
        #expect(ChoresConfig.grocerySubtitle(4) == "4 items")
        #expect(ChoresConfig.grocerySubtitle(0) == "No groceries listed")
    }
}
