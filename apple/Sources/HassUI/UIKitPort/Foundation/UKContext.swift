#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// What the SwiftUI app hands down through `@Environment`, handed down explicitly: every UIKit screen takes the context
/// it was created in and passes it (or a copy with one value changed) to the screens and views it creates.
///
/// A gallery builds one from its fixtures (a fixture ``EntityStore``, a recording ``HassServiceCalling``), the shell from
/// the signed-in session.
@MainActor
struct UKContext {
    /// The one entity store: every read goes through it (AGENTS.md, "One state path").
    var store: EntityStore
    /// Where service calls go: the connection when signed in, a fixture recorder in a gallery.
    var caller: (any HassServiceCalling)?
    /// The live connection, nil in a gallery.
    var connection: HassConnection?
    var session: AppSession?
    /// The house config store a ``UKHouseLayoutGate`` follows, when it is not the session's (a hosted test injects one).
    var houseConfigStore: HouseConfigStore?
    /// The source the gate reads the document from, when it is not ``HouseConfigSource/active`` (a hosted test injects one: the
    /// task-local scope does not survive an observation re-run).
    var houseConfigSource: HouseConfigSource?
    /// The people's photos (`PersonAvatars` in the environment); nil draws every monogram. A gallery passes its fixture's.
    var avatars: PersonAvatars?
    var push: PushCoordinator?
    var location: LocationCoordinator?
    var backdrop: HouseBackdropStore?
    var motion: MotionPolicy?
    var navigator: ShellNavigator?
    var sessionModels: SessionModels?
    /// The section whose stack this screen is in.
    var section: AppSection?
    /// What the shell publishes to every page in the environment (navigation style, chrome, hinge, arrival, the window's
    /// size): `nil` in a gallery that draws no shell (``UKShellEnvironment``).
    var shell: UKShellEnvironment?
    /// The reconnecting arc's state, when the shell runs one (``ReconnectingIndicator``).
    var reconnecting: ReconnectingIndicator?
    /// The screen is a pane or pushed page inside a column of another page (the Settings split's trailing navigation): the column's host
    /// draws the wallpaper, so the page paints no ground of its own (``UKPageViewController``, ``UKPaneViewController``).
    var isPane = false
    /// A page on the wallpaper, or the inside of a sheet (``TileSurface``).
    var surface: TileSurface = .page
    /// No state has arrived yet (first sign-in): tiles and pills show a soft bar for their value.
    ///
    /// Set once by the shell at launch (`true` while nothing has arrived), it then follows the store: the getter is false as soon as
    /// `store.hasReceivedFirstState`, as SwiftUI's environment value is. A view that reads it inside a ``UKObservation`` is updated
    /// when the first state arrives (a copy made before that kept the soft bars for good on the Security doors).
    var valuesPending: Bool {
        get { fixedValuesPending && !store.hasReceivedFirstState }
        set { fixedValuesPending = newValue }
    }
    private var fixedValuesPending = false

    init(store: EntityStore, caller: (any HassServiceCalling)? = nil) {
        self.store = store
        self.caller = caller
    }

    /// The context of a sheet page that is not handed one (``UKPageViewController/init(sheetTitle:)``, ``UKPageHost``): the sheet surface
    /// over an empty store, no shell and no navigator. A sheet page reads its own models, so nothing here is read.
    static let sheetPlaceholder: UKContext = UKContext(store: EntityStore()).with { $0.surface = .sheet }

    /// A copy with one value changed: `context.with { $0.surface = .sheet }`.
    func with(_ change: (inout UKContext) -> Void) -> UKContext {
        var copy = self
        change(&copy)
        return copy
    }
}
#endif
