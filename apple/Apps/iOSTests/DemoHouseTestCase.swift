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
/// **One copy of HassCore.** The bundle links only `HassUI` (`project.yml`, `FentonHomeTests`), the dynamic framework it shares
/// with the host app, and reaches `HassCore`, `HassDesign` and `HassDemoHouse` through it. So ``HouseConfigSource/shared`` is one
/// object: what ``GalleryHouse`` installs is what both the screens under test and the test's own facade calls (`Vacuums.all`,
/// `ChoresConfig.page(_:)`) read. Never list `HassDesign` or `HassDemoHouse` as products of the bundle again: that links a second
/// static copy of them and of `HassCore`, and an `@Observable` write made by test code then never reaches the screen observing
/// it (`.agents/testing/apple/README.md`, "Hosted tests share one copy").
@MainActor
class DemoHouseTestCase: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        GalleryHouse.install()
    }

    override func tearDown() async throws {
        GalleryHouse.uninstall()
        try await super.tearDown()
    }

    /// The demo house's chores page with `id`, for tests that need a chores page; fails the test when the document lacks it.
    func demoChoresPage(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> ChoresConfig.Page {
        try XCTUnwrap(ChoresConfig.page(id), "the demo house has a \(id) chores page", file: file, line: line)
    }
}
