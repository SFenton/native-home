#if DEBUG
import HassCore
import HassDemoHouse

/// The house the DEBUG gallery draws: the synthetic ``DemoHouse``, never a real document.
///
/// Gallery pages read the same `*Config` facades the app does, and their fixtures key states by the ids those facades
/// answer with. Installing the demo document as ``HouseConfigSource/shared`` makes every facade answer with demo ids,
/// including reads that happen after a main-queue hop or inside an observation re-run, where a task-local scope would not
/// survive. A gallery launch has no sign-in, so nothing else writes the source.
@MainActor
enum GalleryHouse {
    /// Makes the demo house the document of `source`. Idempotent: the source ignores an equal document.
    /// - Parameter source: The source to fill; the app's shared one by default (a test passes its own).
    static func install(into source: HouseConfigSource = .shared) {
        source.set(DemoHouse.config)
    }

    /// Clears the document (the facades answer empty again). Hosted tests call it from `tearDown`.
    /// - Parameter source: The source to clear; the app's shared one by default.
    static func uninstall(from source: HouseConfigSource = .shared) {
        source.set(nil)
    }
}
#endif
