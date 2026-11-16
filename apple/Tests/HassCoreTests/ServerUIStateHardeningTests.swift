import Foundation
import Observation
import Testing
@testable import HassCore

// MARK: - Equality-gated writes, fixed copy and retained selection

/// A flag a `withObservationTracking` change handler can set from any thread.
private final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    var value: Bool { lock.withLock { fired } }
    func set() { lock.withLock { fired = true } }
}

@Suite @MainActor struct ServerUIStateHardeningTests {
    private typealias D = ServerUICompositionDocument

    private func changes(_ read: () -> Void) -> ChangeFlag {
        let flag = ChangeFlag()
        withObservationTracking(read) { flag.set() }
        return flag
    }

    // MARK: Retained automatic selection

    @Test func staleEngagedPanelIsForgottenInsteadOfFailingEveryLaterResolve() throws {
        var state = ServerUIAutomaticSelection()
        let wide = ["chooser", "vacation", "solo"]
        #expect(try state.resolve("vacation", initial: "chooser", allowed: wide, retainsEngaged: true) == "vacation")
        // The publication drops the engaged panel; returning to the chooser used to throw forever.
        let narrowed = ["chooser", "solo"]
        #expect(try state.resolve("chooser", initial: "chooser", allowed: narrowed, retainsEngaged: true) == "chooser")
        #expect(state.displayed == "chooser")
        // And it stays forgotten if the panel comes back.
        #expect(try state.resolve("chooser", initial: "chooser", allowed: wide, retainsEngaged: true) == "chooser")
    }

    @Test func invalidResolveLeavesTheSelectionUntouched() throws {
        var state = ServerUIAutomaticSelection()
        _ = try state.resolve("vacation", initial: "chooser", allowed: ["chooser", "vacation"], retainsEngaged: true)
        let before = state
        for (proposed, initial, allowed) in [("missing", "chooser", ["chooser", "vacation"]),
                                             ("chooser", "absent", ["chooser", "vacation"]),
                                             ("chooser", "chooser", []), ("chooser", "chooser", ["chooser", "chooser"])] {
            #expect(throws: ServerUIRecordFailure.invalidValue) {
                try state.resolve(proposed, initial: initial, allowed: allowed, retainsEngaged: true)
            }
        }
        #expect(state == before)
    }

    // MARK: Writes only on change

    @Test func localStateDoesNotNotifyWhenAValueIsUnchanged() throws {
        let field = D.LocalField(id: "count", initial: .number(2), rule: .number(minimum: 0, maximum: 10, step: 2))
        let state = try ServerUILocalState(fields: [field])
        let same = changes { _ = state.values }
        try state.set(.number(2), for: "count")
        try state.apply([field])
        #expect(!same.value)
        let different = changes { _ = state.values }
        try state.set(.number(4), for: "count")
        #expect(different.value)
    }

    @Test func rowCollectionDoesNotNotifyWhenRowsAndPhaseAreUnchanged() throws {
        let collection = ServerUIRowCollection()
        let rows = [ServerUIRowItem(id: "a", title: "A")]
        try collection.apply(rows, phase: .ready)
        let same = changes { _ = collection.rows; _ = collection.phase }
        try collection.apply(rows, phase: .ready)
        #expect(!same.value)
        let different = changes { _ = collection.rows }
        try collection.apply([ServerUIRowItem(id: "a", title: "B")], phase: .ready)
        #expect(different.value)
    }

    @Test func rowCollectionRejectsInvalidRowsWithoutChangingWhatIsShown() throws {
        let collection = ServerUIRowCollection()
        try collection.apply([.init(id: "a", title: "A")], phase: .ready)
        #expect(throws: ServerUIRowCollection.Failure.invalidRows) {
            try collection.apply([.init(id: "a", title: "A"), .init(id: "a", title: "Again")], phase: .ready)
        }
        #expect(throws: ServerUIRowCollection.Failure.invalidRows) { try collection.apply(nil, phase: .ready) }
        #expect(collection.rows.map(\.id) == ["a"] && collection.phase == .ready)
        try collection.apply(nil, phase: .failed)
        #expect(collection.rows.map(\.id) == ["a"] && collection.phase == .failed)
    }

    // MARK: Fixed failure copy

    @MainActor private final class ThrownBox {
        var error: any Error
        init(_ error: any Error) { self.error = error }
    }

    private struct ServerText: LocalizedError {
        var errorDescription: String? { "Internal: WebSocket 401 from 10.0.0.1/api" }
    }

    @Test func formShowsFixedCopyForForeignErrorsAndCuratedCopyForTypedOnes() async throws {
        let identity = ServerUIDraft.Identity(ownerId: "owner", recordId: "record")
        let field = ServerUIFormValue.text("name", "Name", "Old", required: true)
        let thrown = ThrownBox(ServerText())
        let form = try ServerUIValueForm(identity: identity, fields: [field]) { _ in throw thrown.error }
        try form.set(.string("New"), group: "record", field: "name")
        await #expect(throws: ServerText.self) { try await form.save() }
        #expect(form.error == "The change could not be saved. Try again.")
        #expect(form.error?.contains("10.0.0.1") == false)
        thrown.error = ServerUIRecordFailure.staleSelection
        await #expect(throws: ServerUIRecordFailure.staleSelection) { try await form.save() }
        #expect(form.error == ServerUIRecordFailure.staleSelection.errorDescription)
        thrown.error = URLError(.notConnectedToInternet)
        await #expect(throws: URLError.self) { try await form.save() }
        #expect(form.error == "The change could not be saved. Try again.")
        #expect(form.hasChanges && form.canSave && !form.isBusy)
    }

    @Test func todoServiceFailureDescriptionNeverRepeatsServerText() {
        let failure = ServerUITodoProvider.Failure.service("Internal: token abc123 rejected")
        #expect(failure.errorDescription == "The task service could not complete this action")
        #expect(failure.localizedDescription.contains("abc123") == false)
        #expect(ServerUITodoProvider.Failure.forbidden.errorDescription == "This action is not available")
    }
}
