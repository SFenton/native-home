import Foundation
import HassTestSupport
import Testing
@testable import HassCore

private extension JSONValue {
    var object: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
}

// MARK: - Bedroom wire contract

@Suite struct ServerUIBedroomContractTests {
    typealias K = ServerUIBedroomControl.Kind
    typealias P = ServerUICompositionPublication

    func fixture(_ kind: K, wrongProvider: Bool = false, provider: ServerUIBedroomControl.ProviderKind? = nil) throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUICompositionFixture.json")
        var root = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        var document = try #require(root.object?["document"]?.object)
        var sources = try #require(document["dataSources"]?.array)
        sources.append(.object([
            "id": "bedroom-source", "kind": "model", "model": "bedroom-provider@1",
            "inputs": .object(["providerId": "synthetic-provider", "kind": .string(wrongProvider ? "wake-light" : (provider ?? kind.providers[0]).rawValue)])
        ]))
        document["dataSources"] = .array(sources)
        var pages = try #require(document["pages"]?.array)
        var page = try #require(pages[0].object)
        page["components"] = .array(try #require(page["components"]?.array) + [.object([
            "id": "bedroom-atom", "title": "Synthetic control", "type": "bedroom-control",
            "layout": .object(["span": .number(1)]), "props": .object(props(kind))
        ])])
        pages[0] = .object(page)
        document["pages"] = .array(pages)
        var object = try #require(root.object)
        object["document"] = .object(document)
        object["capabilities"] = .array((P.firstSliceCapabilities + ["sh.bedroom-sources@1", kind.capability]).sorted().map(JSONValue.string))
        root = .object(object)
        return root
    }

    func props(_ kind: K) -> [String: JSONValue] {
        var result: [String: JSONValue] = ["control": .string(kind.rawValue), "sourceId": "bedroom-source",
                                         "label": "Synthetic control", "unavailableText": "Unavailable"]
        if kind == .stage { result["parameter"] = "asleep" }
        if kind == .bedTarget { result["parameter"] = "left" }
        if kind == .feedback { result["parameter"] = "error" }
        if kind.usesNavigation {
            result["action"] = .object(["type": "push", "pageId": "page-echo", "arguments": .object([:]),
                "origin": "sender", "duplicate": "reuse-nearest"])
        }
        if kind == .reading {
            result["parameter"] = "pump-status"
            result["activeLabel"] = "Check synthetic pump"
            result["inactiveLabel"] = "Synthetic pump ready"
        }
        if kind == .mode || kind == .power { result["activeLabel"] = "Stop" }
        if kind == .mode {
            result["icon"] = .object(["type": "sf-symbol", "name": "snowflake", "rendering": "canonical", "unavailable": "reject"])
            result["family"] = "cooling"
            result["inactiveLabel"] = "Inactive"
            result["countdownSuffix"] = "remaining"
        }
        if kind.usesOptions {
            result["options"] = .array(ServerUIBedroomControl.allowedOptions(kind).reversed().map {
                .object(["value": .string($0), "label": .string("Choice \($0)")])
            })
        }
        if kind.usesConfirmation {
            result["confirmation"] = .object(["title": "Confirm?", "message": "", "confirmLabel": "Confirm", "cancelLabel": "Cancel"])
        }
        if kind.usesScope {
            result["scope"] = .object(["title": "Apply level?", "message": "", "tonightLabel": "Tonight",
                                      "allNightsLabel": "All nights", "cancelLabel": "Cancel"])
        }
        return result
    }

    func replacingProps(_ root: JSONValue, _ transform: (inout [String: JSONValue]) -> Void) throws -> JSONValue {
        var root = try #require(root.object)
        var document = try #require(root["document"]?.object)
        var pages = try #require(document["pages"]?.array)
        var page = try #require(pages[0].object)
        var components = try #require(page["components"]?.array)
        var node = try #require(components.last?.object)
        var props = try #require(node["props"]?.object)
        transform(&props)
        node["props"] = .object(props)
        components[components.count - 1] = .object(node)
        page["components"] = .array(components); pages[0] = .object(page)
        document["pages"] = .array(pages); root["document"] = .object(document)
        return .object(root)
    }

    @Test(arguments: K.allCases)
    func acceptsAtomicControlAndExactCapabilityClosure(_ kind: K) throws {
        let publication = try P.decode(JSONEncoder().encode(fixture(kind)))
        guard case .bedroom(let node) = publication.document.pages[0].surface.components.last else {
            Issue.record("Expected bedroom atom"); return
        }
        #expect(node.kind == kind)
        #expect(node.options.map(\.value) == (kind.usesOptions ? ServerUIBedroomControl.allowedOptions(kind).reversed().map { $0 } : []))
        #expect(publication.capabilities.contains(kind.capability))
        #expect(Set(publication.capabilities) == Set(P.firstSliceCapabilities + ["sh.bedroom-sources@1", kind.capability]))
    }

    @Test func rejectsWrongProviderAndMandatoryConfirmationRemoval() throws {
        #expect(throws: ServerUICompositionError(.bindingType, "/document/pages/0/components/1/props/sourceId")) {
            try P.decode(JSONEncoder().encode(fixture(.power, wrongProvider: true)))
        }
        let root = try replacingProps(fixture(.power)) { $0.removeValue(forKey: "confirmation") }
        #expect(throws: ServerUICompositionError(.missingRequired, "/document/pages/0/components/1/props/confirmation")) {
            try P.decode(JSONEncoder().encode(root))
        }
    }

    @Test func activeEpisodeRequiresItsCapabilityAndIsClosedToOtherControls() throws {
        let episode: JSONValue = .object(["heading": "Wake In Progress", "detail": "End this room's current wake.",
                                         "pendingLabel": "Ending Wake"])
        let extended = try replacingProps(fixture(.wakeStop)) { $0["episode"] = episode }
        #expect(throws: ServerUICompositionError.self) {
            try P.decode(JSONEncoder().encode(extended))
        }
        var root = try #require(extended.object)
        root["capabilities"] = .array((P.firstSliceCapabilities + [
            "sh.bedroom-sources@1", K.wakeStop.capability, "sh.wake-episode@1"
        ]).sorted().map(JSONValue.string))
        let publication = try P.decode(JSONEncoder().encode(JSONValue.object(root)))
        guard case .bedroom(let control) = publication.document.pages[0].surface.components.last else {
            Issue.record("Missing active-episode control"); return
        }
        #expect(control.episode?.heading == "Wake In Progress")
        #expect(control.episode?.detail == "End this room's current wake.")
        #expect(control.episode?.pendingLabel == "Ending Wake")
        let otherControl = try replacingProps(fixture(.wakeRamp)) { $0["episode"] = episode }
        #expect(throws: ServerUICompositionError(.unknownField, "/document/pages/0/components/1/props/episode")) {
            try P.decode(JSONEncoder().encode(otherControl))
        }
        let incomplete = try replacingProps(.object(root)) {
            $0["episode"] = .object(["heading": "Wake In Progress", "detail": "End this wake."])
        }
        #expect(throws: ServerUICompositionError(.missingRequired, "/document/pages/0/components/1/props/episode/pendingLabel")) {
            try P.decode(JSONEncoder().encode(incomplete))
        }
    }

    @Test func wakeConfirmationNegotiatesClosedFieldsAndRequiresAWakeDraft() throws {
        let confirmation: JSONValue = .object(["title": "Delete Alarm?", "message": "At {time}, {schedule}.",
            "confirmLabel": "Delete Alarm", "cancelLabel": "Cancel", "messageFormat": "wake-alarm"])
        let extended = try replacingProps(fixture(.delete, provider: .wakeDraft)) { $0["confirmation"] = confirmation }
        #expect(throws: ServerUICompositionError.self) { try P.decode(JSONEncoder().encode(extended)) }
        var root = try #require(extended.object)
        root["capabilities"] = .array((try #require(root["capabilities"]?.array).compactMap(\.string)
            + ["sh.wake-alarm-confirmation@1"]).sorted().map(JSONValue.string))
        let publication = try P.decode(JSONEncoder().encode(JSONValue.object(root)))
        guard case .bedroom(let control) = publication.document.pages[0].surface.components.last else {
            Issue.record("Missing delete control"); return
        }
        let question = try #require(control.confirmation)
        let alarm = WakeLight.Alarm.new(id: "example", kind: .weekly)
        #expect(question.message(for: alarm) == "At 7:00 AM, Weekdays.")
        var literal = question
        literal.messageFormat = nil
        #expect(literal.message(for: alarm) == "At {time}, {schedule}.")
        for message in ["At {unknown}.", "At {time."] {
            var fields = try #require(confirmation.object)
            fields["message"] = .string(message)
            let invalid = try replacingProps(.object(root)) {
                $0["confirmation"] = .object(fields)
            }
            #expect(throws: ServerUICompositionError(.invalidCombination, "/document/pages/0/components/1/props/confirmation/message")) {
                try P.decode(JSONEncoder().encode(invalid))
            }
        }
        let wrongProvider = try replacingProps(fixture(.delete)) { $0["confirmation"] = confirmation }
        var wrong = try #require(wrongProvider.object)
        wrong["capabilities"] = root["capabilities"]
        #expect(throws: ServerUICompositionError(.bindingType, "/document/pages/0/components/1/props/sourceId")) {
            try P.decode(JSONEncoder().encode(JSONValue.object(wrong)))
        }
        let power = try replacingProps(fixture(.power)) { $0["confirmation"] = confirmation }
        #expect(throws: ServerUICompositionError(.unknownField, "/document/pages/0/components/1/props/confirmation/messageFormat")) {
            try P.decode(JSONEncoder().encode(power))
        }
    }

    @Test(arguments: [K.name, .alarmKind])
    func fieldHeadingsRequireNegotiationAndRemainOptional(_ kind: K) throws {
        let extended = try replacingProps(fixture(kind)) { $0["showsHeading"] = .bool(true) }
        #expect(throws: ServerUICompositionError.self) { try P.decode(JSONEncoder().encode(extended)) }
        var root = try #require(extended.object)
        root["capabilities"] = .array((try #require(root["capabilities"]?.array).compactMap(\.string)
            + ["sh.bedroom-field-headings@1"]).sorted().map(JSONValue.string))
        let publication = try P.decode(JSONEncoder().encode(JSONValue.object(root)))
        guard case .bedroom(let value) = publication.document.pages[0].surface.components.last else {
            Issue.record("Missing alarm field"); return
        }
        #expect(value.showsHeading)
        let wrongKind = try replacingProps(fixture(.enabled)) { $0["showsHeading"] = .bool(true) }
        #expect(throws: ServerUICompositionError(.unknownField, "/document/pages/0/components/1/props/showsHeading")) {
            try P.decode(JSONEncoder().encode(wrongKind))
        }
    }

    @Test func abbreviatedWeekdaysPreserveNegotiatedSpokenLabels() throws {
        let extended = try replacingProps(fixture(.weekdays)) {
            $0["options"] = .array(Weekday.allCases.map {
                .object(["value": .string($0.rawValue), "label": .string($0.shortLabel),
                         "accessibilityLabel": .string($0.label)])
            })
        }
        #expect(throws: ServerUICompositionError.self) { try P.decode(JSONEncoder().encode(extended)) }
        var root = try #require(extended.object)
        root["capabilities"] = .array((try #require(root["capabilities"]?.array).compactMap(\.string)
            + ["sh.weekday-accessibility-labels@1"]).sorted().map(JSONValue.string))
        let publication = try P.decode(JSONEncoder().encode(JSONValue.object(root)))
        guard case .bedroom(let value) = publication.document.pages[0].surface.components.last else {
            Issue.record("Missing weekday picker"); return
        }
        #expect(value.options.map(\.label) == Weekday.allCases.map(\.shortLabel))
        #expect(value.options.map(\.accessibilityLabel) == Weekday.allCases.map(\.label))
    }

    @Test func surfaceTitleRequiresAnOwnedTypedDraftAndNegotiation() throws {
        var root = try #require(fixture(.name).object)
        var document = try #require(root["document"]?.object)
        var pages = try #require(document["pages"]?.array)
        var page = try #require(pages[0].object)
        page["titleSourceId"] = "bedroom-source"
        pages[0] = .object(page); document["pages"] = .array(pages); root["document"] = .object(document)
        #expect(throws: ServerUICompositionError.self) { try P.decode(JSONEncoder().encode(JSONValue.object(root))) }
        root["capabilities"] = .array((try #require(root["capabilities"]?.array).compactMap(\.string)
            + ["sh.surface-title-source@1"]).sorted().map(JSONValue.string))
        let publication = try P.decode(JSONEncoder().encode(JSONValue.object(root)))
        #expect(publication.document.pages[0].surface.titleSourceId == "bedroom-source")
        page["titleSourceId"] = "unowned-source"
        pages[0] = .object(page); document["pages"] = .array(pages); root["document"] = .object(document)
        #expect(throws: ServerUICompositionError(.invalidCombination, "/document/pages/0/titleSourceId")) {
            try P.decode(JSONEncoder().encode(JSONValue.object(root)))
        }
        var liveRoot = try #require(fixture(.wakeStop).object)
        var liveDocument = try #require(liveRoot["document"]?.object)
        var livePages = try #require(liveDocument["pages"]?.array)
        var livePage = try #require(livePages[0].object)
        livePage["titleSourceId"] = "bedroom-source"
        livePages[0] = .object(livePage); liveDocument["pages"] = .array(livePages); liveRoot["document"] = .object(liveDocument)
        liveRoot["capabilities"] = .array((try #require(liveRoot["capabilities"]?.array).compactMap(\.string)
            + ["sh.surface-title-source@1"]).sorted().map(JSONValue.string))
        #expect(throws: ServerUICompositionError(.bindingType, "/document/pages/0/titleSourceId")) {
            try P.decode(JSONEncoder().encode(JSONValue.object(liveRoot)))
        }
    }

    @Test func linkedCollectionsNegotiateHandoffAndRejectDuplicateSides() throws {
        var root = try #require(fixture(.wakeTile).object)
        var document = try #require(root["document"]?.object)
        var pages = try #require(document["pages"]?.array)
        var page = try #require(pages[0].object)
        let modalID = try #require(document["modals"]?.array?.first?.object?["id"])
        let link: JSONValue = .object(["side": "left", "label": "Open Linked-Device Alarm Editor",
            "action": .object(["type": "present", "modalId": modalID, "arguments": .object([:]), "ifPresented": "replace"])])
        var props: [String: JSONValue] = ["providerId": "synthetic-provider.alarms", "template": "rows",
            "loadingText": "Loading", "emptyText": "No alarms", "bedroomLinks": .array([link])]
        var node: [String: JSONValue] = ["id": "linked-schedule", "title": "Wake Alarms", "type": "collection",
            "layout": .object(["span": .number(1)]), "props": .object(props)]
        var components = try #require(page["components"]?.array)
        components[components.count - 1] = .object(node)
        page["components"] = .array(components); pages[0] = .object(page)
        document["pages"] = .array(pages); root["document"] = .object(document)
        root["capabilities"] = .array((P.firstSliceCapabilities + ["sh.bedroom-sources@1", "sh.collection@1",
            "sh.bedroom-collection-links@1", "sh.modal-handoff@1"]).sorted().map(JSONValue.string))
        let publication = try P.decode(JSONEncoder().encode(JSONValue.object(root)))
        guard case .collection(let collection) = publication.document.pages[0].surface.components.last else {
            Issue.record("Expected linked alarm collection"); return
        }
        #expect(collection.bedroomLinks.first?.action == .present(modalId: modalID.string ?? "", arguments: .init(), ifPresented: .replace))
        props["bedroomLinks"] = .array([link, link]); node["props"] = .object(props)
        components[components.count - 1] = .object(node); page["components"] = .array(components)
        pages[0] = .object(page); document["pages"] = .array(pages); root["document"] = .object(document)
        #expect(throws: ServerUICompositionError(.invalidCombination, "/document/pages/0/components/1/props/bedroomLinks")) {
            try P.decode(JSONEncoder().encode(JSONValue.object(root)))
        }
    }

    @Test(arguments: [["monday"], ["monday", "monday"]])
    func rejectsDuplicateChoicesAndMissingWeekdays(_ days: [String]) throws {
        let root = try replacingProps(fixture(.weekdays)) {
            $0["options"] = .array(days.map { .object(["value": .string($0), "label": "M"]) })
        }
        #expect(throws: ServerUICompositionError(.invalidCombination, "/document/pages/0/components/1/props/options")) {
            try P.decode(JSONEncoder().encode(root))
        }
    }
}

