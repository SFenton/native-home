#if os(iOS) && DEBUG
import HassCore
import UIKit

// Owned by the Chores lane. Pages: chores.
extension UKGallery {
    /// `FENTON_GALLERY=chores`: Chores, Groceries and To-Do on fixture lists with a recording service (``ChoresGallery``).
    /// `FENTON_GALLERY_TODO_PAGE=<page id>` opens another page as the root (e.g. `to-do`); `FENTON_GALLERY_VIEWER=sam` signs the
    /// fixtures in as Sam; `FENTON_GALLERY_EMPTY=1` empties every list; `FENTON_GALLERY_FAIL_COMPLETE=1` makes every check-off
    /// fail after 4 s; `FENTON_GALLERY_CHORES=<n>` adds `n` more chores to each of Alex's lists (the long house);
    /// `FENTON_GALLERY_CLEAN=1` leaves the last-call line out.
    static func chores(_ page: ComponentGallery.Page) -> UIViewController? {
        guard page == .chores else { return nil }
        let environment = ProcessInfo.processInfo.environment
        let empty = environment["FENTON_GALLERY_EMPTY"] == "1"
        let store = EntityStore()
        let service = ChoresFixtureService(store: store, lists: empty ? [:] : ChoresFixtures.lists(extra: Int(environment["FENTON_GALLERY_CHORES"] ?? "") ?? 0),
                                           failsCompletion: environment["FENTON_GALLERY_FAIL_COMPLETE"] == "1")
        store.replaceAll(service.entityStates())
        let viewer = environment["FENTON_GALLERY_VIEWER"].flatMap({ ChoresConfig.Resident(viewerName: $0) }) ?? .resident1
        let model = ChoresModel(service: service, todos: TodoStore(service: service), viewerUserId: viewer.haUserId)
        let choresPage = environment["FENTON_GALLERY_TODO_PAGE"].flatMap(ChoresConfig.page) ?? ChoresConfig.chores
        let context = UKGalleryChrome.context(store: store)

        let controller: UKTodoPageViewController
        if choresPage == ChoresConfig.chores {
            controller = UKChoresPages.root(context: context, model: model)
        } else {
            controller = UKChoresPages.page(choresPage, context: context, model: model)
        }
        // The last-call line stays on the root page, so the floating Add bar sits above it. FENTON_GALLERY_CLEAN=1 (screenshots)
        // leaves it out.
        if !GalleryEnvironment.isClean {
            let lastCall = UKGalleryLastCallView()
            controller.bottomAccessory = lastCall
            controller.bag.observe { [weak lastCall] in lastCall?.record(service.lastCall) }
        }
        return UKGalleryChrome.wrap(controller, context: context)
    }
}
#endif
