import HassCore
import HassDemoHouse
import XCTest
@testable import HassUI

/// A hosted test case that runs against the synthetic ``DemoHouse``, not a real house.
///
/// The facades read ``HouseConfigSource/shared`` after a main-queue hop, so a task-local scope would not reach a built
/// screen; this installs the demo document for the whole test and clears it afterwards
/// (`.agents/platforms/apple/architecture.md`, "House config facades"). Subclass it for any hosted test that reads a house
/// facade or a gallery fixture.
///
/// **Two copies of HassCore.** `HassUI` is a shared dynamic framework, so the host app and the bundle see one copy of it. The
/// bundle also lists `HassDesign` and `HassDemoHouse` as its own package products in `project.yml` (`FentonHomeTests`), and those
/// bring their own static copies of `HassCore` and `HassDesign` into the bundle. `HouseConfigSource.shared` therefore exists twice:
/// the app's, which the screens under test read, and the bundle's, which the test code reads when it calls a facade
/// (`Vacuums.all`, `ChoresConfig.page(_:)`). ``GalleryHouse`` fills only the app's, so ``setUp()`` fills the bundle's as well.
/// A source set or scoped from a test body is never seen by the screens, so tests install through this class only.
/// Removing the bundle's direct `HassDesign` and `HassDemoHouse` products so it reaches them through `TEST_HOST` alone
/// builds, but it was not proven (the host died with signal bus before connecting, on a simulator that failed the same way
/// without the change), so the second copy stays until that is retried on a healthy simulator.
@MainActor
class DemoHouseTestCase: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        GalleryHouse.install()
        // The test bundle links its own copy of HassCore beside the host app's, so `HouseConfigSource.shared` is two objects:
        // `GalleryHouse` fills the app's (what the screens under test read) and this fills the bundle's (what the tests read
        // through the facades, `Vacuums.all`, `ChoresConfig.page(_:)`).
        HouseConfigSource.shared.set(DemoHouse.config)
    }

    override func tearDown() async throws {
        GalleryHouse.uninstall()
        HouseConfigSource.shared.set(nil)
        try await super.tearDown()
    }

    /// The demo house's chores page with `id`, for tests that need a chores page; fails the test when the document lacks it.
    func demoChoresPage(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> ChoresConfig.Page {
        try XCTUnwrap(ChoresConfig.page(id), "the demo house has a \(id) chores page", file: file, line: line)
    }
}
