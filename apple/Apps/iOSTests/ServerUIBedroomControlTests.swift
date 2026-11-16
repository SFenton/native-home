@testable import HassCore
import HassDemoHouse
import HassDesign
import Observation
import UIKit
import XCTest
@testable import HassUI

// MARK: - Hosted bedroom atoms (synthetic only)

@MainActor
final class ServerUIBedroomControlTests: DemoHouseTestCase {
    /// Every test here shows renderer windows. A window left tracked keeps its renderer, observers and pending tasks alive
    /// under the next test, which is how the add-alarm journey failed once in a 183-test run and passed alone.
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    func testMirroredRowsReplaceOnlyTheAuthoredBedModalAndHonorDraftExitAcrossFamilies() throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678), CGSize(width: 820, height: 1180)] {
            for protected in [false, true] {
                let store = EntityStore()
                store.replaceAll(BedroomFixtures.states(.default), freshness: .live)
                let caller = LoggingResponder(BedroomGalleryRecorder(store: store))
                let renderer = try UKServerUIRenderer(publication: linkedPublication(protected: protected),
                    context: UKContext(store: store, caller: caller), backdrop: ServerUIRendererFixture.backdrop(),
                    canEditBedroom: true)
                var failures: [UKServerUIRendererError] = []
                renderer.onError = { failures.append($0) }
                let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
                defer { window.isHidden = true }
                let root = try ServerUIRendererFixture.root(renderer)
                renderer.activate(.present(modalId: "modal-swatch", arguments: .init(), ifPresented: .reject), from: root)
                HostedPage.wait(0.4)
                let original = try XCTUnwrap(renderer.modal?.topViewController as? UKServerUIPage)
                if protected {
                    let draft = try XCTUnwrap(original.bedroomDrafts["protected-editor"])
                    draft.update { if case .bed(var value) = $0 { value.time = "09:17"; $0 = .bed(value) } }
                }
                let list = try XCTUnwrap(original.nodes["linked-schedule"]?.view as? UKServerUICollectionView)
                let nativeRows = list.rows.values.compactMap { $0 as? UKBedroomRow }
                XCTAssertFalse(nativeRows.isEmpty)
                nativeRows.forEach(assertAlarmCardGeometry)
                let collection = try XCTUnwrap(renderer.recordCollection("authored-wake.alarms"))
                let record = try XCTUnwrap(collection.records.first {
                    if case .bedroom(let row, _) = $0 { row.linked != nil } else { false }
                })
                guard case .bedroom(let alarm, let source) = record,
                      case .linkedBed(let side) = try source.alarms.route(for: alarm) else {
                    return XCTFail("Expected a mirrored alarm with a real originating bed.")
                }
                let destination = "linked-" + side.rawValue
                let handoff = ServerUICompositionDocument.Action.present(modalId: destination, arguments: .init(), ifPresented: .replace)
                XCTAssertTrue(HostedPage.until { renderer.isEnabled(handoff, from: original) })
                let row = try XCTUnwrap(list.rows[record.id])
                let link = try XCTUnwrap(HostedPage.descendants(of: row).compactMap { $0 as? UIButton }.first {
                    $0.accessibilityIdentifier?.hasSuffix(".linked-editor") == true
                })
                XCTAssertEqual(link.configuration?.title, "Open Linked-Device Alarm Editor")
                XCTAssertGreaterThanOrEqual(link.bounds.height, 44)
                XCTAssertGreaterThanOrEqual(row.bounds.height, link.frame.maxY)
                link.sendActions(for: .touchUpInside)
                if protected {
                    XCTAssertTrue(HostedPage.until { FeatureHost.alert(on: renderer) != nil })
                    XCTAssertTrue(renderer.modal?.topViewController === original)
                    let alert = try XCTUnwrap(FeatureHost.alert(on: renderer))
                    XCTAssertTrue(FeatureHost.answer(alert, DiscardChangesCopy.discard, dismissing: false))
                }
                XCTAssertTrue(HostedPage.until {
                    guard let page = renderer.modal?.topViewController as? UKServerUIPage else { return false }
                    return page.definition.id == destination && renderer.isEnabled(.dismiss(scope: .currentModal), from: page)
                })
                XCTAssertEqual(renderer.navigation.snapshot.presentations.count, 1)
                XCTAssertEqual(renderer.navigation.snapshot.presentations.last?.modalID, destination)
                XCTAssertEqual((renderer.modal?.topViewController as? UKServerUIPage)?.definition.id, destination)
                XCTAssertEqual(renderer.navigation.snapshot.stacks[root.root]?.count, 1, "The handoff must not push onto the underlying page.")
                XCTAssertTrue(caller.calls.isEmpty, "Opening the linked schedule must not change its alarm or wake link.")
                XCTAssertTrue(source.session.editors.isEmpty)
                XCTAssertTrue(failures.isEmpty, "\(failures)")
            }
        }
    }

    private func linkedPublication(protected: Bool, holdExplanation: Bool = false, episode: Bool = false) throws -> ServerUICompositionPublication {
        var json = try ServerUIRendererFixture.authoredBedroom()
        var modals = try XCTUnwrap(json["document"]?["modals"]?.array)
        guard case .object(var schedule) = modals[0] else { throw ServerUIRecordFailure.invalidValue }
        let links: [JSONValue] = BedSide.allCases.map { side in
            .object(["side": .string(side.rawValue), "label": "Open Linked-Device Alarm Editor",
                "action": .object(["type": "present", "modalId": .string("linked-" + side.rawValue),
                                  "arguments": .object([:]), "ifPresented": "replace"])])
        }
        var components: [JSONValue] = [.object(["id": "wake-summary", "type": "bedroom-control", "title": "Wake Status",
            "layout": .object(["span": .number(1)]), "props": .object(["control": "wake-summary",
                "sourceId": "authored-wake-source", "label": "Wake Status", "unavailableText": "Setup · Unavailable"])]),
            .object(["id": "linked-schedule", "type": "collection", "title": "Wake Alarms",
            "layout": .object(["span": .number(1)]), "props": .object(["providerId": "authored-wake.alarms", "template": "rows",
                "loadingText": "Loading", "emptyText": "No alarms", "bedroomLinks": .array(links)])])]
        var sources = try XCTUnwrap(json["document"]?["dataSources"]?.array)
        if episode {
            components.insert(.object(["id": "wake-episode", "type": "bedroom-control", "title": "Current Wake",
                "layout": .object(["span": .number(1)]), "props": .object(["control": "wake-stop",
                    "sourceId": "authored-wake-source", "label": "End This Wake", "unavailableText": "Unavailable",
                    "episode": .object(["heading": "Wake In Progress", "detail": "End this room's current wake.",
                                        "pendingLabel": "Ending Wake"])])]), at: 1)
        }
        if holdExplanation {
            components.append(.object(["id": "wake-hold", "type": "bedroom-control", "title": "Hold",
                "layout": .object(["span": .number(1)]), "props": .object(["control": "wake-hold",
                    "sourceId": "authored-wake-source", "label": "Post-Wake Hold Time", "unavailableText": "Unavailable",
                    "showsExplanation": .bool(true), "options": .array(WakeLight.holdMinutes.map {
                        .object(["value": .string(String($0)), "label": .string(WakeLight.durationLabel($0))])
                    })])]))
        }
        if protected {
            sources.append(.object(["id": "protected-editor", "kind": "model", "model": "bedroom-provider@1",
                "inputs": .object(["providerId": "authored-left.new-editor", "kind": "bed-alarm-draft"])]))
            components.append(.object(["id": "protected-time", "type": "bedroom-control", "title": "Time",
                "layout": .object(["span": .number(1)]), "props": .object(["control": "alarm-time", "sourceId": "protected-editor",
                    "label": "Time", "unavailableText": "Unavailable"])]))
        }
        schedule["components"] = .array(components); modals[0] = .object(schedule)
        for side in BedSide.allCases {
            var destination = schedule
            destination["id"] = .string("linked-" + side.rawValue)
            destination["title"] = "Linked Bed"
            destination["components"] = .array([.object(["id": .string("linked-copy-" + side.rawValue), "type": "text",
                "title": "Linked Bed", "layout": .object(["span": .number(1)]),
                "props": .object(["value": .object(["type": "literal", "value": .string(side.rawValue)]),
                                  "style": "body", "unavailableText": "Unavailable"])])])
            modals.append(.object(destination))
        }
        json = try ServerUIRendererFixture.changing(json, path: "/document/modals", to: .array(modals))
        json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources", to: .array(sources))
        var capabilities = try XCTUnwrap(json["capabilities"]?.array).compactMap(\.string)
        capabilities += ["sh.collection@1", "sh.bedroom-collection-links@1", "sh.modal-handoff@1", "sh.wake-summary@1"]
        if protected { capabilities.append("sh.alarm-time@1") }
        if holdExplanation { capabilities += ["sh.wake-hold@1", "sh.wake-hold-explanation@1"] }
        if episode { capabilities += ["sh.wake-stop@1", "sh.wake-episode@1"] }
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        return try ServerUIRendererFixture.publication(json)
    }

    func testAddAlarmUsesAuthoredRouteLockedDayAndCanonicalCardsAcrossFamilies() throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678), CGSize(width: 820, height: 1180)] {
            for available in [false, true] {
                let store = EntityStore()
                store.replaceAll(BedroomFixtures.states(.default), freshness: .live)
                let caller = LoggingResponder(BedroomGalleryRecorder(store: store))
                let renderer = try UKServerUIRenderer(publication: editorPublication(routed: true),
                    context: UKContext(store: store, caller: caller), backdrop: ServerUIRendererFixture.backdrop(),
                    canEditBedroom: true)
                let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
                defer { HostedPage.hideTracked(); window.isHidden = true }
                let root = try ServerUIRendererFixture.root(renderer)
                let source = try XCTUnwrap(renderer.bindings.bedroomRegistry?.sources["authored-left"])
                XCTAssertTrue(source.session.editors.isEmpty)
                let list = try XCTUnwrap(root.nodes["alarm-list"]?.view as? UKServerUICollectionView)
                XCTAssertTrue(HostedPage.until { !list.rows.isEmpty })
                XCTAssertTrue(list.rows.values.allSatisfy { $0 is UKBedroomRow })
                list.rows.values.compactMap { $0 as? UKBedroomRow }.forEach(assertAlarmCardGeometry)
                XCTAssertTrue(HostedPage.descendants(of: list).allSatisfy { !($0 is UKModuleRowBackgroundView) })
                let atom = try XCTUnwrap(root.nodes["alarm-add"]?.view)
                let button = try XCTUnwrap(HostedPage.descendants(of: atom).compactMap { $0 as? UKPrimaryButton }.first)
                if !available {
                    store.apply([.init(entityId: source.session.descriptor.environment.scheduleEntityId, state: "unavailable")])
                    XCTAssertTrue(HostedPage.until { !source.alarms.canAdd })
                }
                XCTAssertTrue(HostedPage.until { button.isEnabled == available }, "The add button follows the schedule and the busy state")
                XCTAssertEqual(button.isEnabled, available)
                XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
                XCTAssertEqual(button.accessibilityLabel, "Add Alarm")
                guard available else { continue }
                button.sendActions(for: .touchUpInside)
                XCTAssertTrue(HostedPage.until {
                    (renderer.stacks[renderer.navigation.snapshot.selection]?.topViewController as? UKServerUIPage)?.definition.id == "alarm-editor"
                })
                let page = try XCTUnwrap(renderer.stacks[renderer.navigation.snapshot.selection]?.topViewController as? UKServerUIPage)
                XCTAssertEqual(page.definition.id, "alarm-editor")
                // The draft opens when the page builds its components, which follows the push by a layout pass.
                XCTAssertTrue(HostedPage.until { page.bedroomDrafts["editor-source"] != nil }, "The editor page opens its draft once built")
                let draft = try XCTUnwrap(page.bedroomDrafts["editor-source"])
                guard case .bed(let value) = draft.value else { return XCTFail("Expected a bed alarm draft") }
                XCTAssertEqual(value.lockedDay, .monday)
                XCTAssertTrue(try XCTUnwrap(page.nodes["editor-days"]?.view).isHidden,
                              "A locked weekday must collapse the entire atom, not leave a layout gap.")
                XCTAssertTrue(caller.calls.isEmpty, "Opening an editor must not mutate Home Assistant.")
                draft.discard()
            }
        }
    }

    private func assertAlarmCardGeometry(_ row: UKBedroomRow) {
        XCTAssertGreaterThanOrEqual(row.bounds.height, 44, "A native alarm card must not collapse in the manual column.")
        XCTAssertGreaterThanOrEqual(row.bounds.height + 0.5, row.gridHeight(forWidth: row.bounds.width))
        for label in HostedPage.descendants(of: row).compactMap({ $0 as? UILabel })
            where !label.isHidden && !(label.text ?? "").isEmpty {
            XCTAssertGreaterThan(label.bounds.height, 0)
            XCTAssertTrue(row.bounds.insetBy(dx: -0.5, dy: -0.5).contains(label.convert(label.bounds, to: row)),
                          "The alarm's visible text must remain inside its card.")
        }
    }

    func testWakeSummaryUsesCanonicalModalCopyAndTracksEntityUpdatesAcrossFamilies() throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678), CGSize(width: 820, height: 1180)] {
            let store = EntityStore()
            store.replaceAll(BedroomFixtures.states(.default), freshness: .live)
            let caller = LoggingResponder(BedroomGalleryRecorder(store: store))
            let renderer = try UKServerUIRenderer(publication: linkedPublication(protected: false, holdExplanation: true),
                context: UKContext(store: store, caller: caller), backdrop: ServerUIRendererFixture.backdrop(),
                canEditBedroom: true)
            let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
            defer { window.isHidden = true }
            let root = try ServerUIRendererFixture.root(renderer)
            renderer.activate(.present(modalId: "modal-swatch", arguments: .init(), ifPresented: .reject), from: root)
            XCTAssertTrue(HostedPage.until { renderer.modal?.topViewController is UKServerUIPage })
            let page = try XCTUnwrap(renderer.modal?.topViewController as? UKServerUIPage)
            let view = try XCTUnwrap(page.nodes["wake-summary"]?.view)
            let label = try XCTUnwrap(HostedPage.descendants(of: view).compactMap { $0 as? UILabel }.first)
            guard case .wake(let wake) = renderer.bindings.bedroom("authored-wake-source") else { return XCTFail("Missing wake source") }
            XCTAssertEqual(label.text, WakeLight.subtitle(wake.snapshot, modal: true))
            let hold = try XCTUnwrap(page.nodes["wake-hold"]?.view)
            XCTAssertTrue(HostedPage.labels(in: hold).contains(WakeLight.postWakeHoldExplanation(contractVersion: 6)))
            let note = try XCTUnwrap(HostedPage.descendants(of: hold).compactMap { $0 as? UILabel }.first {
                $0.text == WakeLight.postWakeHoldExplanation(contractVersion: 6)
            })
            XCTAssertTrue(HostedPage.until { note.bounds.width > 0 && note.bounds.height > 0 })
            XCTAssertEqual(note.bounds.height,
                           note.sizeThatFits(CGSize(width: note.bounds.width, height: .greatestFiniteMagnitude)).height,
                           accuracy: 0.01, "Whole-point rounding must not shift the footnote's baseline under the pinned glass bar.")
            let selected = try XCTUnwrap(HostedPage.descendants(of: hold).compactMap { $0 as? UKChipButton }.first {
                $0.accessibilityTraits.contains(.selected)
            })
            selected.sendActions(for: .touchUpInside)
            HostedPage.wait(0.1)
            XCTAssertTrue(caller.calls.isEmpty, "Selecting the current default must not send a redundant command.")
            var state = try XCTUnwrap(store.value(wake.config.statusEntityId))
            state.attributes["alarms"] = .array([])
            state.attributes["contract_version"] = .number(5)
            store.apply([state])
            XCTAssertTrue(HostedPage.until { label.text == "No Active Wake-Light Alarms" })
            XCTAssertTrue(HostedPage.until {
                HostedPage.labels(in: hold).contains(WakeLight.postWakeHoldExplanation(contractVersion: 5))
            })
            store.apply([.init(entityId: state.entityId, state: "unavailable")])
            XCTAssertTrue(HostedPage.until { label.text == "Setup · Unavailable" })
            XCTAssertTrue(caller.calls.isEmpty)
        }
    }

    func testWakeEpisodeUsesAuthoredCopyAndCurrentAvailabilityThenCollapsesAfterStoppingAcrossFamilies() throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678), CGSize(width: 820, height: 1180)] {
            let store = EntityStore()
            store.replaceAll(BedroomFixtures.states(.waking), freshness: .live)
            let caller = LoggingResponder(BedroomGalleryRecorder(store: store))
            let renderer = try UKServerUIRenderer(publication: linkedPublication(protected: false, episode: true),
                context: UKContext(store: store, caller: caller), backdrop: ServerUIRendererFixture.backdrop(),
                canEditBedroom: false)
            let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
            defer { window.isHidden = true }
            let root = try ServerUIRendererFixture.root(renderer)
            renderer.activate(.present(modalId: "modal-swatch", arguments: .init(), ifPresented: .reject), from: root)
            XCTAssertTrue(HostedPage.until { renderer.modal?.topViewController is UKServerUIPage })
            let page = try XCTUnwrap(renderer.modal?.topViewController as? UKServerUIPage)
            let atom = try XCTUnwrap(page.nodes["wake-episode"]?.view)
            let button = try XCTUnwrap(HostedPage.descendants(of: atom).compactMap { $0 as? UKFilledButton }.first)
            XCTAssertTrue(HostedPage.until { button.bounds.height >= 44 })
            XCTAssertEqual(button.accessibilityLabel, "End This Wake")
            XCTAssertTrue(button.isEnabled, "Stopping an episode must not require alarm-editing privileges.")
            XCTAssertTrue(HostedPage.labels(in: atom).contains("Wake In Progress"))
            XCTAssertTrue(HostedPage.labels(in: atom).contains("End this room's current wake."))
            guard case .wake(let wake) = renderer.bindings.bedroom("authored-wake-source") else { return XCTFail("Missing wake source") }
            let occurrence = try XCTUnwrap(wake.snapshot.activeOccurrences.first)
            let alarm = try XCTUnwrap(wake.snapshot.alarms.first { $0.id == occurrence.alarmId })
            XCTAssertTrue(HostedPage.labels(in: atom).contains("\(alarm.label) · \(WakeLight.displayTime(occurrence.wakeAt))"))
            let header = try XCTUnwrap(HostedPage.descendants(of: atom).compactMap { $0 as? UILabel }.first {
                $0.text == "Wake In Progress"
            })
            XCTAssertTrue(header.accessibilityTraits.contains(.header))
            var state = try XCTUnwrap(store.value(wake.config.statusEntityId))
            let activeState = state.state
            state.state = "unavailable"
            store.apply([state])
            XCTAssertTrue(HostedPage.until { !button.isEnabled })
            button.sendActions(for: .touchUpInside)
            HostedPage.wait(0.1)
            XCTAssertTrue(caller.calls.isEmpty, "An outdated tap must not stop an unavailable episode.")
            state.state = activeState
            store.apply([state])
            XCTAssertTrue(HostedPage.until { button.isEnabled })
            button.sendActions(for: .touchUpInside)
            XCTAssertTrue(HostedPage.until { atom.isHidden && !wake.stopping && wake.live.activeOccurrences.isEmpty })
            XCTAssertEqual(caller.calls, ["wake_light.command"])
            XCTAssertEqual(caller.data.first?["operation"] as? String, "end_episode")
            XCTAssertEqual(caller.data.first?["episode_ref"] as? String, "episode-1")
        }
    }

    func testRetiredDraftRemainsOwnedUntilDiscardThenReleasesAutomatically() async throws {
        let store = EntityStore()
        store.replaceAll(BedroomFixtures.states(.default), freshness: .live)
        let renderer = try UKServerUIRenderer(publication: editorPublication(),
            context: UKContext(store: store, caller: LoggingResponder(BedroomGalleryRecorder(store: store))),
            backdrop: ServerUIRendererFixture.backdrop(), canEditBedroom: true)
        let window = HostedPage.show(renderer, size: HostedPage.inScene(CGSize(width: 466, height: 678)))
        defer { window.isHidden = true }
        let session = try XCTUnwrap(renderer.bindings.bedroomRegistry?.sources["authored-left"]?.session)
        let draft = try XCTUnwrap(session.editors.values.first)
        draft.update { if case .bed(var value) = $0 { value.time = "09:17"; $0 = .bed(value) } }
        session.retire(draft)
        XCTAssertFalse(session.editors.isEmpty, "Retirement cannot abandon a protected draft.")
        let released = expectation(description: "Settled editor released")
        withObservationTracking { _ = session.editors } onChange: {
            Task { @MainActor in if session.editors.isEmpty { released.fulfill() } }
        }
        draft.discard()
        await fulfillment(of: [released], timeout: 2)
        XCTAssertTrue(session.editors.isEmpty)
    }

    func testEditorFactoriesValidateOwnersWithoutCreatingDraftsAndRetainImmutableSelections() throws {
        let store = EntityStore()
        store.replaceAll(BedroomFixtures.states(.default), freshness: .live)
        let caller = LoggingResponder(BedroomGalleryRecorder(store: store))
        let publication = try editorPublication()
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: store, caller: caller),
                                          backdrop: ServerUIRendererFixture.backdrop(), canEditBedroom: true)
        let registry = try XCTUnwrap(host.bindings.bedroomRegistry)
        let source = try XCTUnwrap(registry.sources["authored-left"])
        XCTAssertTrue(source.session.editors.isEmpty, "Admission must not open an alarm or own an unsaved draft.")
        let collection = try XCTUnwrap(registry.collections["authored-left.alarms"])
        let row = try XCTUnwrap(collection.records.first)
        try collection.select(row)
        let editor = try XCTUnwrap(registry.editors["authored-left.editor"])
        let draft = try editor.open(visitID: "selected")
        guard case .bedroom(let expected, _) = row, case .bed(let alarm) = expected.alarm,
              case .bed(let value) = draft.value else { return XCTFail("Missing bed row and draft") }
        XCTAssertEqual(value.editingId, alarm.id)
        store.apply([.init(entityId: source.session.descriptor.environment.scheduleEntityId, state: "ok",
                           attributes: ["left": .object([:]), "right": .object([:])])])
        XCTAssertThrowsError(try collection.select(row))
        XCTAssertThrowsError(try editor.open(visitID: "stale"))
        XCTAssertEqual(draft.value, .bed(value), "A live update must not rewrite the opened editor.")
        let mismatch = ServerUICompositionDocument.Source.bedroom(id: "bad", providerId: "authored-left.editor", kind: .wakeDraft)
        XCTAssertThrowsError(try registry.validate([mismatch], supplied: [:]))
        let missing = ServerUICompositionDocument.Source.bedroom(id: "bad", providerId: "unregistered.editor", kind: .bedDraft)
        XCTAssertThrowsError(try registry.validate([missing], supplied: [:]))
    }

    func testAuthoredAlarmEditorKeepsDraftAndAccessibleTimeFieldAndRequiresDiscardAcrossFamilies() async throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678), CGSize(width: 820, height: 1180)] {
            let store = EntityStore()
            store.replaceAll(BedroomFixtures.states(.default), freshness: .live)
            let caller = LoggingResponder(BedroomGalleryRecorder(store: store))
            let publication = try editorPublication()
            let renderer = try UKServerUIRenderer(publication: publication, context: UKContext(store: store, caller: caller),
                backdrop: ServerUIRendererFixture.backdrop(), canEditBedroom: true)
            let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
            defer { window.isHidden = true }
            let page = try ServerUIRendererFixture.root(renderer)
            let draft = try XCTUnwrap(page.bedroomDrafts["editor-source"])
            let atom = try XCTUnwrap(page.nodes["editor-time"]?.view)
            let picker = try XCTUnwrap(HostedPage.descendants(of: atom).compactMap { $0 as? UIDatePicker }.first)
            XCTAssertNotNil(picker.accessibilityLabel)
            XCTAssertGreaterThanOrEqual(atom.bounds.height, 44)
            XCTAssertFalse(renderer.nativeExitGate?.blocksExit(page) == true)
            draft.update { if case .bed(var value) = $0 { value.time = "09:17"; $0 = .bed(value) } }
            XCTAssertTrue(renderer.nativeExitGate?.blocksExit(page) == true)
            try renderer.validateUpdate(publication)
            XCTAssertTrue(page.bedroomDrafts["editor-source"] === draft)
            var exited = false
            let exit = expectation(description: "Confirmed alarm discard at \(size.width) points")
            renderer.requestNativeExit(from: page) { exited = true; exit.fulfill() }
            await HostedPage.pump(passes: 5)
            XCTAssertFalse(exited)
            let alert = try XCTUnwrap(FeatureHost.alert(on: renderer))
            XCTAssertTrue(FeatureHost.answer(alert, DiscardChangesCopy.discard, dismissing: false))
            await fulfillment(of: [exit], timeout: 2)
            XCTAssertTrue(exited)
            XCTAssertTrue(draft.completed)
            XCTAssertTrue(caller.calls.isEmpty)
        }
    }

    func testWakeEditorUsesAuthoredFieldsStableTitleAndOneGuardedBackAcrossFamilies() throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678), CGSize(width: 820, height: 1180)] {
            for isNew in [false, true] {
                let store = EntityStore()
                store.replaceAll(BedroomFixtures.states(.default), freshness: .live)
                let caller = LoggingResponder(BedroomGalleryRecorder(store: store))
                let renderer = try UKServerUIRenderer(publication: wakeEditorPublication(isNew: isNew),
                    context: UKContext(store: store, caller: caller), backdrop: ServerUIRendererFixture.backdrop(), canEditBedroom: true)
                var failures: [UKServerUIRendererError] = []
                renderer.onError = { failures.append($0) }
                let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
                defer { window.isHidden = true }
                let root = try ServerUIRendererFixture.root(renderer)
                if !isNew { try selectWeeklyWake(renderer) }
                renderer.activate(.push(.init(pageId: "wake-editor", arguments: .init(), origin: .sender, duplicate: .reuseNearest)), from: root)
                XCTAssertTrue(HostedPage.until {
                    (renderer.stacks[root.root]?.topViewController as? UKServerUIPage)?.bedroomDrafts["wake-editor-source"] != nil
                }, "\(failures)")
                let page = try XCTUnwrap(renderer.stacks[root.root]?.topViewController as? UKServerUIPage)
                let draft = try XCTUnwrap(page.bedroomDrafts["wake-editor-source"])
                let openedTitle = draft.presentationTitle
                XCTAssertEqual(page.title, openedTitle)
                let kind = try XCTUnwrap(page.nodes["editor-kind"]?.view)
                XCTAssertTrue(HostedPage.labels(in: kind).contains("Alarm Type"))
                let name = try XCTUnwrap(page.nodes["editor-name"]?.view)
                XCTAssertTrue(HostedPage.labels(in: name).contains("Alarm Name"))
                let field = try XCTUnwrap(HostedPage.descendants(of: name).compactMap { $0 as? UKOutlinedTextField }.first)
                let text = try XCTUnwrap(HostedPage.descendants(of: field).compactMap { $0 as? UITextView }.first)
                XCTAssertEqual(text.accessibilityLabel, "Alarm Name")
                let days = try XCTUnwrap(page.nodes["editor-days"]?.view)
                let chips = HostedPage.descendants(of: days).compactMap { $0 as? UKChipButton }
                XCTAssertEqual(chips.map(\.accessibilityLabel), Weekday.allCases.map { Optional($0.label) })
                let date = try XCTUnwrap(page.nodes["editor-date"]?.view)
                XCTAssertFalse(days.isHidden, "The native editor starts new alarms scheduled on workdays.")
                XCTAssertTrue(date.isHidden)
                let targets: [UIView] = chips
                XCTAssertTrue(HostedPage.until { targets.allSatisfy { $0.bounds.width >= 44 && $0.bounds.height >= 44 } })
                for target in targets {
                    XCTAssertGreaterThanOrEqual(target.bounds.width, 44)
                    XCTAssertGreaterThanOrEqual(target.bounds.height, 44)
                }
                XCTAssertTrue(HostedPage.labels(in: days).contains("Mon"))
                XCTAssertFalse(try XCTUnwrap(page.nodes["editor-errors"]?.view).isHidden)
                XCTAssertTrue(try XCTUnwrap(page.nodes["editor-reload"]?.view).isHidden)
                XCTAssertEqual(try XCTUnwrap(page.nodes["editor-delete"]?.view).isHidden, isNew)
                XCTAssertEqual(try XCTUnwrap(page.nodes["editor-bed"]?.view).isHidden, !isNew)
                let ramp = try XCTUnwrap(page.nodes["editor-ramp"]?.view)
                let enabled = try XCTUnwrap(page.nodes["editor-enabled"]?.view)
                XCTAssertLessThan(ramp.convert(ramp.bounds, to: page.view).minY, enabled.convert(enabled.bounds, to: page.view).minY)
                field.onChange("Unsaved alarm name")
                XCTAssertTrue(HostedPage.until { draft.dirty })
                XCTAssertEqual(page.title, openedTitle, "Typing must not rename the navigation title.")
                let back = try XCTUnwrap(page.navigationItem.leftBarButtonItems?.first)
                XCTAssertEqual(back.accessibilityLabel, "Back")
                XCTAssertTrue(back.isEnabled && page.navigationItem.hidesBackButton)
                try XCTUnwrap(back.primaryAction).performWithSender(back, target: nil)
                XCTAssertTrue(HostedPage.until { FeatureHost.alert(on: renderer) != nil })
                let alert = try XCTUnwrap(FeatureHost.alert(on: renderer))
                XCTAssertTrue(FeatureHost.answer(alert, DiscardChangesCopy.discard, dismissing: false))
                XCTAssertTrue(HostedPage.until { renderer.stacks[root.root]?.topViewController === root })
                XCTAssertTrue(draft.completed)
                XCTAssertTrue(caller.calls.isEmpty, "Editing and discarding must not send a live command.")
            }
        }
    }

    func testWakeEditorSharesValidationAndCanReloadAnExternallyChangedAlarmAcrossFamilies() throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678), CGSize(width: 820, height: 1180)] {
            let store = EntityStore()
            store.replaceAll(BedroomFixtures.states(.default), freshness: .live)
            let caller = LoggingResponder(BedroomGalleryRecorder(store: store))
            let renderer = try UKServerUIRenderer(publication: wakeEditorPublication(isNew: false),
                context: UKContext(store: store, caller: caller), backdrop: ServerUIRendererFixture.backdrop(), canEditBedroom: true)
            var failures: [UKServerUIRendererError] = []
            renderer.onError = { failures.append($0) }
            let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
            defer { window.isHidden = true }
            let root = try ServerUIRendererFixture.root(renderer)
            try selectWeeklyWake(renderer)
            renderer.activate(.push(.init(pageId: "wake-editor", arguments: .init(), origin: .sender, duplicate: .reuseNearest)), from: root)
            XCTAssertTrue(HostedPage.until {
                (renderer.stacks[root.root]?.topViewController as? UKServerUIPage)?.bedroomDrafts["wake-editor-source"] != nil
            }, "\(failures)")
            let page = try XCTUnwrap(renderer.stacks[root.root]?.topViewController as? UKServerUIPage)
            let draft = try XCTUnwrap(page.bedroomDrafts["wake-editor-source"])
            let name = try XCTUnwrap(page.nodes["editor-name"]?.view)
            let field = try XCTUnwrap(HostedPage.descendants(of: name).compactMap { $0 as? UKOutlinedTextField }.first)
            field.onChange("")
            XCTAssertFalse(draft.problems.isEmpty)
            XCTAssertTrue(HostedPage.until {
                draft.problems.allSatisfy { HostedPage.labels(in: page.view).contains($0) }
            })
            for problem in draft.problems {
                XCTAssertEqual(HostedPage.labels(in: page.view).filter { $0 == problem }.count, 1,
                               "Shared feedback must not be repeated under every field.")
            }
            XCTAssertFalse(draft.canSave)
            field.onChange("My edited alarm")
            guard case .wake(let alarm) = draft.value,
                  case .wake(let wake) = renderer.bindings.bedroom("authored-wake-source") else { return XCTFail("Missing wake draft") }
            var status = try XCTUnwrap(store.value(wake.config.statusEntityId))
            var alarms = try XCTUnwrap(status.attributes["alarms"]?.array)
            let index = try XCTUnwrap(alarms.firstIndex { $0["id"]?.string == alarm.id })
            guard case .object(var latest) = alarms[index] else { return XCTFail("Missing alarm") }
            latest["label"] = "Latest server alarm"
            latest["revision"] = .number(Double(alarm.revision + 1))
            alarms[index] = .object(latest); status.attributes["alarms"] = .array(alarms)
            store.apply([status])
            let reloadAtom = try XCTUnwrap(page.nodes["editor-reload"]?.view)
            XCTAssertTrue(HostedPage.until { !reloadAtom.isHidden })
            XCTAssertFalse(draft.canSave)
            let reload = try XCTUnwrap(HostedPage.descendants(of: reloadAtom).compactMap { $0 as? UIButton }.first)
            XCTAssertEqual(reload.configuration?.title, "Open Latest Alarm, Replace Draft")
            reload.sendActions(for: .touchUpInside)
            XCTAssertTrue(HostedPage.until { page.title == "Latest server alarm" && reloadAtom.isHidden })
            XCTAssertFalse(draft.dirty)
            XCTAssertTrue(draft.problems.isEmpty)
            XCTAssertTrue(caller.calls.isEmpty, "Reload reads the same entity store without issuing a command.")
        }
    }

    func testUnchangedNewAlarmBackDoesNotPromptAndReleasesPublicationOwnershipAcrossFamilies() throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678), CGSize(width: 820, height: 1180)] {
            for (wake, inModal) in [(false, false), (true, false), (false, true), (true, true)] {
                let store = EntityStore()
                store.replaceAll(BedroomFixtures.states(.default), freshness: .live)
                let caller = LoggingResponder(BedroomGalleryRecorder(store: store))
                let publication = try (wake ? wakeEditorPublication(isNew: true) : editorPublication(routed: true))
                let renderer = try UKServerUIRenderer(publication: publication, context: UKContext(store: store, caller: caller),
                    backdrop: ServerUIRendererFixture.backdrop(), canEditBedroom: true)
                let window = HostedPage.show(renderer, size: HostedPage.inScene(size))
                defer { window.isHidden = true }
                var root = try ServerUIRendererFixture.root(renderer)
                if inModal {
                    renderer.activate(.present(modalId: "modal-swatch", arguments: .init(), ifPresented: .reject), from: root)
                    XCTAssertTrue(HostedPage.until {
                        guard let page = renderer.modal?.topViewController as? UKServerUIPage else { return false }
                        return renderer.isEnabled(.dismiss(scope: .currentModal), from: page)
                    })
                    root = try XCTUnwrap(renderer.modal?.topViewController as? UKServerUIPage)
                }
                let navigation: UINavigationController = try XCTUnwrap(inModal ? renderer.modal : renderer.stacks[root.root])
                let sourceID = wake ? "wake-editor-source" : "editor-source"
                let pageID = wake ? "wake-editor" : "alarm-editor"
                let push = ServerUICompositionDocument.Action.push(.init(
                    pageId: pageID, arguments: .init(), origin: .sender, duplicate: .reuseNearest))
                renderer.activate(push, from: root)
                XCTAssertTrue(HostedPage.until {
                    guard let page = navigation.topViewController as? UKServerUIPage else { return false }
                    return page.bedroomDrafts[sourceID] != nil && renderer.isEnabled(.back, from: page)
                })
                var editor: UKServerUIPage? = try XCTUnwrap(navigation.topViewController as? UKServerUIPage)
                let draft = try XCTUnwrap(editor?.bedroomDrafts[sourceID])
                let owner = try XCTUnwrap(renderer.bindings.bedroomRegistry?.sources[wake ? "authored-wake" : "authored-left"]?.session)
                XCTAssertFalse(draft.blocksExit)
                XCTAssertTrue(draft.protectsPublication, "A new draft still owns its inputs while its page is open.")
                let back = try XCTUnwrap(editor?.navigationItem.leftBarButtonItems?.first)
                try XCTUnwrap(back.primaryAction).performWithSender(back, target: nil)
                XCTAssertTrue(HostedPage.until { navigation.topViewController === root && renderer.isEnabled(push, from: root) })
                XCTAssertNil(FeatureHost.alert(on: renderer))
                XCTAssertTrue(HostedPage.until { owner.editors.isEmpty })
                XCTAssertTrue(draft.completed)
                XCTAssertFalse(owner.protectsPublication, "A departed pristine draft must not pin publication forever.")
                editor = nil
                XCTAssertTrue(caller.calls.isEmpty)
            }
        }
    }

    private func selectWeeklyWake(_ renderer: UKServerUIRenderer) throws {
        let collection = try XCTUnwrap(renderer.bindings.bedroomRegistry?.collections["authored-wake.alarms"])
        let record = try XCTUnwrap(collection.records.first {
            guard case .bedroom(let row, _) = $0, case .wake(let alarm) = row.alarm else { return false }
            return row.linked == nil && alarm.kind == .weekly
        })
        try collection.select(record)
    }

    private func wakeEditorPublication(isNew: Bool) throws -> ServerUICompositionPublication {
        var json = try ServerUIRendererFixture.authoredBedroom()
        let sources = try XCTUnwrap(json["document"]?["dataSources"]?.array) + [.object([
            "id": "wake-editor-source", "kind": "model", "model": "bedroom-provider@1",
            "inputs": .object(["providerId": .string(isNew ? "authored-wake.new-editor" : "authored-wake.editor"),
                              "kind": "wake-alarm-draft"]),
        ])]
        json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources", to: .array(sources))
        var kinds: Set<String> = []
        func control(_ id: String, _ kind: String, _ label: String, _ extra: [String: JSONValue] = [:]) -> JSONValue {
            kinds.insert(kind)
            return .object(["id": .string("editor-" + id), "type": "bedroom-control", "title": .string(label),
                "layout": .object(["span": .number(1)]), "props": .object(extra.merging([
                    "control": .string(kind), "sourceId": "wake-editor-source", "label": .string(label), "unavailableText": "Unavailable",
                ]) { _, value in value })])
        }
        let components: [JSONValue] = [
            control("errors", "alarm-feedback", "Alarm Error", ["parameter": "error"]),
            control("reload", "alarm-reload", "Open Latest Alarm, Replace Draft"),
            control("kind", "alarm-kind", "Alarm Type", ["showsHeading": .bool(true), "options": .array([
                .object(["value": "weekly", "label": "Scheduled"]), .object(["value": "once", "label": "One-Time"]),
            ])]),
            control("name", "alarm-name", "Alarm Name", ["showsHeading": .bool(true)]),
            control("days", "alarm-weekdays", "Days", ["options": .array(Weekday.allCases.map {
                .object(["value": .string($0.rawValue), "label": .string($0.shortLabel), "accessibilityLabel": .string($0.label)])
            })]),
            control("time", "alarm-time", "Wake Time"),
            control("date", "alarm-date", "Alarm Date"),
            control("ramp", "alarm-ramp", "Light Ramp Duration", ["options": .array(WakeLight.rampMinutes.map {
                .object(["value": .string(String($0)), "label": .string(WakeLight.durationLabel($0))])
            })]),
            control("enabled", "alarm-enabled", "Wake Alarm Enabled"),
            control("bed", "alarm-bed-target", "Add to Bed", ["parameter": "left"]),
            control("problems", "alarm-feedback", "Alarm Validation", ["parameter": "problems"]),
            control("save", "alarm-save", "Save"),
            control("delete", "alarm-delete", "Delete", ["confirmation": .object([
                "title": "Delete Alarm?", "message": "", "confirmLabel": "Delete", "cancelLabel": "Cancel",
            ])]),
        ]
        var pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        guard case .object(var editor) = pages[0] else { throw ServerUIRecordFailure.invalidValue }
        editor["id"] = "wake-editor"; editor["title"] = "Authored Alarm"; editor["titleSourceId"] = "wake-editor-source"
        editor["components"] = .array(components)
        pages.append(.object(editor))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages", to: .array(pages))
        let capabilities = try XCTUnwrap(json["capabilities"]?.array).compactMap(\.string)
            + kinds.map { "sh.\($0)@1" }
            + ["sh.surface-title-source@1", "sh.bedroom-field-headings@1", "sh.weekday-accessibility-labels@1"]
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities",
            to: .array(Set(capabilities).sorted().map(JSONValue.string)))
        return try ServerUIRendererFixture.publication(json)
    }

    private func editorPublication(routed: Bool = false) throws -> ServerUICompositionPublication {
        var json = try ServerUIRendererFixture.authoredBedroom()
        let sources = try XCTUnwrap(json["document"]?["dataSources"]?.array) + [
            JSONValue.object(["id": "editor-source", "kind": "model", "model": "bedroom-provider@1",
                "inputs": .object(["providerId": "authored-left.new-editor", "kind": "bed-alarm-draft"])]),
        ]
        json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources", to: .array(sources))
        let components = try XCTUnwrap(json["document"]?["pages"]?.array?.first?["components"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components + [
            .object(["id": "editor-time", "type": "bedroom-control", "title": "Alarm Time",
                "layout": .object(["span": .number(1)]), "props": .object(["sourceId": "editor-source", "control": "alarm-time",
                                                "label": "Alarm Time", "unavailableText": "Alarm unavailable"])]),
        ]))
        var capabilities = try XCTUnwrap(json["capabilities"]?.array).compactMap(\.string) + ["sh.alarm-time@1"]
        if routed {
            var pages = try XCTUnwrap(json["document"]?["pages"]?.array)
            guard case .object(var editor) = pages[0] else { throw ServerUIRecordFailure.invalidValue }
            editor["id"] = "alarm-editor"; editor["title"] = "Add Alarm"
            let time = try XCTUnwrap(editor["components"]?.array?.last)
            editor["components"] = .array([time, .object([
                "id": "editor-days", "type": "bedroom-control", "title": "Days", "layout": .object(["span": .number(1)]),
                "props": .object(["sourceId": "editor-source", "control": "alarm-weekdays", "label": "Days",
                    "unavailableText": "Unavailable", "options": .array(Weekday.allCases.map {
                        .object(["value": .string($0.rawValue), "label": .string($0.label)])
                    })]),
            ])])
            pages.append(.object(editor))
            json = try ServerUIRendererFixture.changing(json, path: "/document/pages", to: .array(pages))
            let action: JSONValue = .object(["type": "push", "pageId": "alarm-editor", "arguments": .object([:]),
                "origin": "sender", "duplicate": "reuse-nearest"])
            json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: .array(components + [
                .object(["id": "alarm-list", "type": "collection", "title": "Alarms", "layout": .object(["span": .number(1)]),
                    "props": .object(["providerId": "authored-left.day.monday", "template": "rows", "loadingText": "Loading",
                                      "emptyText": "No alarms"])]),
                .object(["id": "alarm-add", "type": "bedroom-control", "title": "Add Alarm", "layout": .object(["span": .number(1)]),
                    "props": .object(["sourceId": "left-source", "control": "alarm-add", "label": "Add Alarm",
                                      "unavailableText": "Unavailable", "action": action])]),
            ]))
            json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources", to: .array(sources + [
                .object(["id": "left-source", "kind": "model", "model": "bedroom-provider@1",
                         "inputs": .object(["providerId": "authored-left", "kind": "bed-side"])]),
            ]))
            json = try ServerUIRendererFixture.changing(json, path: "/document/dataSources/\(sources.count - 1)/inputs/providerId",
                                                        to: "authored-left.day.monday.new-editor")
            capabilities += ["sh.alarm-add@1", "sh.alarm-weekdays@1", "sh.collection@1"]
        }
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        return try ServerUIRendererFixture.publication(json)
    }

    func testRoleRefreshRebuildsIdleAuthoredProvidersButPreservesAnOwnedDraft() throws {
        let publication = try ServerUIRendererFixture.publication(ServerUIRendererFixture.authoredBedroom())
        let store = EntityStore()
        store.replaceAll(BedroomFixtures.states(.default), freshness: .live)
        let caller = LoggingResponder(BedroomGalleryRecorder(store: store))
        let backdrop = try ServerUIRendererFixture.backdrop()
        let renderer = try UKServerUIRenderer(publication: publication, context: UKContext(store: store, caller: caller),
                                              backdrop: backdrop, canEditBedroom: false)
        let original = try XCTUnwrap(renderer.deviceProviders.bedrooms["authored-bedroom"])
        XCTAssertFalse(original.devices.wakeLight.canEdit)
        try renderer.apply(publication: publication, backdrop: backdrop, canEditBedroom: true)
        let editable = try XCTUnwrap(renderer.deviceProviders.bedrooms["authored-bedroom"])
        XCTAssertFalse(editable === original)
        XCTAssertTrue(editable.devices.wakeLight.canEdit)
        let draft = try editable.editor(providerId: "authored-left", route: .addBed(.monday), visitId: "role-refresh")
        XCTAssertThrowsError(try renderer.apply(publication: publication, backdrop: backdrop, canEditBedroom: false))
        XCTAssertTrue(renderer.deviceProviders.bedrooms["authored-bedroom"] === editable)
        draft.discard()
        try editable.release(draft)
        try renderer.apply(publication: publication, backdrop: backdrop, canEditBedroom: false)
        XCTAssertFalse(try XCTUnwrap(renderer.deviceProviders.bedrooms["authored-bedroom"]).devices.wakeLight.canEdit)
        try renderer.apply(publication: publication, backdrop: ServerUIRendererFixture.backdrop())
        XCTAssertFalse(try XCTUnwrap(renderer.deviceProviders.bedrooms["authored-bedroom"]).devices.wakeLight.canEdit)
    }

    func testConfiguredWeekdayOrderAndLabelsPreserveCanonicalAccessibility() throws {
        let canonical = UKWeekdayPicker(title: nil, days: [], identifier: "canonical") { _ in }
        let canonicalChips = HostedPage.descendants(of: canonical).compactMap { $0 as? UKChipButton }
        XCTAssertEqual(canonicalChips.map(\.accessibilityLabel), Weekday.allCases.map { Optional($0.label) })
        let choices = Weekday.allCases.reversed().map { ($0, "Authored \($0.rawValue)") }
        let authored = UKWeekdayPicker(title: "Repeat", days: [.monday], choices: choices, identifier: "authored") { _ in }
        let authoredChips = HostedPage.descendants(of: authored).compactMap { $0 as? UKChipButton }
        XCTAssertEqual(authoredChips.map(\.accessibilityLabel), choices.map { Optional($0.1) })
    }

    private func publication() throws -> ServerUICompositionPublication {
        var root = try ServerUIRendererFixture.json()
        var sources = try XCTUnwrap(root["document"]?["dataSources"]?.array)
        sources.append(.object([
            "id": "bedroom-source", "kind": "model", "model": "bedroom-provider@1",
            "inputs": .object(["providerId": "synthetic-bed", "kind": "bed-side"])
        ]))
        root = try ServerUIRendererFixture.changing(root, path: "/document/dataSources", to: .array(sources))
        let control: JSONValue = .object([
            "id": "synthetic-power", "title": "Synthetic power", "type": "bedroom-control",
            "layout": .object(["span": .number(1)]),
            "props": .object([
                "control": "bed-power", "sourceId": "bedroom-source", "label": "Start synthetic side",
                "activeLabel": "Stop synthetic side", "unavailableText": "Synthetic side unavailable",
                "confirmation": .object(["title": "Stop this side?", "message": "", "confirmLabel": "Stop side", "cancelLabel": "Keep running"])
            ])
        ])
        var components = try XCTUnwrap(root["document"]?["pages"]?.array?.first?["components"]?.array)
        components.append(control)
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components", to: .array(components))
        root = try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array(
            (ServerUICompositionPublication.firstSliceCapabilities + ["sh.bedroom-sources@1", "sh.bed-power@1"]).sorted().map(JSONValue.string)))
        return try ServerUIRendererFixture.publication(root)
    }

    func testMissingInjectedProviderIsRejectedBeforeRendering() throws {
        let store = EntityStore()
        XCTAssertThrowsError(try UKServerUIRenderer(publication: publication(), context: UKContext(store: store),
                                                   backdrop: ServerUIRendererFixture.backdrop())) { error in
            XCTAssertEqual((error as? UKServerUIRendererError)?.code, .unavailableSource)
        }
    }

    func testPowerQuestionRevalidatesAndKeepsAccessibleControlsAcrossFamilies() throws {
        let sizes = [CGSize(width: 390, height: 844), CGSize(width: 440, height: 956),
                     CGSize(width: 960, height: 640), CGSize(width: 820, height: 1180)]
        for size in sizes {
            let store = EntityStore()
            store.replaceAll(BedroomFixtures.states(.default), freshness: .live)
            let log = LoggingResponder(BedroomGalleryRecorder(store: store))
            let devices = BedroomDevices(store: store, caller: log)
            let bed = devices.bed(.left)
            let publication = try publication()
            let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: store, caller: log),
                backdrop: ServerUIRendererFixture.backdrop(), bedroomProviders: ["synthetic-bed": .bed(bed)])
            let window = HostedPage.show(host, size: HostedPage.inScene(size))
            defer { window.isHidden = true }
            HostedPage.wait(0.1)
            let page = try ServerUIRendererFixture.root(host)
            let atom = try XCTUnwrap(page.nodes["synthetic-power"]?.view)
            let button = try XCTUnwrap(HostedPage.descendants(of: atom).compactMap { $0 as? UKGreyCapsuleButton }.first)
            XCTAssertEqual(button.accessibilityIdentifier, "synthetic-power.input")
            XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
            let before = log.calls.count
            button.sendActions(for: .touchUpInside)
            HostedPage.wait(0.1)
            XCTAssertEqual(log.calls.count, before)
            let alert = try XCTUnwrap(FeatureHost.alert(on: host))
            store.apply([EntityState(entityId: bed.config.climateEntityId, state: "off")])
            XCTAssertTrue(FeatureHost.answer(alert, "Stop side"))
            HostedPage.wait(0.1)
            XCTAssertEqual(log.calls.count, before, "A stale power-off confirmation must not act")
        }
    }
}