// MARK: - Command and draft lifetime

@Suite(.demoHouse)
@MainActor
struct ServerUIBedroomDraftTests {
    @Test func mirroredWakeRowsToggleOnlyLinksAndRouteToTheirOwningBed() async throws {
        let caller = ResponseCaller()
        let controller = WakeLightController(config: MasterBedroom.wakeLight, store: bedroomStore([wakeStatus()]),
            caller: caller, scheduler: ManualScheduler())
        let collection = ServerUIBedroomAlarms(source: .wake(controller))
        let row = try #require(collection.rows().first { $0.linked != nil })
        #expect(try collection.route(for: row) == .linkedBed(.left))
        #expect(row.linked == true)
        #expect(try await collection.toggle(row, enabled: false))
        #expect(caller.calls.last?.data["operation"] as? String == "link_alarm")
        #expect(throws: ServerUIBedroomAlarms.Failure.staleRow) {
            try collection.route(for: row)
        }
    }

    @Test func pinsInjectedBedEnvironmentAcrossTransportAndOptimisticEcho() async {
        let scheduler = ManualScheduler()
        let caller = ResponseCaller()
        let config = MasterBedroom.bed(.left)
        let environment = BedSideEnvironment(scheduleEntityId: "sensor.demo_schedule", scheduleSetTopic: "synthetic/schedule",
            hotFlashBrokerScript: "demo_broker", householdAwayEntityId: "sensor.demo_away",
            householdAwayScript: "synthetic_away", wakeLight: MasterBedroom.wakeLight)
        let controller = BedSideController(config: config, store: bedroomStore(bedEntities()), caller: caller,
            environment: environment, scheduler: scheduler)
        controller.setPower(on: false)
        #expect(controller.hasPendingCommands)
        await controller.waitForCalls()
        #expect(caller.names == ["script.demo_broker"])
        #expect(controller.hasPendingCommands)
        scheduler.fireAll()
        #expect(!controller.hasPendingCommands)
    }

    @Test func failedWakeSaveKeepsDraftAndReadOnlyCannotSend() async {
        let caller = ResponseCaller()
        caller.fail = true
        let controller = WakeLightController(config: MasterBedroom.wakeLight, store: bedroomStore([wakeStatus()]),
            caller: caller, scheduler: ManualScheduler())
        let alarm = controller.snapshot.alarms[0]
        let draft = ServerUIBedroomDraft.wake(controller: controller, alarm: alarm, isNew: false) { await controller.save($0) }
        var edited = alarm
        edited.label = "Synthetic changed"
        draft.update { $0 = .wake(edited) }
        #expect(await draft.save() == false)
        #expect(draft.value == .wake(edited))
        #expect(draft.dirty && draft.protectsPublication && draft.error != nil)
        #expect(draft.feedbackError == controller.error)
        let calls = caller.calls.count
        controller.canEdit = false
        #expect(await draft.save() == false)
        #expect(caller.calls.count == calls)
    }

    @Test func deletionRevalidatesCompleteDraftAndExplicitReloadReplacesIt() async {
        let caller = ResponseCaller()
        let controller = WakeLightController(config: MasterBedroom.wakeLight, store: bedroomStore([wakeStatus()]),
            caller: caller, scheduler: ManualScheduler())
        let alarm = controller.snapshot.alarms[0]
        let draft = ServerUIBedroomDraft.wake(controller: controller, alarm: alarm, isNew: false) { await controller.save($0) }
        let ticket = draft.value
        var edited = alarm
        edited.localTime = "08:40"
        draft.update { $0 = .wake(edited) }
        #expect(await draft.delete(confirming: ticket) == false)
        #expect(caller.calls.isEmpty)
        #expect(draft.reload())
        #expect(draft.value == ticket)
        #expect(!draft.dirty)
    }

    @Test func staleDraftOffersExplicitReloadAndKeepsItsOpenedTitleUntilThen() throws {
        let store = bedroomStore([wakeStatus()])
        let controller = WakeLightController(config: MasterBedroom.wakeLight, store: store,
            caller: ResponseCaller(), scheduler: ManualScheduler())
        let alarm = try #require(controller.snapshot.alarms.first)
        let draft = ServerUIBedroomDraft.wake(controller: controller, alarm: alarm, isNew: false) { await controller.save($0) }
        draft.update {
            guard case .wake(var value) = $0 else { return }
            value.label = "Unsaved name"
            value.localTime = "09:17"
            $0 = .wake(value)
        }
        #expect(draft.presentationTitle == alarm.label)
        #expect(draft.openedWakeAlarm == alarm)
        #expect(!draft.needsReload)
        var status = try #require(store.value(controller.config.statusEntityId))
        var alarms = try #require(status.attributes["alarms"]?.array)
        var latest = try #require(alarms[0].object)
        latest["label"] = "Latest server name"
        latest["revision"] = .number(Double(alarm.revision + 1))
        alarms[0] = .object(latest)
        status.attributes["alarms"] = .array(alarms)
        store.apply([status])
        #expect(draft.needsReload && !draft.canSave)
        #expect(draft.presentationTitle == alarm.label)
        #expect(draft.reload())
        #expect(draft.presentationTitle == "Latest server name")
        #expect(draft.openedWakeAlarm?.label == "Latest server name")
        #expect(!draft.needsReload && !draft.dirty)
    }

    @Test func invalidUnsavedFieldsDoNotPreventDeletingTheExistingAlarm() async {
        let caller = ResponseCaller()
        let controller = WakeLightController(config: MasterBedroom.wakeLight, store: bedroomStore([wakeStatus()]),
            caller: caller, scheduler: ManualScheduler())
        let alarm = controller.snapshot.alarms[0]
        let draft = ServerUIBedroomDraft.wake(controller: controller, alarm: alarm, isNew: false) { await controller.save($0) }
        var invalid = alarm
        invalid.localTime = "99:99"
        draft.update { $0 = .wake(invalid) }
        #expect(!draft.canSave)
        #expect(await draft.delete(confirming: draft.value))
        #expect(caller.calls.last?.data["operation"] as? String == "delete_alarm")
    }

    @Test func busySavePinsTheCapturedDraftAndItsOptimisticCommandLifetime() async {
        let caller = ResponseCaller()
        caller.hold = true
        let scheduler = ManualScheduler()
        let controller = WakeLightController(config: MasterBedroom.wakeLight, store: bedroomStore([wakeStatus()]),
            caller: caller, scheduler: scheduler, timeout: patientTimeout)
        let alarm = controller.snapshot.alarms[0]
        let draft = ServerUIBedroomDraft.wake(controller: controller, alarm: alarm, isNew: false) { await controller.save($0) }
        var edited = alarm
        edited.label = "Pinned synthetic alarm"
        draft.update { $0 = .wake(edited) }
        let captured = draft.value
        let work = Task { await draft.save() }
        await Task.yield()
        #expect(draft.busy)
        #expect(!draft.discard())
        draft.update { $0 = .wake(alarm) }
        #expect(draft.value == captured)
        #expect(draft.protectsPublication)
        caller.release()
        #expect(await work.value)
        #expect(draft.completed && !draft.busy)
        #expect(draft.protectsPublication)
        scheduler.fireAll()
        #expect(!draft.protectsPublication)
    }

    @Test func explicitDiscardReleasesAnUnsavedDraftWithoutSending() {
        let caller = ResponseCaller()
        let controller = WakeLightController(config: MasterBedroom.wakeLight, store: bedroomStore([wakeStatus()]),
            caller: caller, scheduler: ManualScheduler())
        let alarm = controller.snapshot.alarms[0]
        let draft = ServerUIBedroomDraft.wake(controller: controller, alarm: alarm, isNew: false) { await controller.save($0) }
        draft.update { value in
            guard case .wake(var alarm) = value else { return }
            alarm.label = "Unsaved synthetic change"
            value = .wake(alarm)
        }
        #expect(draft.protectsPublication)
        #expect(draft.discard())
        #expect(draft.value == .wake(alarm))
        #expect(draft.completed && !draft.protectsPublication)
        #expect(caller.calls.isEmpty)
    }

    @Test func equivalentWakeFieldEditsDoNotCreateAPhantomDiscardPrompt() throws {
        let controller = WakeLightController(config: MasterBedroom.wakeLight, store: bedroomStore([wakeStatus()]),
            caller: ResponseCaller(), scheduler: ManualScheduler())
        let alarm = try #require(controller.snapshot.alarms.first)
        let draft = ServerUIBedroomDraft.wake(controller: controller, alarm: alarm, isNew: false) { await controller.save($0) }
        draft.update {
            guard case .wake(var value) = $0 else { return }
            value.label = " " + value.label + " "
            value.weekdays.reverse()
            $0 = .wake(value)
        }
        #expect(!draft.dirty && !draft.blocksExit && !draft.canSave)
        draft.update {
            guard case .wake(var value) = $0 else { return }
            value.enabled.toggle()
            $0 = .wake(value)
        }
        #expect(draft.dirty && draft.blocksExit)
    }
}
