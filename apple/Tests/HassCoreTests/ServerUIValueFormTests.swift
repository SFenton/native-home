import Foundation
import Testing
@testable import HassCore

// MARK: - Real scalar draft transactions

@Suite @MainActor struct ServerUIValueFormTests {
    private let identity = ServerUIDraft.Identity(ownerId: "todo.demo_unit", recordId: "record")
    private let field = ServerUIFormValue.text("name", "Name", "Original", required: true)

    @Test func scheduleDraftAcceptsOnlyWholeSecondsInsideProviderBounds() async throws {
        let time = ServerUIFormValue.number("start", "Starts", 1_800_000_000, minimum: 1_700_000_000,
            maximum: 1_900_000_000, step: 1, control: .scheduleDateTime)
        var saved: Double?
        let form = try ServerUIValueForm(identity: identity, fields: [time]) { saved = try $0.formNumber("start") }
        #expect(throws: ServerUIRecordFailure.invalidValue) { try form.set(.number(1_800_000_000.5), group: "record", field: "start") }
        #expect(throws: ServerUIRecordFailure.invalidValue) { try form.set(.number(2_000_000_000), group: "record", field: "start") }
        try form.set(.number(1_800_000_060), group: "record", field: "start")
        #expect(saved == nil)
        try await form.save()
        #expect(saved == 1_800_000_060)
    }

    @Test func resetKeepsEditingWhileDiscardReleasesExactlyOnce() throws {
        var releases = 0
        let form = try ServerUIValueForm(identity: identity, fields: [field], release: { releases += 1 }) { _ in }
        try form.set(.string("Changed"), group: "record", field: "name")
        #expect(form.hasChanges && form.canSave)
        try form.reset()
        #expect(!form.hasChanges)
        #expect(releases == 0)
        try form.set(.string("Again"), group: "record", field: "name")
        try form.discard()
        try form.discard()
        #expect(releases == 1)
        #expect(throws: ServerUIRecordFailure.busy) { try form.set(.string("Lost"), group: "record", field: "name") }
    }

    @Test func invalidIdentityTypeAndRequiredValuesNeverSubmit() throws {
        var submitted = false
        let form = try ServerUIValueForm(identity: identity, fields: [field]) { _ in submitted = true }
        #expect(throws: ServerUIRecordFailure.invalidField) { try form.set(.string("Other"), group: "other", field: "name") }
        #expect(throws: ServerUIRecordFailure.invalidValue) { try form.set(.boolean(true), group: "record", field: "name") }
        try form.set(.string("  "), group: "record", field: "name")
        #expect(!form.canSave)
        #expect(!submitted)
        #expect(throws: ServerUIRecordFailure.invalidField) {
            try ServerUIValueForm(identity: identity, fields: [field, field]) { _ in }
        }
    }

    @Test func savePinsValuesAndOwnershipAndFailureRetainsEditsForRetry() async throws {
        var form: ServerUIValueForm!
        var fail = true
        var snapshots: [[String: ServerUICompositionDocument.LocalValue]] = []
        form = try ServerUIValueForm(identity: identity, fields: [field]) { values in
            snapshots.append(values)
            #expect(form.isBusy)
            #expect(throws: ServerUIRecordFailure.busy) { try form.reset() }
            #expect(throws: ServerUIRecordFailure.busy) { try form.discard() }
            #expect(throws: ServerUIRecordFailure.busy) { try form.set(.string("Racing"), group: "record", field: "name") }
            if fail { throw ServerUIRecordFailure.unavailable("Try again") }
        }
        try form.set(.string("Edited"), group: "record", field: "name")
        await #expect(throws: ServerUIRecordFailure.unavailable("Try again")) { try await form.save() }
        #expect(form.hasChanges && form.canSave && !form.isBusy)
        #expect(form.error == "Try again")
        fail = false
        try await form.save()
        #expect(!form.hasChanges && !form.canSave && form.error == nil)
        #expect(snapshots == [["name": .string("Edited")], ["name": .string("Edited")]])
    }

    @Test func conditionalFieldsRetainValuesAcrossVisibilityChanges() throws {
        let form = try ServerUIValueForm(identity: identity,
            fields: [.toggle("enabled", "Enabled", false), field],
            visibility: { key, values in key != "name" || values["enabled"] == .boolean(true) }) { _ in }
        #expect(form.groups[0].fields[1].visible == false)
        #expect(throws: ServerUIRecordFailure.invalidField) { try form.set(.string("Hidden"), group: "record", field: "name") }
        try form.set(.boolean(true), group: "record", field: "enabled")
        try form.set(.string("Retained"), group: "record", field: "name")
        try form.set(.boolean(false), group: "record", field: "enabled")
        #expect(form.groups[0].fields[1].visible == false)
        #expect(form.values["name"] == .string("Retained"))
    }

    @Test func defaultsAndControlMetadataRemainClosed() throws {
        #expect(throws: ServerUIRecordFailure.invalidField) {
            try ServerUIValueForm(identity: identity, fields: [field], defaults: ["unknown": .string("No")]) { _ in }
        }
        let mismatched = ServerUIFormValue(key: "invalid", label: "Invalid", control: .toggle,
            rule: .string(maxLength: 10), value: .string("text"))
        #expect(throws: ServerUIRecordFailure.invalidField) {
            try ServerUIValueForm(identity: identity, fields: [mismatched]) { _ in }
        }
        let form = try ServerUIValueForm(identity: identity, fields: [field], defaults: ["name": .string("Default")]) { _ in }
        try form.reset()
        #expect(form.values["name"] == .string("Default"))
        #expect(form.hasChanges && !form.canReset)
        try form.discard()
        #expect(form.values["name"] == .string("Original"))
    }

    @Test func optionalChoiceMayStartUnselectedButRejectsUnknownOptions() throws {
        let choice = ServerUIFormValue.choice("quick", "Quick Dates", "", [.init("Tomorrow", "tomorrow")], control: .options)
        let form = try ServerUIValueForm(identity: identity, fields: [choice]) { _ in }
        try form.set(.string("tomorrow"), group: "record", field: "quick")
        #expect(form.canSave)
        #expect(throws: ServerUIRecordFailure.invalidValue) { try form.set(.string("invented"), group: "record", field: "quick") }
        try form.reset()
        #expect(form.values["quick"] == .string(""))
    }

}
