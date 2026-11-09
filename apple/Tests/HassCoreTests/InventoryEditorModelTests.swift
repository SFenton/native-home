import Foundation
@testable import HassCore
import Testing

/// The item editor against the fixture server: drafts, saves, deletes and the prepared-food projection.
/// "Today" is 2026-10-11 (UTC).
@MainActor
struct InventoryEditorModelTests {
    typealias Row = EverShelfFixtureServer.Row

    let calendar = InventoryFixtures.calendar()

    /// Milk has a dated batch (rows 1 and 2, 3 units) and an undated one (row 3).
    private func makeServer() -> EverShelfFixtureServer {
        EverShelfFixtureServer(rows: [
            Row(id: 1, name: "Milk", quantity: 2, location: .fridge, expiryDate: "2026-10-20"),
            Row(id: 2, name: "Milk", quantity: 1, location: .fridge, expiryDate: "2026-10-20"),
            Row(id: 3, name: "Milk", quantity: 1, location: .fridge, expiryDate: nil),
            Row(id: 4, name: "Jam", quantity: 1, location: .fridge, expiryDate: "2026-12-01"),
            Row(id: 5, name: "Soup", quantity: 2, location: .fridge, expiryDate: "2026-10-15"),
        ])
    }

    private struct Setup {
        let editor: InventoryEditorModel
        let list: InventoryListModel
        let server: EverShelfFixtureServer
    }

    private func open(_ id: String, server: EverShelfFixtureServer? = nil) async throws -> Setup {
        let server = server ?? makeServer()
        let list = InventoryListModel(space: .fridge, client: EverShelfClient(caller: server), calendar: calendar)
        await list.load()
        let item = try #require(list.displayItem(id: id))
        let editor = InventoryEditorModel(item: item, list: list)
        editor.preparedRetry = .milliseconds(10)
        editor.preparedDeadline = .milliseconds(200)
        return Setup(editor: editor, list: list, server: server)
    }