// MARK: - Authored bedroom acceptance fixture

extension ServerUIRendererFixture {
    static func authoredBedroom(useHouseIDs: Bool = false) throws -> JSONValue {
        let room = DemoHouse.config.bedroom
        // The document never names the room's scripts or topic: they resolve from the house document by role.
        let removed: Set<String> = ["tonightScript", "outsideScheduleScript", "scheduleSetTopic", "hotFlashBrokerScript",
                                    "householdAwayScript"]
        func encoded(_ value: some Encodable) throws -> JSONValue {
            let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
            guard case .object(let fields) = raw else { return raw }
            return .object(fields.filter { !removed.contains($0.key) })
        }
        let environment = try encoded(BedSideEnvironment(scheduleEntityId: room.scheduleEntityId,
            scheduleSetTopic: room.scheduleSetTopic, hotFlashBrokerScript: room.hotFlashBrokerScript,
            householdAwayEntityId: room.householdAwayEntityId, householdAwayScript: room.householdAwayScript,
            wakeLight: room.wakeLight))
        let wakeID = useHouseIDs ? room.wakeLight.id : "authored-wake"
        let beds: [JSONValue] = try room.beds.map {
            .object(["providerId": .string(useHouseIDs ? $0.id : "authored-" + $0.side.rawValue),
                     "configuration": try encoded($0)])
        }
        var root = try json()
        var sources = try XCTUnwrap(root["document"]?["dataSources"]?.array)
        sources.append(.object([
            "id": "authored-bedroom", "kind": "model", "model": "bedroom-config@1",
            "inputs": .object(["wakeProviderId": .string(wakeID), "beds": .array(beds), "environment": environment]),
        ]))
        sources.append(.object([
            "id": "authored-wake-source", "kind": "model", "model": "bedroom-provider@1",
            "inputs": .object(["providerId": .string(wakeID), "kind": "wake-light"]),
        ]))
        root = try changing(root, path: "/document/dataSources", to: .array(sources))
        return try changing(root, path: "/capabilities", to: .array(
            (ServerUICompositionPublication.firstSliceCapabilities + ["sh.bedroom-config@1", "sh.bedroom-sources@1"])
                .sorted().map(JSONValue.string)))
    }
}
