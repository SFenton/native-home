#if DEBUG
import Foundation
import HassCore
import HassDesign
import SwiftUI

/// The Your Summary gallery's fixture house, shared with the UIKit port's gallery: the store, the chores model on its fixture
/// service, the kitchen's fixture server, the Food page's models and the navigator that names the signed-in person.
@MainActor
struct ProfileGalleryFixtures {
    let store: EntityStore
    let chores: ChoresModel
    let service: ChoresFixtureService
    let server: EverShelfFixtureServer
    let models: InventoryModels
    let navigator: ShellNavigator
    let avatars: PersonAvatars
    let opening: SummaryTab?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let empty = environment["FENTON_GALLERY_EMPTY"] == "1"
        let viewerName = environment["FENTON_GALLERY_VIEWER"] ?? Resident.resident1.key
        let viewer = ChoresConfig.Resident(viewerName: viewerName)
        let store = EntityStore()
        let service = ChoresFixtureService(
            store: store, lists: empty ? [:] : ChoresFixtures.lists(extra: Int(environment["FENTON_GALLERY_CHORES"] ?? "") ?? 0)
        )
        let server = EverShelfFixtureServer.sample()
        Self.addExpiredFood(to: server)
        if empty { server.rows = [] }
        server.latency = .milliseconds(environment["FENTON_GALLERY_LATENCY_MS"].flatMap { Int($0) } ?? 100)
        service.extraStates = Self.people() + [
            EntityState(entityId: ChoresConfig.vacationModeEntityId, state: environment["FENTON_GALLERY_VACATION"] == "1" ? "on" : "off"),
            Self.expiredFoodSensor(server.rows),
        ]
        store.replaceAll(service.entityStates())
        let navigator = ShellNavigator()
        navigator.profileName = viewer.map { $0 == .resident1 ? "Alex Demo" : "Sam Demo" } ?? "Guest"
        self.store = store
        self.service = service
        self.server = server
        self.models = InventoryModels(client: EverShelfClient(caller: server))
        self.navigator = navigator
        self.avatars = GalleryAvatarPhotos.avatars(enabled: environment["FENTON_GALLERY_PHOTOS"] == "1", viewerPersonID: viewer == .resident2 ? "person.demo_sam" : "person.demo_alex")
        self.chores = ChoresModel(service: service, todos: TodoStore(service: service), viewerUserId: viewer?.haUserId)
        opening = environment["FENTON_GALLERY_TAB"].flatMap(SummaryTab.init(rawValue:))
    }

    /// The chore service's last call, else the kitchen's.
    var lastCall: String {
        service.lastCall == "none" ? server.lastCall.replacing("None", with: "none") : service.lastCall
    }

    // MARK: - Fixtures

    /// Expired items on top of the sample's one: yesterday, a month and a half ago (two of them), so the rows show the
    /// singular, the plural and a stock count.
    static func addExpiredFood(to server: EverShelfFixtureServer) {
        let calendar = InventoryCalendar.current
        func day(_ offset: Int) -> String {
            calendar.isoString(calendar.calendar.date(byAdding: .day, value: offset, to: calendar.today) ?? calendar.today)
        }
        server.rows += [
            .init(id: 101, name: "Greek Yogurt", quantity: 1, location: .fridge, expiryDate: day(-1), productId: 61),
            .init(id: 102, name: "Cereal", quantity: 2, location: .pantry, expiryDate: day(-45), productId: 62),
            // Long names beside a count, two batches of one product (owner's tall-row report, 2026-10-31).
            .init(id: 103, name: "Extra Sharp cheddar block", quantity: 2, location: .fridge, expiryDate: day(-37), productId: 63),
            .init(id: 104, name: "Extra Sharp cheddar block", quantity: 1, location: .fridge, expiryDate: day(-20), productId: 63),
            .init(id: 105, name: "Sweet Baby Ray's Barbecue Sauce", quantity: 2, location: .fridge, expiryDate: day(-12), productId: 64),
        ]
    }

    /// `expired_list` from the rows already past their date, as EverShelf's sensor reports it.
    static func expiredFoodSensor(_ rows: [EverShelfFixtureServer.Row]) -> EntityState {
        let calendar = InventoryCalendar.current
        let expired = rows.filter { row in
            row.expiryDate.flatMap(calendar.date(fromISO:)).map { calendar.days(until: $0) < 0 } ?? false
        }
        let list: [JSONValue] = expired.map { row in
            .object([
                "name": .string(row.name), "expiry_date": .string(row.expiryDate ?? ""), "location": .string(row.location.rawValue),
                "inventory_id": .number(Double(row.id)), "quantity": .number(row.quantity),
            ])
        }
        return EntityState(entityId: ProfileSummary.expiredFoodEntityId, state: String(expired.count), attributes: ["expired_list": .array(list)])
    }

    static func people() -> [EntityState] {
        [
            EntityState(entityId: "person.demo_alex", state: "home", attributes: ["friendly_name": .string("Alex Demo")]),
            EntityState(entityId: "person.demo_sam", state: "not_home", attributes: ["friendly_name": .string("Sam Demo")]),
            EntityState(entityId: "person.demo_guest", state: "home", attributes: ["friendly_name": .string("Guest")]),
        ]
    }
}
#endif