    private func sleep(_ milliseconds: Int) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }

    // MARK: Derived

    @Test func batchesAndCopy() async throws {
        let setup = try await open("milk")
        let editor = setup.editor
        #expect(editor.itemId == "milk")
        #expect(editor.title == "Milk")
        #expect(editor.busy == nil && editor.error == nil && !editor.isFinished)
        #expect(editor.authority.name == "Milk")
        #expect(editor.calendar.today == calendar.today)

        let batches = editor.batches
        #expect(batches.map(\.quantity) == [3, 1])
        #expect(editor.multipleBatches)
        #expect(editor.heading(batches[0]) == "Expires Oct 20, 2026")
        #expect(editor.heading(batches[1]) == "No Expiration Date")
        #expect(editor.qualifier(batches[0]) == " expiring Oct 20, 2026")
        #expect(editor.qualifier(batches[1]) == " without an expiration date")
        #expect(editor.locationLine(batches[0]) == "In the Fridge")
        var prepared = batches[0]
        prepared.preparedFood = true
        #expect(editor.locationLine(prepared) == "In the Fridge · Prepared")
        #expect(!editor.isDisabled(batches[0]))
        #expect(!editor.dismissalBlocked)
    }

    @Test func singleBatchUsesTheItemName() async throws {
        let editor = try await open("jam").editor
        let batch = try #require(editor.batches.first)
        #expect(!editor.multipleBatches)
        #expect(editor.heading(batch) == "Jam")
        #expect(editor.qualifier(batch) == "")
    }

    @Test func authorityFallsBackToTheOpeningCard() async throws {
        let setup = try await open("jam")
        setup.server.rows.removeAll { $0.name == "Jam" }
        try await setup.list.refresh()
        #expect(setup.list.displayItem(id: "jam") == nil)
        #expect(setup.editor.authority.name == "Jam")
    }

    @Test func busyBlocksDismissalExceptForPrepared() {
        #expect(InventoryEditorModel.Busy.save("k").blocksDismissal)
        #expect(InventoryEditorModel.Busy.delete("k").blocksDismissal)
        #expect(!InventoryEditorModel.Busy.prepared("k").blocksDismissal)
    }

    // MARK: Drafts

    @Test func quantityDraftsClampAndHint() async throws {
        let editor = try await open("milk").editor
        let batch = editor.batches[0]
        #expect(editor.quantity(batch) == 3)
        #expect(editor.minimumQuantity(batch) == 1)

        editor.setQuantity(0, for: batch)
        #expect(editor.quantity(batch) == 1)
        editor.setQuantity(5000, for: batch)
        #expect(editor.quantity(batch) == 999)

        editor.setQuantity(5, for: batch)
        #expect(editor.quantityDelta(batch) == 2)
        #expect(editor.hasChanges(batch))
        #expect(editor.hint(batch) == "Saving adds 2 items to the fridge.")
        #expect(editor.quantityDrafts[batch.key] == 5)

        editor.setQuantity(2, for: batch)
        #expect(editor.hint(batch) == "Saving removes 1 item from the fridge.")

        editor.reportInvalidQuantity(max: 3)
        #expect(editor.error == "Enter a number from 1 to 3.")
        editor.reset(batch)
        #expect(editor.quantity(batch) == 3)
        #expect(editor.hint(batch) == nil)
        #expect(!editor.hasChanges(batch))
        #expect(editor.error == nil)
    }

    @Test func fractionalStockAllowsItsOwnMinimum() async throws {
        let editor = try await open("milk").editor
        var batch = editor.batches[1]
        batch.quantity = 0.5
        #expect(editor.minimumQuantity(batch) == 0.5)
        editor.setQuantity(0, for: batch)
        #expect(editor.quantity(batch) == 0.5)
    }

    @Test func expiryDrafts() async throws {
        let editor = try await open("milk").editor
        let batch = editor.batches[0]
        #expect(editor.expiry(batch) == "2026-10-20")
        editor.setExpiry("2026-11-01", for: batch)
        #expect(editor.expiry(batch) == "2026-11-01")
        #expect(editor.expiryDrafts[batch.key] == "2026-11-01")
        #expect(editor.hasChanges(batch))
        #expect(editor.hint(batch) == nil)
        editor.reset(batch)
        #expect(editor.expiry(batch) == "2026-10-20")
        #expect(editor.expiryDrafts.isEmpty)
    }

    @Test func reportInvalidQuantityFormatsTheMax() async throws {
        let editor = try await open("milk").editor
        editor.reportInvalidQuantity(max: 2.5)
        #expect(editor.error == "Enter a number from 1 to 2.5.")
    }

    // MARK: Save

    @Test func saveDecreaseRemovesSmallestRowsFirst() async throws {
        let setup = try await open("milk")
        let (editor, server) = (setup.editor, setup.server)
        let batch = editor.batches[0]
        editor.setQuantity(1, for: batch)
        await editor.save(batch)
        #expect(server.calls.suffix(3) == [
            "evershelf.delete_inventory inventory_id=2",
            "evershelf.delete_inventory inventory_id=1 quantity=1",
            "evershelf.list_inventory location=frigo",
        ])
        #expect(server.rows.filter { $0.name == "Milk" }.map(\.quantity) == [1, 1])
        #expect(setup.list.displayItem(id: "milk")?.quantity == 2)
        #expect(editor.isFinished)
        #expect(editor.busy == nil)
        #expect(editor.error == nil)
    }

    @Test func saveIncreaseRestocksTheBatch() async throws {
        let setup = try await open("milk")
        let (editor, server) = (setup.editor, setup.server)
        let batch = editor.batches[0]
        editor.setQuantity(5, for: batch)
        await editor.save(batch)
        #expect(server.calls.contains(
            "evershelf.add_scanned_item expiry_date=2026-10-20 inventory_prepared_food=false location=frigo name=Milk quantity=2 unit=pz vacuum_sealed=false"
        ))
        #expect(server.rows.first { $0.id == 1 }?.quantity == 4)
        #expect(setup.list.displayItem(id: "milk")?.quantity == 6)
        #expect(editor.isFinished)
    }

    @Test func saveExpiryMovesEveryUnit() async throws {
        let setup = try await open("milk")
        let (editor, server) = (setup.editor, setup.server)
        let batch = editor.batches[0]
        editor.setExpiry(" 2026-11-01 ", for: batch)
        await editor.save(batch)
        #expect(server.calls.filter { $0.hasPrefix("evershelf.update_inventory_item") } == [
            "evershelf.update_inventory_item expiry_date=2026-11-01 inventory_id=1",
            "evershelf.update_inventory_item expiry_date=2026-11-01 inventory_id=1",
            "evershelf.update_inventory_item expiry_date=2026-11-01 inventory_id=2",
        ])
        let milk = server.rows.filter { $0.name == "Milk" }
        #expect(milk.map(\.expiryDate) == [nil, "2026-11-01"])
        #expect(milk.map(\.quantity) == [1, 3])
        #expect(editor.isFinished)
    }

    @Test func clearingTheExpiryMergesIntoTheUndatedBatch() async throws {
        let setup = try await open("milk")
        let batch = setup.editor.batches[0]
        setup.editor.setExpiry("", for: batch)
        await setup.editor.save(batch)
        let milk = setup.server.rows.filter { $0.name == "Milk" }
        #expect(milk.map(\.id) == [3])
        #expect(milk.map(\.quantity) == [4])
    }

    @Test func saveDecreaseThenMoveTheRest() async throws {
        let setup = try await open("milk")
        let (editor, server) = (setup.editor, setup.server)
        let batch = editor.batches[0]
        editor.setQuantity(2, for: batch)
        editor.setExpiry("2026-11-01", for: batch)
        await editor.save(batch)
        #expect(server.calls.contains("evershelf.delete_inventory inventory_id=2"))
        #expect(server.calls.filter { $0.hasPrefix("evershelf.update_inventory_item") }.count == 2)
        #expect(server.rows.filter { $0.name == "Milk" && $0.expiryDate == "2026-11-01" }.map(\.quantity) == [2])
    }

    @Test func saveRejectsAMalformedDate() async throws {
        let setup = try await open("milk")
        let batch = setup.editor.batches[0]
        setup.editor.setExpiry("2026/11/01", for: batch)
        await setup.editor.save(batch)
        #expect(setup.editor.error == "Use YYYY-MM-DD or clear the date.")
        #expect(setup.server.calls.count == 1)
        #expect(!setup.editor.isFinished)
    }

    @Test func saveWithoutChangesDoesNothing() async throws {
        let setup = try await open("milk")
        await setup.editor.save(setup.editor.batches[0])
        #expect(setup.server.calls.count == 1)
        #expect(!setup.editor.isFinished)
        #expect(setup.editor.error == nil)
    }

    @Test func unaddressableBatchesAreReadOnly() async throws {
        let setup = try await open("milk")
        var batch = setup.editor.batches[0]
        batch.addressable = false
        #expect(setup.editor.isDisabled(batch))
        setup.editor.setQuantity(1, for: batch)
        await setup.editor.save(batch)
        await setup.editor.delete(batch)
        await setup.editor.togglePrepared(batch)
        #expect(setup.server.calls.count == 1)
    }

    @Test func increaseNeedsALocation() async throws {
        let stub = InventoryStubCaller()
        stub.responses["list_inventory"] = .object(["inventory": .array([
            .object(["inventory_id": .number(1), "name": .string("Mystery"), "quantity": .number(1)]),
        ])])
        let list = InventoryListModel(space: .allFood, client: EverShelfClient(caller: stub), calendar: calendar)
        await list.load()
        let item = try #require(list.displayItem(id: "mystery"))
        let editor = InventoryEditorModel(item: item, list: list)
        let batch = try #require(editor.batches.first)
        #expect(batch.locationPhrase == "library")
        editor.setQuantity(2, for: batch)
        await editor.save(batch)
        #expect(editor.error == "Home Assistant did not report a storage location for Mystery, so more cannot be added.")
        #expect(stub.calls.count == 1)
    }

    @Test func saveFailureShowsTheError() async throws {
        let setup = try await open("milk")
        setup.server.failing = ["evershelf.delete_inventory"]
        let batch = setup.editor.batches[0]
        setup.editor.setQuantity(1, for: batch)
        await setup.editor.save(batch)
        #expect(setup.editor.error == "EverShelf is unavailable")
        #expect(setup.editor.busy == nil)
        #expect(!setup.editor.isFinished)
        #expect(setup.editor.quantity(batch) == 1, "The draft is kept to retry")
    }

    @Test func refreshFailureAfterSaveIsReported() async throws {
        let setup = try await open("milk")
        setup.server.failing = ["evershelf.list_inventory"]
        let batch = setup.editor.batches[0]
        setup.editor.setQuantity(1, for: batch)
        await setup.editor.save(batch)
        #expect(setup.editor.isFinished)
        #expect(setup.editor.error == "EverShelf is unavailable")
    }

    @Test func saveIsBusyWhileRunning() async throws {
        let setup = try await open("milk")
        setup.server.latency = .milliseconds(600)
        let batch = setup.editor.batches[0]
        setup.editor.setQuantity(2, for: batch)
        let save = Task { await setup.editor.save(batch) }
        #expect(await eventually { setup.editor.busy != nil })
        #expect(setup.editor.busy == .save(batch.key))
        #expect(setup.editor.dismissalBlocked)
        #expect(setup.editor.isDisabled(batch))
        await setup.editor.save(batch)
        await setup.editor.delete(batch)
        await save.value
        #expect(setup.editor.busy == nil)
        #expect(setup.server.calls.filter { $0.hasPrefix("evershelf.delete_inventory") }.count == 1)
    }

    // MARK: Delete

    @Test func partialDeleteKeepsTheRestShown() async throws {
        let setup = try await open("milk")
        let (editor, server) = (setup.editor, setup.server)
        let dated = editor.batches[0]
        editor.setExpiry("2026-11-02", for: editor.batches[1])
        await editor.delete(dated, quantity: 1)
        #expect(server.calls.contains("evershelf.delete_inventory inventory_id=2"))
        #expect(!editor.isFinished)
        #expect(editor.error == nil)
        #expect(editor.batches.map(\.quantity) == [2, 1])
        #expect(editor.batches[0].rows == [InventoryBatch.Row(inventoryId: 1, quantity: 2)])
        #expect(editor.expiryDrafts.isEmpty)
        #expect(setup.list.displayItem(id: "milk")?.quantity == 3)
    }

    @Test func deletingAWholeBatchThenTheLastFinishes() async throws {
        let setup = try await open("milk")
        let (editor, server) = (setup.editor, setup.server)
        await editor.delete(editor.batches[0])
        #expect(server.calls.contains("evershelf.delete_inventory inventory_id=1"))
        #expect(server.calls.contains("evershelf.delete_inventory inventory_id=2"))
        #expect(!editor.isFinished)
        #expect(editor.batches.map(\.quantity) == [1])

        await editor.delete(editor.batches[0])
        #expect(editor.isFinished)
        #expect(server.rows.filter { $0.name == "Milk" }.isEmpty)
        #expect(setup.list.displayItem(id: "milk") == nil)
    }

    @Test func deletingEverythingFinishes() async throws {
        let setup = try await open("jam")
        await setup.editor.delete(setup.editor.batches[0], quantity: 5)
        #expect(setup.editor.isFinished)
        #expect(setup.server.calls.contains("evershelf.delete_inventory inventory_id=4"))
        #expect(setup.list.displayItem(id: "jam") == nil)
    }

    @Test func deleteFailureShowsTheError() async throws {
        let setup = try await open("milk")
        setup.server.failing = ["evershelf.delete_inventory"]
        await setup.editor.delete(setup.editor.batches[0])
        #expect(setup.editor.error == "EverShelf is unavailable")
        #expect(setup.editor.busy == nil)
        #expect(!setup.editor.isFinished)
        #expect(setup.editor.batches.map(\.quantity) == [3, 1])
    }

    // MARK: Prepared food

    // MARK: Prepared food drafts (one commit model, owner 2026-10-24)

    @Test func preparedFoodIsADraftUntilSave() async throws {
        let setup = try await open("soup")
        let (editor, server) = (setup.editor, setup.server)
        let batch = editor.batches[0]
        editor.togglePreparedDraft(batch, quantity: 1)
        #expect(!server.calls.contains { $0.contains("set_inventory_prepared_food") })
        #expect(editor.hasChanges(batch) && editor.batches.filter(editor.hasChanges).count == 1)
        #expect(editor.preparedHint(batch) == "Saving marks 1 as Prepared.")
        #expect(editor.showsPrepared(batch) == batch.preparedFood, "A partial change leaves the switch as it was")
        // A second tap drops it; Cancel (reset) drops it too.
        editor.togglePreparedDraft(batch)
        #expect(editor.preparedDrafts.isEmpty && editor.preparedHint(batch) == nil)
        editor.togglePreparedDraft(batch)
        #expect(editor.showsPrepared(batch), "A draft covering the whole batch flips the switch")
        #expect(editor.preparedHint(batch) == "Saving marks 2 as Prepared.")
        editor.reset(batch)
        #expect(editor.preparedDrafts.isEmpty)
        editor.togglePreparedDraft(batch, quantity: 0)
        #expect(editor.preparedDrafts.isEmpty, "Nothing to change")
    }

    @Test func savingAppliesPreparedFood() async throws {
        let setup = try await open("soup")
        let (editor, server) = (setup.editor, setup.server)
        editor.togglePreparedDraft(editor.batches[0], quantity: 1)
        await editor.savePrepared()
        #expect(server.calls.contains("evershelf.set_inventory_prepared_food inventory_id=5 prepared_food=true quantity=1"))
        #expect(editor.error == nil)
        #expect(editor.isFinished)
        #expect(editor.preparedDrafts.isEmpty)
        #expect(editor.batches.map(\.preparedFood) == [false, true])
        // And with nothing drafted it does nothing.
        let calls = server.calls.count
        await editor.savePrepared()
        #expect(server.calls.count == calls)
    }

    @Test func preparedFoodSavesAfterAnExpiryChange() async throws {
        let setup = try await open("soup")
        let (editor, server) = (setup.editor, setup.server)
        let batch = editor.batches[0]
        editor.setExpiry("2026-11-01", for: batch)
        editor.togglePreparedDraft(batch)
        #expect(editor.batches.filter(editor.hasChanges).count == 1)
        await editor.save(batch)
        await editor.savePrepared()
        #expect(editor.error == nil)
        #expect(server.calls.contains { $0.contains("set_inventory_prepared_food") && $0.contains("prepared_food=true") })
        #expect(editor.batches.allSatisfy { $0.preparedFood }, "Found again by its rows after the re-key: \(editor.batches.map { ($0.rows.map(\.inventoryId), $0.quantity, $0.preparedFood, $0.expiryDate) }) calls \(server.calls)")
    }

    @Test func aFailedPreparedSaveStaysOpen() async throws {
        let setup = try await open("soup")
        let editor = setup.editor
        setup.server.failing = ["evershelf.set_inventory_prepared_food"]
        editor.togglePreparedDraft(editor.batches[0])
        await editor.savePrepared()
        #expect(editor.error != nil)
        #expect(!editor.isFinished)
    }

    @Test func unaddressableBatchesTakeNoPreparedDraft() async throws {
        let setup = try await open("soup")
        var batch = setup.editor.batches[0]
        batch.addressable = false
        setup.editor.togglePreparedDraft(batch)
        #expect(setup.editor.preparedDrafts.isEmpty)
    }

    @Test func togglePreparedConfirms() async throws {
        let setup = try await open("soup")
        let (editor, server) = (setup.editor, setup.server)
        await editor.togglePrepared(editor.batches[0], quantity: 1)
        #expect(server.calls.contains("evershelf.set_inventory_prepared_food inventory_id=5 prepared_food=true quantity=1"))
        #expect(editor.error == nil)
        #expect(editor.busy == nil)
        #expect(editor.batches.map(\.preparedFood) == [false, true])
        #expect(editor.batches.map(\.quantity) == [1, 1])
        #expect(editor.batches.allSatisfy { $0.addressable })
        #expect(setup.list.displayItem(id: "soup")?.rows.count == 2)

        // And back: the prepared unit merges into the plain batch.
        let prepared = try #require(editor.batches.first { $0.preparedFood })
        await editor.togglePrepared(prepared)
        #expect(editor.error == nil)
        #expect(editor.batches.map(\.quantity) == [2])
        #expect(editor.batches.map(\.preparedFood) == [false])
    }

    @Test func togglePreparedShowsTheProjectionMeanwhile() async throws {
        let setup = try await open("soup")
        let editor = setup.editor
        setup.server.latency = .milliseconds(600)
        let batch = editor.batches[0]
        editor.setQuantity(1, for: batch)
        let toggle = Task { await editor.togglePrepared(batch) }
        #expect(await eventually { editor.busy != nil })
        #expect(editor.busy == .prepared(batch.key))
        #expect(!editor.dismissalBlocked)
        #expect(editor.quantityDrafts.isEmpty)
        #expect(editor.batches.map(\.preparedFood) == [true])
        #expect(editor.batches.map(\.quantity) == [2])
        #expect(!editor.batches[0].addressable)
        await toggle.value
        #expect(editor.busy == nil)
        #expect(editor.error == nil)
        #expect(editor.batches.map(\.preparedFood) == [true])
    }

    @Test func togglePreparedMutationFailure() async throws {
        let setup = try await open("soup")
        let editor = setup.editor
        setup.server.failing = ["evershelf.set_inventory_prepared_food"]
        await editor.togglePrepared(editor.batches[0], quantity: 1)
        #expect(editor.error == "EverShelf is unavailable")
        #expect(editor.busy == nil)
        #expect(editor.batches.map(\.quantity) == [2])
        #expect(editor.batches.map(\.preparedFood) == [false])
    }

    @Test func togglePreparedGivesUpWithoutConfirmation() async throws {
        let setup = try await open("soup")
        let editor = setup.editor
        setup.server.failing = ["evershelf.list_inventory"]
        let started = ContinuousClock.now
        await editor.togglePrepared(editor.batches[0], quantity: 1)
        #expect(ContinuousClock.now - started >= .milliseconds(200))
        #expect(editor.error == "Unable to update prepared food")
        #expect(editor.busy == nil)
        // The page never re-read, so the card shows what the list last had.
        #expect(editor.batches.map(\.quantity) == [2])
        #expect(setup.server.rows.filter { $0.name == "Soup" }.map(\.preparedFood) == [false, true])
    }

    @Test func togglePreparedBothFailing() async throws {
        let setup = try await open("soup")
        let editor = setup.editor
        setup.server.failing = ["evershelf.list_inventory", "evershelf.set_inventory_prepared_food"]
        await editor.togglePrepared(editor.batches[0])
        #expect(editor.error == "EverShelf is unavailable")
        #expect(editor.batches.map(\.quantity) == [2])
    }
}
