import HassCore
import XCTest
@testable import HassUI

/// Kept text in the view layer (`sh.text-keep@1`, T-text-keep): the bindings give a `keep` slot its last answer while its value is
/// unavailable, its fallback before any answer, and the loading look only while the house has not been heard from.
@MainActor
final class ServerUITextKeepHostedTests: XCTestCase {
    private func slot() throws -> ServerUICompositionDocument.StringValue {
        let publication = try ServerUICompositionPublication.decode(Data(UKTextKeepGalleryFixture.envelope.utf8))
        guard case .text(let text) = publication.document.pages[0].surface.components[0] else { throw CocoaError(.fileReadCorruptFile) }
        return text.value
    }

    private func bindings(_ store: EntityStore) throws -> UKServerUIBindings {
        let publication = try ServerUICompositionPublication.decode(Data(UKTextKeepGalleryFixture.envelope.utf8))
        var context = UKContext(store: store)
        context.valuesPending = true
        return UKServerUIBindings(sources: publication.document.dataSources, context: context)
    }

    private func answer(_ id: String, _ state: String) -> EntityState { EntityState(entityId: id, state: state) }

    /// Live, kept, recovered: the slot's own memory, per instance.
    func testKeepSlotDrawsLastAnswerWhileUnavailable() throws {
        let store = EntityStore()
        let bindings = try bindings(store)
        let value = try slot()
        var memory = ServerUITextMemory()
        var other = ServerUITextMemory()
        _ = store.replaceAll([answer("sensor.keep_temperature", "21.5 degrees")])
        XCTAssertEqual(bindings.string(value, memory: &memory).value, "21.5 degrees")
        _ = store.replaceAll([answer("sensor.keep_temperature", "unavailable")])
        XCTAssertEqual(bindings.string(value, memory: &memory).value, "21.5 degrees", "kept")
        XCTAssertEqual(bindings.string(value, memory: &other).value, "No reading", "another instance never answered")
        XCTAssertEqual(bindings.string(value).value, "No reading", "the memoryless form draws the fallback")
    }

    /// Before any answer the slot draws its fallback; the loading look is only for a house not yet heard from.
    func testBeforeAnyAnswerDrawsTheFallbackNotLoading() throws {
        let store = EntityStore()
        let bindings = try bindings(store)
        let value = try slot()
        var memory = ServerUITextMemory()
        if case .loading = bindings.string(value, memory: &memory) {} else { XCTFail("an empty store has not been heard from: loading") }
        // A delta on an empty store has not handed the server's state over: still not heard from.
        _ = store.apply([answer("sensor.keep_temperature", "unavailable")])
        if case .loading = bindings.string(value, memory: &memory) {} else { XCTFail("apply alone leaves the store unheard") }
        _ = store.replaceAll([answer("sensor.keep_temperature", "unavailable")])
        XCTAssertEqual(bindings.string(value, memory: &memory).value, "No reading")
    }

    /// The gallery's `before` state hands the whole state over, so its slots draw the fallback (it once drew the loading look).
    func testGalleryBeforeStateHasHeardFromTheServer() {
        for state in [UKTextKeepSourceState.before, .kept] {
            let gallery = UKTextKeepGalleryViewController(start: state)
            gallery.loadViewIfNeeded()
            XCTAssertTrue(gallery.store.hasReceivedFirstState, "\(state): the page is built after the server answered")
        }
        let loading = UKTextKeepGalleryViewController(start: .loading)
        loading.loadViewIfNeeded()
        XCTAssertFalse(loading.store.hasReceivedFirstState, "loading has heard nothing")
    }
}
