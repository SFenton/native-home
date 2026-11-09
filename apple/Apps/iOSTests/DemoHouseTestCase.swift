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
